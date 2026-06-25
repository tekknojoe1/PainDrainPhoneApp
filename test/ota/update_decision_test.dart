import 'package:flutter_test/flutter_test.dart';
import 'package:pain_drain_mobile_app/ota/firmware_info.dart';
import 'package:pain_drain_mobile_app/ota/update_decision.dart';

void main() {
  group('decideUpdate', () {
    test('newer manifest -> updateAvailable', () {
      expect(
        decideUpdate(deviceVersion: 10100, manifestVersion: 10200),
        UpdateStatus.updateAvailable,
      );
    });

    test('equal versions -> upToDate', () {
      expect(
        decideUpdate(deviceVersion: 10100, manifestVersion: 10100),
        UpdateStatus.upToDate,
      );
    });

    test('older manifest -> downgrade', () {
      expect(
        decideUpdate(deviceVersion: 10200, manifestVersion: 10100),
        UpdateStatus.downgrade,
      );
    });

    test('integrates with FirmwareInfo parsing end-to-end', () {
      final device = FirmwareInfo.parse('1.1.0.6/0');
      // Manifest advertises 1.2.0 -> 10200 > 10100.
      expect(
        decideUpdate(
          deviceVersion: device.version,
          manifestVersion: FirmwareInfo.numericVersion(1, 2, 0),
        ),
        UpdateStatus.updateAvailable,
      );
      // The image to send targets the inactive slot.
      expect(device.inactiveSlot, 1);
    });

    test('a higher build alone does not make an update available', () {
      final device = FirmwareInfo.parse('1.1.0.6/0');
      // Same MAJOR.MINOR.PATCH, only build differs -> still up to date.
      expect(
        decideUpdate(
          deviceVersion: device.version,
          manifestVersion: FirmwareInfo.numericVersion(1, 1, 0),
        ),
        UpdateStatus.upToDate,
      );
    });
  });
}
