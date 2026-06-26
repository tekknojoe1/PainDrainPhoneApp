import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'cyacd2_file.dart';
import 'dfu_transfer.dart';
import 'firmware_info.dart';

/// BLE-level OTA operations: reading the running firmware/slot from the Device
/// Information Service, and streaming a `.cyacd2` image to the Cypress
/// Bootloader Service.
///
/// The device does NOT support pairing/bonding — like the existing control
/// connection we simply connect and use GATT. We never call any pairing API; if
/// the platform stack auto-pairs, that attempt is what the device rejects, so we
/// keep to plain connect/discover/read/write here.
class OtaService {
  // Device Information Service (DIS).
  static const String _disServiceUuid = '180a';
  static const String _firmwareRevisionUuid = '2a26';

  // Cypress Bootloader Service (BTS).
  static const String _btsServiceUuid =
      '00060000-f8ce-11e4-abf4-0002a5d5c51b';
  static const String _btsCharacteristicUuid =
      '00060001-f8ce-11e4-abf4-0002a5d5c51b';

  /// PainDrain DFU product ID.
  static const int productId = 0x01020304;

  final void Function(String message)? log;

  OtaService({this.log});

  /// Reads and parses the DIS Firmware Revision String (e.g. `"1.1.0.6/0"`)
  /// from an already-connected [device].
  Future<FirmwareInfo> readFirmwareInfo(BluetoothDevice device) async {
    final services = await device.discoverServices();
    final dis = _findService(services, _disServiceUuid);
    if (dis == null) {
      throw StateError('Device Information Service (0x180A) not found');
    }
    final firmwareChar = dis.characteristics.firstWhere(
      (c) => _matches(c.uuid, _firmwareRevisionUuid),
      orElse: () =>
          throw StateError('Firmware Revision String (0x2A26) not found'),
    );
    final raw = await firmwareChar.read();
    final text = utf8.decode(raw, allowMalformed: true);
    log?.call('DIS firmware revision: "$text"');
    return FirmwareInfo.parse(text);
  }

  /// Streams [image] to the device's Bootloader Service and returns the result.
  ///
  /// On [DfuResultType.success] the device resets and the BLE link drops — call
  /// [readFirmwareInfo] again after reconnecting to confirm the new version and
  /// slot. A [DfuResultType.wrongSlot] result means the device refused the
  /// write (wrong slot file / already current) and is unharmed.
  Future<DfuResult> flashImage(
    BluetoothDevice device,
    Cyacd2File image, {
    void Function(double progress)? onProgress,
    DfuCancelToken? cancelToken,
  }) async {
    // Request a larger MTU for throughput — each DFU packet is chunked to fit a
    // single MTU-bounded write (the bootloader characteristic rejects long
    // writes), so a bigger MTU directly means bigger, faster chunks.
    var mtu = 23;
    try {
      mtu = await device.requestMtu(517);
    } catch (e) {
      try {
        mtu = device.mtuNow;
      } catch (_) {}
      log?.call('MTU request failed ($e)');
    }
    log?.call('Using MTU $mtu (max write ${mtu - 3} bytes)');

    // The bootloader fixes its MTU at 23 (CY_BLE_CONFIG_GATT_MTU), so each write
    // is tiny and the transfer is dominated by round-trip latency. Ask for a
    // high-priority connection to shrink the connection interval (Android only;
    // a no-op elsewhere).
    try {
      await device.requestConnectionPriority(
        connectionPriorityRequest: ConnectionPriority.high,
      );
      log?.call('Requested high-priority (fast) connection');
    } catch (e) {
      log?.call('Connection priority request failed ($e)');
    }

    final services = await device.discoverServices();
    final bts = _findService(services, _btsServiceUuid);
    if (bts == null) {
      throw StateError('Cypress Bootloader Service not found');
    }
    final command = bts.characteristics.firstWhere(
      (c) => _matches(c.uuid, _btsCharacteristicUuid),
      orElse: () =>
          throw StateError('Bootloader command characteristic not found'),
    );

    // Enable notifications (CCCD) so we receive DFU response packets.
    if (command.properties.notify || command.properties.indicate) {
      await command.setNotifyValue(true);
    }

    final transfer = DfuTransfer(
      characteristic: command,
      productId: productId,
      mtu: mtu,
      log: log,
    );

    return transfer.run(
      image,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  BluetoothService? _findService(
      List<BluetoothService> services, String uuid) {
    for (final service in services) {
      if (_matches(service.uuid, uuid)) return service;
    }
    return null;
  }

  /// Compares a discovered [Guid] against either a 16-bit short UUID (`"180a"`)
  /// or a full 128-bit UUID string, case-insensitively.
  bool _matches(Guid guid, String uuid) {
    final a = guid.toString().toLowerCase();
    final b = uuid.toLowerCase();
    if (a == b) return true;
    // flutter_blue_plus may expand short UUIDs to the full base UUID.
    return a.replaceAll('-', '').endsWith(b.replaceAll('-', '')) ||
        a.contains(b);
  }
}
