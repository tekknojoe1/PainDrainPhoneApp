import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'cyacd2_file.dart';
import 'dfu_protocol.dart';

/// How a DFU transfer ended.
enum DfuResultType {
  /// Image fully programmed and verified; the device is resetting into the new
  /// slot (the BLE drop after this is expected, not an error).
  success,

  /// The device rejected a write to its running slot early in the transfer —
  /// i.e. the wrong slot file was sent (or it is already up to date). The
  /// device is unharmed and still on its current firmware. Re-read the DIS and
  /// retry with the correct slot file.
  wrongSlot,

  /// A genuine transfer failure (framing, verify, timeout, BLE error).
  failed,
}

class DfuResult {
  const DfuResult(this.type, {this.message});
  final DfuResultType type;
  final String? message;

  bool get isSuccess => type == DfuResultType.success;
}

/// Cancellation signal a caller can flip to abort an in-flight transfer.
class DfuCancelToken {
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  bool get isCancelled => _cancelled;
}

/// Drives the Cypress/Infineon DFU host protocol over a single BLE
/// characteristic (the Bootloader Service "command" characteristic, which is
/// Write / Write-Without-Response + Notify).
///
/// The notification CCCD must already be enabled by the caller (the service
/// layer does this) so [BluetoothCharacteristic.onValueReceived] delivers the
/// device's response packets.
class DfuTransfer {
  DfuTransfer({
    required this.characteristic,
    required this.productId,
    this.codec = const DfuCodec(),
    this.mtu = 23,
    this.includeRowCrc = true,
    // Pipelining (window > 1) deterministically corrupts a write on this
    // bootloader/BLE-stack once a row's burst passes ~37 packets (ERR_CHECKSUM
    // at a fixed offset, unrecoverable by Sync+retry), whereas serial sends all
    // 39 Send Data per row reliably. So default to serial; the real speed fix is
    // a larger device MTU (CY_BLE_CONFIG_GATT_MTU), which cuts the packet count.
    this.inFlightWindow = 1,
    this.maxRowRetries = 3,
    this.responseTimeout = const Duration(seconds: 5),
    this.log,
  });

  /// Bootloader Service command characteristic (notify + write).
  final BluetoothCharacteristic characteristic;

  /// Device product ID, sent with Enter DFU (PainDrain = 0x01020304).
  final int productId;

  final DfuCodec codec;

  /// Negotiated ATT MTU. The bootloader characteristic does NOT accept queued
  /// (long) writes — only the small Enter/Metadata/Verify packets (≤ MTU-3)
  /// were getting through, while the first >MTU-3 row write was rejected. So
  /// every DFU packet, including row data, is chunked to fit a single write of
  /// at most MTU-3 bytes. A larger negotiated MTU simply means bigger (faster)
  /// chunks.
  final int mtu;

  /// Largest single BLE write payload: ATT MTU minus the 3-byte ATT header,
  /// bounded by the 512-byte attribute limit.
  int get _maxPacket => (mtu - 3).clamp(20, 512);

  /// Whether Program/Verify Data carry a CRC-32 of the row. The cy_bootload
  /// Program Data command is [address 4][row CRC-32 4][data]; omitting the CRC
  /// makes the device read the first 4 data bytes as the CRC and reject the
  /// row as ERR_LENGTH. So this is `true` (CRC is CRC-32C, see dfuRowCrc32).
  final bool includeRowCrc;

  final Duration responseTimeout;
  final void Function(String message)? log;

  /// Maximum number of row packets sent before their status notifications are
  /// awaited (flow-controlled pipelining). 1 is fully serial; a small window
  /// overlaps round-trips for speed without overrunning the bootloader (an
  /// unbounded blast corrupts its packet buffer -> ERR_CHECKSUM).
  final int inFlightWindow;

  /// How many times to Sync + re-send a row that fails with a recoverable error
  /// (e.g. a checksum/length error from a dropped or out-of-order packet under
  /// pipelining) before giving up.
  final int maxRowRetries;

