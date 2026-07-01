import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

part 'device_state.freezed.dart';

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
  }) = _DeviceState;
}
