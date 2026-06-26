import 'dart:async';
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

  StreamSubscription<List<int>>? _sub;
  final List<int> _rxBuffer = [];
  Completer<DfuResponse>? _pending;

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
        final r = await _programRow(row);

        if (r.status != DfuStatus.success) {
          // Only the device's row-access rejection means it refused a write
          // into its running slot: wrong slot file (or already up to date). The
          // device is unharmed and stays on its current firmware. Any other
          // status is a genuine failure — surface it (with the code, the
          // failing sub-command, and the MTU) so it is not silently swallowed.
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
            'Row $rowIndex ${r.where} failed: ${_statusDetail(r.status)} '
            '[MTU $mtu]',
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
  /// single MTU-bounded write. Returns the DFU status plus a short description of
  /// the command that produced it (for diagnostics).
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
    var offset = 0;
    while (offset < sendEnd) {
      final n = math.min(sendChunk, sendEnd - offset);
      final chunk = data.sublist(offset, offset + n);
      final pkt = codec.buildPacket(DfuCommand.sendData, chunk);
      // Fire Send Data without waiting for the ATT write-ack (we still await the
      // bootloader's status notification), saving a round-trip per chunk.
      final resp = await _send(DfuCommand.sendData, chunk, withoutResponseWrite: true);
      if (!resp.isSuccess) {
        return (status: resp.status, where: 'SendData ${n}B (pkt ${pkt.length}B)');
      }
      offset += n;
    }

    final payload = <int>[
      ...u32le(row.address),
      if (includeRowCrc) ...u32le(dfuRowCrc32(data)),
      ...data.sublist(sendEnd),
    ];
    final pkt = codec.buildPacket(DfuCommand.programData, payload);
    final resp = await _send(DfuCommand.programData, payload);
    return (status: resp.status, where: 'ProgramData ${progTail}B (pkt ${pkt.length}B)');
  }

  // --- BLE transport ------------------------------------------------------

  void _listen() {
    _sub = characteristic.onValueReceived.listen(_onData);
  }

  void _onData(List<int> value) {
    _rxBuffer.addAll(value);
    // A DFU response is [SOP][status][lenLo][lenHi][data][cksum 2][EOP].
    if (_rxBuffer.length < 7) return;
    final length = _rxBuffer[2] | (_rxBuffer[3] << 8);
    final expected = 7 + length;
    if (_rxBuffer.length < expected) return;

    final frame = _rxBuffer.sublist(0, expected);
    _rxBuffer.removeRange(0, expected);

    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    try {
      pending.complete(codec.parseResponse(frame));
    } catch (e) {
      pending.completeError(e);
    }
  }

  Future<DfuResponse> _send(
    int command,
    List<int> data, {
    bool expectResponse = true,
    bool withoutResponseWrite = false,
  }) async {
    final packet = codec.buildPacket(command, data);

    if (!expectResponse) {
      // Fire-and-forget (Exit): the device resets immediately, so the ATT
      // response may never arrive — write without response.
      await characteristic.write(packet, withoutResponse: true);
      return DfuResponse(status: DfuStatus.success, data: Uint8List(0));
    }

    // Packets are pre-chunked to fit MTU-3, so we never need allowLongWrite (the
    // bootloader characteristic does not accept queued writes — that caused
    // ERR_LENGTH on the first >20-byte row write). [withoutResponseWrite] skips
    // the ATT write-ack for throughput on Send Data; we still await the
    // bootloader's status notification below.
    final completer = Completer<DfuResponse>();
    _pending = completer;
    await characteristic.write(packet, withoutResponse: withoutResponseWrite);
    return completer.future.timeout(responseTimeout);
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

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    _rxBuffer.clear();
    _pending = null;
  }
}