  StreamSubscription<List<int>>? _sub;
  final List<int> _rxBuffer = [];

  /// Outstanding command responses, in send order. Pipelining (firing several
  /// writes before awaiting their notifications) relies on the device
  /// responding in order, so responses are matched to writes FIFO.
  final Queue<Completer<DfuResponse>> _pending = Queue();

  /// Runs the full Enter -> (Set Metadata) -> Program rows -> Verify -> Exit
  /// sequence for [image]. Reports fraction-complete (0..1) via [onProgress].
  Future<DfuResult> run(
    Cyacd2File image, {
    void Function(double progress)? onProgress,
    DfuCancelToken? cancelToken,
  }) async {
    _listen();
    try {
      final appId = image.appId ?? 0;

      // --- Enter DFU -------------------------------------------------------
      // The product id is carried in the .cyacd2 header; fall back to the
      // configured one if the header is the short 7-byte form.
      final enter = await _send(
        DfuCommand.enter,
        u32le(image.productId ?? productId),
      );
      if (!enter.isSuccess) {
        return _fail('Enter DFU rejected: ${_statusDetail(enter.status)}');
      }
      log?.call('Entered DFU; programming ${image.rows.length} rows '
          '(appId $appId, ${image.totalDataBytes} bytes)');

      // --- Set Application Metadata (app start + size from @APPINFO) --------
      if (image.appInfoAddress != null && image.appInfoSize != null) {
        // Layout: [appId 1][appStart 4][appSize 4] — appId is the slot the
        // image was linked for (header byte 7).
        final meta = <int>[
          appId,
          ...u32le(image.appInfoAddress!),
          ...u32le(image.appInfoSize!),
        ];
        final metaResp = await _send(DfuCommand.setAppMetadata, meta);
        if (!metaResp.isSuccess) {
          return _fail(
            'Set metadata failed: ${_statusDetail(metaResp.status)}',
          );
        }
      }

      // --- Set EIV if the image is encrypted -------------------------------
      if (image.eiv != null && image.eiv!.isNotEmpty) {
        final eivResp = await _send(DfuCommand.setEiv, image.eiv!);
        if (!eivResp.isSuccess) {
          return _fail('Set EIV failed: ${_statusDetail(eivResp.status)}');
        }
      }

      // --- Program every row ----------------------------------------------
      final totalBytes = image.totalDataBytes;
      var sentBytes = 0;
      for (var rowIndex = 0; rowIndex < image.rows.length; rowIndex++) {
        if (cancelToken?.isCancelled ?? false) {
          return _fail('Cancelled by user');
        }
        final row = image.rows[rowIndex];

        // Pipelining can occasionally desync the bootloader (a dropped/extra
        // notification or an overrun) -> a checksum/length error. Recover by
        // issuing a Sync (resets the device's receive state) and re-sending the
        // whole row, since its accumulation is discarded.
        var r = await _programRow(row);
        var attempt = 0;
        while (r.status != DfuStatus.success &&
            r.status != DfuStatus.errRowAccess &&
            attempt < maxRowRetries) {
          attempt++;
          log?.call('Row $rowIndex ${r.where} -> ${_statusDetail(r.status)}; '
              'resync + retry $attempt/$maxRowRetries');
          await _resync();
          r = await _programRow(row);
        }

        if (r.status != DfuStatus.success) {
          // The device's row-access rejection means it refused a write into its
          // running slot: wrong slot file (or already up to date). The device is
          // unharmed and stays on its current firmware. Anything else is a
          // genuine failure — surface it (status code, failing sub-command, MTU)
          // so it is not silently swallowed.
          if (r.status == DfuStatus.errRowAccess) {
            log?.call('Row $rowIndex row-access denied -> wrong slot file');
            return DfuResult(
              DfuResultType.wrongSlot,
              message: 'Device refused the write at row $rowIndex '
                  '(${_statusDetail(r.status)}) — wrong slot file or already up '
                  'to date.',
            );
          }
          return _fail(
            'Row $rowIndex ${r.where} failed after $attempt retries: '
            '${_statusDetail(r.status)} [MTU $mtu]',
          );
        }

        sentBytes += row.data.length;
        if (totalBytes > 0) {
          onProgress?.call(sentBytes / totalBytes);
        }
      }

      // --- Verify Application ---------------------------------------------
      final verify = await _send(DfuCommand.verifyApp, [appId]);
      if (!verify.isSuccess) {
        return _fail('Verify application failed: '
            '${_statusDetail(verify.status)}');
      }

      // --- Exit (device resets and boots the new slot) --------------------
      // Exit is fire-and-forget: the device resets immediately, so a response
      // / the BLE drop here is expected and means success.
      try {
        await _send(DfuCommand.exit, const [], expectResponse: false);
      } catch (_) {
        // Connection dropping mid-Exit is the normal success path.
      }

      onProgress?.call(1.0);
      return const DfuResult(DfuResultType.success);
    } on TimeoutException {
      return _fail('Timed out waiting for the device to respond');
    } catch (e) {
      return _fail('DFU error: $e');
    } finally {
      await _stop();
    }
  }

