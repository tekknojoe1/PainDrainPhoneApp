// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$DeviceState {
  bool get isConnected => throw _privateConstructorUsedError;
  BluetoothDevice? get connectedDevice => throw _privateConstructorUsedError;
  List<ScanResult> get scanResults => throw _privateConstructorUsedError;
  bool get isCharging => throw _privateConstructorUsedError;
  bool get showChargingAnimation =>
      throw _privateConstructorUsedError; // Battery state-of-charge (0-100%) from the BLE Battery Service (0x2A19).
// Null until the first read/notification arrives after connecting.
  int? get batteryLevel => throw _privateConstructorUsedError;

  /// Create a copy of DeviceState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DeviceStateCopyWith<DeviceState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DeviceStateCopyWith<$Res> {
  factory $DeviceStateCopyWith(
          DeviceState value, $Res Function(DeviceState) then) =
      _$DeviceStateCopyWithImpl<$Res, DeviceState>;
  @useResult
  $Res call(
      {bool isConnected,
      BluetoothDevice? connectedDevice,
      List<ScanResult> scanResults,
      bool isCharging,
      bool showChargingAnimation,
      int? batteryLevel});
}

/// @nodoc
class _$DeviceStateCopyWithImpl<$Res, $Val extends DeviceState>
    implements $DeviceStateCopyWith<$Res> {
  _$DeviceStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DeviceState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? isConnected = null,
    Object? connectedDevice = freezed,
    Object? scanResults = null,
    Object? isCharging = null,
    Object? showChargingAnimation = null,
    Object? batteryLevel = freezed,
  }) {
    return _then(_value.copyWith(
      isConnected: null == isConnected
          ? _value.isConnected
          : isConnected // ignore: cast_nullable_to_non_nullable
              as bool,
      connectedDevice: freezed == connectedDevice
          ? _value.connectedDevice
          : connectedDevice // ignore: cast_nullable_to_non_nullable
              as BluetoothDevice?,
      scanResults: null == scanResults
          ? _value.scanResults
          : scanResults // ignore: cast_nullable_to_non_nullable
              as List<ScanResult>,
      isCharging: null == isCharging
          ? _value.isCharging
          : isCharging // ignore: cast_nullable_to_non_nullable
              as bool,
      showChargingAnimation: null == showChargingAnimation
          ? _value.showChargingAnimation
          : showChargingAnimation // ignore: cast_nullable_to_non_nullable
              as bool,
      batteryLevel: freezed == batteryLevel
          ? _value.batteryLevel
          : batteryLevel // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DeviceStateImplCopyWith<$Res>
    implements $DeviceStateCopyWith<$Res> {
  factory _$$DeviceStateImplCopyWith(
          _$DeviceStateImpl value, $Res Function(_$DeviceStateImpl) then) =
      __$$DeviceStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool isConnected,
      BluetoothDevice? connectedDevice,
      List<ScanResult> scanResults,
      bool isCharging,
      bool showChargingAnimation,
      int? batteryLevel});
}

/// @nodoc
class __$$DeviceStateImplCopyWithImpl<$Res>
    extends _$DeviceStateCopyWithImpl<$Res, _$DeviceStateImpl>
    implements _$$DeviceStateImplCopyWith<$Res> {
  __$$DeviceStateImplCopyWithImpl(
      _$DeviceStateImpl _value, $Res Function(_$DeviceStateImpl) _then)
      : super(_value, _then);

  /// Create a copy of DeviceState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? isConnected = null,
    Object? connectedDevice = freezed,
    Object? scanResults = null,
    Object? isCharging = null,
    Object? showChargingAnimation = null,
    Object? batteryLevel = freezed,
  }) {
    return _then(_$DeviceStateImpl(
      isConnected: null == isConnected
          ? _value.isConnected
          : isConnected // ignore: cast_nullable_to_non_nullable
              as bool,
      connectedDevice: freezed == connectedDevice
          ? _value.connectedDevice
          : connectedDevice // ignore: cast_nullable_to_non_nullable
              as BluetoothDevice?,
      scanResults: null == scanResults
          ? _value._scanResults
          : scanResults // ignore: cast_nullable_to_non_nullable
              as List<ScanResult>,
      isCharging: null == isCharging
          ? _value.isCharging
          : isCharging // ignore: cast_nullable_to_non_nullable
              as bool,
      showChargingAnimation: null == showChargingAnimation
          ? _value.showChargingAnimation
          : showChargingAnimation // ignore: cast_nullable_to_non_nullable
              as bool,
      batteryLevel: freezed == batteryLevel
          ? _value.batteryLevel
          : batteryLevel // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc

class _$DeviceStateImpl implements _DeviceState {
  const _$DeviceStateImpl(
      {this.isConnected = false,
      this.connectedDevice,
      final List<ScanResult> scanResults = const [],
      this.isCharging = false,
      this.showChargingAnimation = false,
      this.batteryLevel})
      : _scanResults = scanResults;

  @override
  @JsonKey()
  final bool isConnected;
  @override
  final BluetoothDevice? connectedDevice;
  final List<ScanResult> _scanResults;
  @override
  @JsonKey()
  List<ScanResult> get scanResults {
    if (_scanResults is EqualUnmodifiableListView) return _scanResults;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_scanResults);
  }

  @override
  @JsonKey()
  final bool isCharging;
  @override
  @JsonKey()
  final bool showChargingAnimation;
// Battery state-of-charge (0-100%) from the BLE Battery Service (0x2A19).
// Null until the first read/notification arrives after connecting.
  @override
  final int? batteryLevel;

  @override
  String toString() {
    return 'DeviceState(isConnected: $isConnected, connectedDevice: $connectedDevice, scanResults: $scanResults, isCharging: $isCharging, showChargingAnimation: $showChargingAnimation, batteryLevel: $batteryLevel)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DeviceStateImpl &&
            (identical(other.isConnected, isConnected) ||
                other.isConnected == isConnected) &&
            (identical(other.connectedDevice, connectedDevice) ||
                other.connectedDevice == connectedDevice) &&
            const DeepCollectionEquality()
                .equals(other._scanResults, _scanResults) &&
            (identical(other.isCharging, isCharging) ||
                other.isCharging == isCharging) &&
            (identical(other.showChargingAnimation, showChargingAnimation) ||
                other.showChargingAnimation == showChargingAnimation) &&
            (identical(other.batteryLevel, batteryLevel) ||
                other.batteryLevel == batteryLevel));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      isConnected,
      connectedDevice,
      const DeepCollectionEquality().hash(_scanResults),
      isCharging,
      showChargingAnimation,
      batteryLevel);

  /// Create a copy of DeviceState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DeviceStateImplCopyWith<_$DeviceStateImpl> get copyWith =>
      __$$DeviceStateImplCopyWithImpl<_$DeviceStateImpl>(this, _$identity);
}

abstract class _DeviceState implements DeviceState {
  const factory _DeviceState(
      {final bool isConnected,
      final BluetoothDevice? connectedDevice,
      final List<ScanResult> scanResults,
      final bool isCharging,
      final bool showChargingAnimation,
      final int? batteryLevel}) = _$DeviceStateImpl;

  @override
  bool get isConnected;
  @override
  BluetoothDevice? get connectedDevice;
  @override
  List<ScanResult> get scanResults;
  @override
  bool get isCharging;
  @override
  bool get showChargingAnimation; // Battery state-of-charge (0-100%) from the BLE Battery Service (0x2A19).
// Null until the first read/notification arrives after connecting.
  @override
  int? get batteryLevel;

  /// Create a copy of DeviceState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DeviceStateImplCopyWith<_$DeviceStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
