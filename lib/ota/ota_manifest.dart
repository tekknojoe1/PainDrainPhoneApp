/// The `manifest.json` carried inside a `PainDrain_ota_v<version>.zip` artifact.
///
/// Example:
/// ```json
/// {
///   "firmware_version": "1.1.0.6",
///   "version": 10100,
///   "slots": { "0": "PainDrain_slot0.cyacd2", "1": "PainDrain_slot1.cyacd2" }
/// }
/// ```
class OtaManifest {
  const OtaManifest({
    required this.firmwareVersion,
    required this.version,
    required this.slotFiles,
  });

  /// Human readable version, e.g. `"1.1.0.6"`.
  final String firmwareVersion;

  /// Numeric version, comparable against [FirmwareInfo.version].
  final int version;

  /// Maps slot index (`0`/`1`) to the `.cyacd2` file name within the zip.
  final Map<int, String> slotFiles;

  /// Returns the `.cyacd2` file name to flash for the given (inactive) slot.
  ///
  /// Throws a [StateError] if the manifest does not contain an entry for the
  /// requested slot — that would indicate a malformed artifact.
  String fileNameForSlot(int slot) {
    final name = slotFiles[slot];
    if (name == null || name.isEmpty) {
      throw StateError('Manifest has no image for slot $slot');
    }
    return name;
  }

  factory OtaManifest.fromJson(Map<String, dynamic> json) {
    final firmwareVersion = json['firmware_version'];
    final version = json['version'];
    final slots = json['slots'];

    if (firmwareVersion is! String || firmwareVersion.isEmpty) {
      throw const FormatException('manifest.firmware_version is missing');
    }
    if (version is! int) {
      throw const FormatException('manifest.version must be an integer');
    }
    if (slots is! Map) {
      throw const FormatException('manifest.slots is missing');
    }

    final slotFiles = <int, String>{};
    slots.forEach((key, value) {
      final slot = int.tryParse(key.toString());
      if (slot != null && value is String) {
        slotFiles[slot] = value;
      }
    });

    if (slotFiles.isEmpty) {
      throw const FormatException('manifest.slots contained no valid entries');
    }

    return OtaManifest(
      firmwareVersion: firmwareVersion,
      version: version,
      slotFiles: slotFiles,
    );
  }

  @override
  String toString() => 'OtaManifest($firmwareVersion, version=$version)';
}