  /// Programs one row: stream all but the final piece via Send Data, then commit
  /// with Program Data ([address][crc?][last piece]). Every packet is sized to a
  /// single MTU-bounded write.
  ///
  /// The whole row is *pipelined*: all packets are fired back-to-back (paced by
  /// the BLE write hand-off, so several ride each connection interval) and their
  /// status notifications are awaited afterward, in order. This is what makes a
  /// row take roughly one batch of writes instead of ~40 serial round-trips.
  /// Returns the DFU status plus a short description of the failing command.
  Future<({int status, String where})> _programRow(Cyacd2Row row) async {
    final data = row.data;
    final sendChunk = _maxPacket - 7; // framing
    final progOverhead = 7 + 4 + (includeRowCrc ? 4 : 0); // framing+addr+crc
    final progChunk = _maxPacket - progOverhead;
    if (progChunk < 1) {
      return (status: DfuStatus.errLength, where: 'MTU $mtu too small');
    }

    // Reserve the last progChunk bytes for the Program Data packet; stream the
    // rest with Send Data.
    final progTail = math.min(progChunk, data.length);
    final sendEnd = data.length - progTail;

    // Build the row's ordered packet list.
    final packets = <({int command, List<int> data, String where})>[];
    var offset = 0;
    while (offset < sendEnd) {
      final n = math.min(sendChunk, sendEnd - offset);
      packets.add((
        command: DfuCommand.sendData,
        data: data.sublist(offset, offset + n),
        where: 'SendData @$offset ${n}B',
      ));
      offset += n;
    }
    packets.add((
      command: DfuCommand.programData,
      data: <int>[
        ...u32le(row.address),
        if (includeRowCrc) ...u32le(dfuRowCrc32(data)),
        ...data.sublist(sendEnd),
      ],
      where: 'ProgramData ${progTail}B',
    ));

    // Send with a bounded in-flight window: keep at most [inFlightWindow]
    // packets outstanding, awaiting the oldest response before firing more.
    final inFlight = Queue<({Future<DfuResponse> future, String where})>();
    ({int status, String where})? failure;

    Future<void> awaitOldest() async {
      final r = inFlight.removeFirst();
      if (failure != null) {
        r.future.then((_) {}, onError: (_) {}); // swallow; row already failed
        return;
      }
      try {
        final resp = await r.future.timeout(responseTimeout);
        if (!resp.isSuccess) failure = (status: resp.status, where: r.where);
      } on TimeoutException {
        failure = (status: DfuStatus.errUnknown, where: '${r.where} (timeout)');
      }
    }

    for (final p in packets) {
      if (failure != null) break;
      final future =
          await _fire(p.command, p.data, withoutResponseWrite: true);
      inFlight.add((future: future, where: p.where));
      if (inFlight.length >= inFlightWindow) await awaitOldest();
    }
    while (inFlight.isNotEmpty) {
      await awaitOldest();
    }

    return failure ?? (status: DfuStatus.success, where: 'row');
  }

