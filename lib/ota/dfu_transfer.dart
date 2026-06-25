import 'dart:async';
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
    this.maxDataSize = 256,
    this.includeRowCrc = false,
    this.earlyRowThreshold = 4,
    this.responseTimeout = const Duration(seconds: 5),
    this.log,
  });

  /// Bootloader Service command characteristic (notify + write).
  final BluetoothCharacteristic characteristic;

  /// Device product ID, sent with Enter DFU (PainDrain = 0x01020304).
  final int productId;

  final DfuCodec codec;

  /// Max payload bytes per Send Data packet. Bounded by the negotiated ATT MTU
  /// minus the 7-byte DFU framing; the service layer requests a large MTU.
  final int maxDataSize;

  /// Whether Program/Verify Data carry a CRC-32 of the row. PainDrain `.cyacd2`
  /// rows are address+data with no embedded checksum, so this is `false`.
  final bool includeRowCrc;

  /// A program-row rejection at or before this row index is treated as
  /// "wrong slot file / already up to date" rather than a failure — the device
  /// refuses writes into its running slot at the very start of the transfer.
  final int earlyRowThreshold;

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
        return _fail('Enter DFU rejected: ${DfuStatus.describe(enter.status)}');
      }

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
            'Set metadata failed: ${DfuStatus.describe(metaResp.status)}',
          );
        }
      }

      // --- Set EIV if the image is encrypted -------------------------------
      if (image.eiv != null && image.eiv!.isNotEmpty) {
        final eivResp = await _send(DfuCommand.setEiv, image.eiv!);
        if (!eivResp.isSuccess) {
          return _fail('Set EIV failed: ${DfuStatus.describe(eivResp.status)}');
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
        final status = await _programRow(row);

        if (status != DfuStatus.success) {
          // A rejection right at the start of the transfer means the device
          // refused a write into its running slot: wrong slot file (or already
          // up to date). The device is unharmed and stays on its current
          // firmware — never report this as a brick.
          final isEarly = rowIndex <= earlyRowThreshold;
          if (status == DfuStatus.errRowAccess || isEarly) {
            log?.call('Row $rowIndex rejected (${DfuStatus.describe(status)})'
                ' -> wrong slot file');
            return const DfuResult(
              DfuResultType.wrongSlot,
              message: 'Device refused the write — wrong slot file or already '
                  'up to date.',
            );
          }
          return _fail(
            'Program row $rowIndex failed: ${DfuStatus.describe(status)}',
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
            '${DfuStatus.describe(verify.status)}');
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

  /// Programs one row: stream the data in [maxDataSize] chunks via Send Data,
  /// then commit it with Program Data carrying the address (+ optional CRC-32).
  Future<int> _programRow(Cyacd2Row row) async {
    final data = row.data;
    var offset = 0;
    while (data.length - offset > maxDataSize) {
      final chunk = data.sublist(offset, offset + maxDataSize);
      final resp = await _send(DfuCommand.sendData, chunk);
      if (!resp.isSuccess) return resp.status;
      offset += maxDataSize;
    }

    final tail = data.sublist(offset);
    final payload = <int>[
      ...u32le(row.address),
      if (includeRowCrc) ...u32le(dfuRowCrc32(data)),
      ...tail,
    ];
    final resp = await _send(DfuCommand.programData, payload);
    return resp.status;
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
  }) async {
    final packet = codec.buildPacket(command, data);

    if (!expectResponse) {
      // Fire-and-forget (Exit): the device resets immediately, so the ATT
      // response may never arrive — write without response.
      await characteristic.write(packet, withoutResponse: true);
      return DfuResponse(status: DfuStatus.success, data: Uint8List(0));
    }

    // Write WITH response, using a queued (long) write for any packet larger
    // than the minimum ATT payload (MTU-3 = 20 bytes at the default 23-byte
    // MTU). Write-without-response is hard-capped at that size and would throw
    // "data longer than allowed"; long writes are not, regardless of MTU. This
    // mirrors the existing control-path writes in bluetooth_notifier.
    final completer = Completer<DfuResponse>();
    _pending = completer;
    await characteristic.write(
      packet,
      withoutResponse: false,
      allowLongWrite: packet.length > 20,
    );
    return completer.future.timeout(responseTimeout);
  }

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
