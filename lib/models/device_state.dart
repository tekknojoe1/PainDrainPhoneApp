import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

part 'device_state.freezed.dart';

/// Why the BLE link dropped, so the UI can distinguish an expected/graceful
/// disconnect from an unexpected one.
///
/// The firmware announces a graceful disconnect ~100ms before the link drops:
///   "disconnect 0" -> [poweringOff]  (device is turning off; do not reconnect)
///   "disconnect 1" -> [charging]     (device is entering charging mode)
/// A drop with no preceding announcement is [unexpected].
enum DeviceDisconnectReason { none, poweringOff, charging, unexpected }

@freezed
class DeviceState with _$DeviceState {
  const factory DeviceState({
    @Default(false) bool isConnected,
    BluetoothDevice? connectedDevice,
    @Default([]) List<ScanResult> scanResults,
    @Default(false) bool isCharging,
    @Default(false) bool showChargingAnimation,
    // Battery state-of-charge (0-100%) from the BLE Battery Service (0x2A19).
    // Null until the first read/notification arrives after connecting.
    int? batteryLevel,
    // Set from a "disconnect 0/1" announcement so the imminent link drop is
    // treated as graceful, then reflects the actual reason after disconnect.
    @Default(DeviceDisconnectReason.none) DeviceDisconnectReason disconnectReason,
  }) = _DeviceState;
}