  // --- BLE transport ------------------------------------------------------

  void _listen() {
    _sub = characteristic.onValueReceived.listen(_onData);
  }

  void _onData(List<int> value) {
    _rxBuffer.addAll(value);
    // A response is [SOP][status][lenLo][lenHi][data][cksum 2][EOP]. The device
    // may pack several responses into one notification when pipelined, so drain
    // every complete frame and match each to the next outstanding write.
    while (true) {
      if (_rxBuffer.length < 7) return;
      final length = _rxBuffer[2] | (_rxBuffer[3] << 8);
      final expected = 7 + length;
      if (_rxBuffer.length < expected) return;

      final frame = _rxBuffer.sublist(0, expected);
      _rxBuffer.removeRange(0, expected);

      if (_pending.isEmpty) continue; // unexpected/extra response — discard
      final completer = _pending.removeFirst();
      if (completer.isCompleted) continue;
      try {
        completer.complete(codec.parseResponse(frame));
      } catch (e) {
        completer.completeError(e);
      }
    }
  }

  /// Writes one command packet and returns a future for its status
  /// notification, without awaiting it — so callers can fire several packets
  /// back-to-back (pipelining) and await the responses afterward. The write
  /// itself is awaited, which paces sending to the BLE link rate.
  ///
  /// Packets are pre-chunked to fit MTU-3 (the bootloader rejects queued/long
  /// writes), and [withoutResponseWrite] skips the ATT write-ack for throughput;
  /// the bootloader's status notification is still what we match on.
  Future<Future<DfuResponse>> _fire(
    int command,
    List<int> data, {
    bool withoutResponseWrite = false,
  }) async {
    final packet = codec.buildPacket(command, data);
    final completer = Completer<DfuResponse>();
    _pending.add(completer);
    await characteristic.write(packet, withoutResponse: withoutResponseWrite);
    return completer.future;
  }

  /// Sends a single command and awaits its response (used for the one-off
  /// Enter / Set Metadata / Verify commands; row data is pipelined instead).
  Future<DfuResponse> _send(
    int command,
    List<int> data, {
    bool expectResponse = true,
  }) async {
    if (!expectResponse) {
      // Fire-and-forget (Exit): the device resets immediately, so the ATT
      // response may never arrive — write without response.
      await characteristic.write(
        codec.buildPacket(command, data),
        withoutResponse: true,
      );
      return DfuResponse(status: DfuStatus.success, data: Uint8List(0));
    }
    final response = await _fire(command, data);
    return response.timeout(responseTimeout);
  }

  /// "<description> (0xNN)" — always includes the raw status code so unexpected
  /// rejections can be diagnosed from the UI message alone.
  String _statusDetail(int status) =>
      '${DfuStatus.describe(status)} '
      '(0x${status.toRadixString(16).padLeft(2, '0')})';

  DfuResult _fail(String message) {
    log?.call(message);
    return DfuResult(DfuResultType.failed, message: message);
  }

  /// Recovers the bootloader's receive state after a row failure: abandons any
  /// outstanding responses, sends the Sync command (which resets the device's
  /// command parser and discards its partial row buffer), and drops any stale
  /// notifications. After this the row can be re-sent cleanly.
  Future<void> _resync() async {
    for (final completer in _pending) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('resync'));
      }
    }
    _pending.clear();
    _rxBuffer.clear();
    try {
      await characteristic.write(
        codec.buildPacket(DfuCommand.sync),
        withoutResponse: true,
      );
    } catch (_) {
      // Best effort — Sync has no response and the device may be mid-reset.
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _rxBuffer.clear(); // discard notifications from the aborted row
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    _rxBuffer.clear();
    for (final completer in _pending) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('DFU transfer stopped'));
      }
    }
    _pending.clear();
  }
}
