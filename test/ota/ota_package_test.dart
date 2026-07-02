import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pain_drain_mobile_app/ota/ota_source.dart';

/// End-to-end decode of the real artifact bundled at
/// assets/ota/PainDrain_ota.zip — exercises the zip + manifest + .cyacd2 chain
/// against an actual firmware build (no device required).
void main() {
  final zip = File('assets/ota/PainDrain_ota.zip');

  group('real bundled OTA package', () {
    test('decodes manifest and both slot images', () {
      // Skip gracefully if the artifact has not been dropped in yet.
      if (!zip.existsSync()) {
        markTestSkipped('assets/ota/PainDrain_ota.zip not present');
        return;
      }

      final pkg = decodeOtaZip(zip.readAsBytesSync());

      // Manifest matches the firmware build (v10102 / "1.1.2.6").
      expect(pkg.manifest.version, 10102);
      expect(pkg.manifest.firmwareVersion, '1.1.2.6');
      expect(pkg.manifest.fileNameForSlot(0), 'PainDrain_slot0.cyacd2');
      expect(pkg.manifest.fileNameForSlot(1), 'PainDrain_slot1.cyacd2');

      // Slot 0 image: linked at 0x10010000, appId 0, product 0x01020304.
      final slot0 = pkg.imageForSlot(0);
      expect(slot0.appId, 0);
      expect(slot0.productId, 0x01020304);
      expect(slot0.checksumType, 0x00);
      expect(slot0.appInfoAddress, 0x10010000);
      expect(slot0.rows, isNotEmpty);
      expect(slot0.rows.first.address, 0x10010000);

      // Slot 1 image: linked at 0x10088000, appId 1.
      final slot1 = pkg.imageForSlot(1);
      expect(slot1.appId, 1);
      expect(slot1.appInfoAddress, 0x10088000);
    });
  });
}
