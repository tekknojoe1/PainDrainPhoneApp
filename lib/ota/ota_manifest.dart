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
    this.productId,
    this.compatibleModels = const [],
    this.compatibleHardwareRevisions = const [],
  });

  /// Human readable version, e.g. `"1.1.0.6"`.
  final String firmwareVersion;

  /// Numeric version, comparable against [FirmwareInfo.version].
  final int version;

  /// Maps slot index (`0`/`1`) to the `.cyacd2` file name within the zip.
  final Map<int, String> slotFiles;

  /// DFU product ID string from the manifest, e.g. `"0x50440001"`. Informational
  /// on the app side — the device enforces the product ID itself at DFU ENTER
  /// (the app never sends it manually; it is carried in the `.cyacd2`).
  final String? productId;

  /// Device Model Numbers this image supports (exact match). Empty = accept any.
  final List<String> compatibleModels;

  /// Hardware Revision Strings this image supports (exact match). Empty = accept
  /// any.
  final List<String> compatibleHardwareRevisions;

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

    final productIdRaw = json['product_id'];

    return OtaManifest(
      firmwareVersion: firmwareVersion,
      version: version,
      slotFiles: slotFiles,
      productId: productIdRaw is String ? productIdRaw : null,
      compatibleModels: _stringList(json['compatible_models']),
      compatibleHardwareRevisions:
          _stringList(json['compatible_hardware_revisions']),
    );
  }

  /// Parses a JSON string array, ignoring non-string entries; a missing or
  /// non-list value becomes an empty list ("accept any").
  static List<String> _stringList(dynamic value) =>
      value is List ? value.whereType<String>().toList() : const [];

  @override
  String toString() => 'OtaManifest($firmwareVersion, version=$version)';
}
