import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'cyacd2_file.dart';
import 'ota_manifest.dart';

/// A loaded OTA artifact: the parsed [manifest] plus accessors for the per-slot
/// `.cyacd2` images contained in the same zip.
class OtaPackage {
  OtaPackage({required this.manifest, required Archive archive})
      : _archive = archive;

  final OtaManifest manifest;
  final Archive _archive;

  /// Parses and returns the image for [slot] (typically the device's inactive
  /// slot). Throws if the file named by the manifest is absent from the zip.
  Cyacd2File imageForSlot(int slot) {
    final fileName = manifest.fileNameForSlot(slot);
    final file = _archive.files.firstWhere(
      (f) => f.isFile && _baseName(f.name) == fileName,
      orElse: () => throw StateError('"$fileName" not found in OTA zip'),
    );
    final bytes = file.content as List<int>;
    return Cyacd2File.parse(utf8.decode(bytes));
  }

  static String _baseName(String path) => path.split('/').last;
}

/// Strategy for obtaining the `PainDrain_ota_v<version>.zip` artifact. The app
/// is wired against this interface so the delivery mechanism (bundled today,
/// downloaded later) can change without touching the OTA flow.
abstract class OtaSource {
  Future<OtaPackage> load();
}

/// Loads the artifact from a zip bundled in the app's assets (the default).
/// New firmware ships with an app update.
class BundledOtaSource implements OtaSource {
  const BundledOtaSource({this.assetPath = 'assets/ota/PainDrain_ota.zip'});

  final String assetPath;

  @override
  Future<OtaPackage> load() async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    return _decode(bytes);
  }
}

/// Placeholder for fetching the artifact from a server URL. Wire this to your
/// HTTP client / firmware endpoint when over-the-network delivery is needed.
class DownloadOtaSource implements OtaSource {
  const DownloadOtaSource(this.url);

  final String url;

  @override
  Future<OtaPackage> load() {
    throw UnimplementedError(
      'DownloadOtaSource is a stub. Fetch $url (e.g. with package:http), then '
      'pass the bytes to decodeOtaZip().',
    );
  }
}

/// Decodes raw zip [bytes] into an [OtaPackage]. Shared by the bundled and
/// (future) download sources.
OtaPackage decodeOtaZip(Uint8List bytes) => _decode(bytes);

OtaPackage _decode(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final manifestFile = archive.files.firstWhere(
    (f) => f.isFile && f.name.split('/').last == 'manifest.json',
    orElse: () => throw StateError('manifest.json not found in OTA zip'),
  );
  final manifestJson = json.decode(
    utf8.decode(manifestFile.content as List<int>),
  ) as Map<String, dynamic>;
  return OtaPackage(
    manifest: OtaManifest.fromJson(manifestJson),
    archive: archive,
  );
}
