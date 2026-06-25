import '../ota/firmware_info.dart';
import '../ota/ota_manifest.dart';

/// High-level OTA UI states.
///
/// Note: this is a plain immutable class (not `freezed`) on purpose. The
/// project's code-generation toolchain is currently incompatible with the Dart
/// SDK that ships with Flutter 3.44, so the OTA feature avoids codegen to stay
/// self-contained. Convert to `freezed` once the build_runner stack is updated.
enum OtaStatus {
  /// Nothing checked yet.
  idle,

  /// Reading the device version / loading the artifact.
  checking,

  /// Device firmware matches the artifact — nothing to do.
  upToDate,

  /// A newer firmware is available to flash.
  updateAvailable,

  /// A transfer is in progress; see [OtaState.progress].
  updating,

  /// Transfer completed; the device reset into the new slot.
  success,

  /// The device refused the write (wrong slot file / already current). The
  /// device is unharmed; the flow re-reads the version and can retry.
  wrongSlot,

  /// A retryable failure occurred; see [OtaState.message].
  failed,
}

class OtaState {
  const OtaState({
    this.status = OtaStatus.idle,
    this.currentFirmware,
    this.manifest,
    this.progress = 0.0,
    this.message,
  });

  final OtaStatus status;

  /// Firmware/slot currently reported by the device's DIS.
  final FirmwareInfo? currentFirmware;

  /// Manifest from the loaded OTA artifact.
  final OtaManifest? manifest;

  /// Transfer progress in the range 0..1 (only meaningful while updating).
  final double progress;

  /// Human readable status/error detail for the UI.
  final String? message;

  /// Current version string, e.g. `"1.1.0.6"`.
  String? get currentVersionString => currentFirmware?.versionString;

  /// Available version string from the manifest.
  String? get availableVersionString => manifest?.firmwareVersion;

  bool get isBusy =>
      status == OtaStatus.checking || status == OtaStatus.updating;

  /// Returns a copy with the given fields replaced. Omitted fields are kept
  /// (including [message] — pass a new string to change it).
  OtaState copyWith({
    OtaStatus? status,
    FirmwareInfo? currentFirmware,
    OtaManifest? manifest,
    double? progress,
    String? message,
  }) {
    return OtaState(
      status: status ?? this.status,
      currentFirmware: currentFirmware ?? this.currentFirmware,
      manifest: manifest ?? this.manifest,
      progress: progress ?? this.progress,
      message: message ?? this.message,
    );
  }
}
