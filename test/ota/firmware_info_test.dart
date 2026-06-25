import 'package:flutter_test/flutter_test.dart';
import 'package:pain_drain_mobile_app/ota/firmware_info.dart';

void main() {
  group('FirmwareInfo.parse', () {
    test('parses a well-formed string from slot 0', () {
      final info = FirmwareInfo.parse('1.1.0.6/0');
      expect(info.versionString, '1.1.0.6');
      expect(info.major, 1);
      expect(info.minor, 1);
      expect(info.patch, 0);
      expect(info.build, 6);
      expect(info.runningSlot, 0);
      expect(info.inactiveSlot, 1);
      // 1*10000 + 1*100 + 0 = 10100
      expect(info.version, 10100);
    });

    test('parses slot 1 and computes the inactive slot as 0', () {
      final info = FirmwareInfo.parse('2.3.4.10/1');
      expect(info.runningSlot, 1);
      expect(info.inactiveSlot, 0);
      // 2*10000 + 3*100 + 4 = 20304
      expect(info.version, 20304);
    });

    test('build number does not affect the numeric version', () {
      final a = FirmwareInfo.parse('1.1.0.6/0');
      final b = FirmwareInfo.parse('1.1.0.999/0');
      expect(a.version, b.version);
    });

    test('tolerates trailing NUL padding and whitespace', () {
      final info = FirmwareInfo.parse('  1.1.0.6/0\x00\x00 ');
      expect(info.versionString, '1.1.0.6');
      expect(info.runningSlot, 0);
    });

    test('throws on missing slot', () {
      expect(() => FirmwareInfo.parse('1.1.0.6'), throwsFormatException);
    });

    test('throws on an out-of-range slot', () {
      expect(() => FirmwareInfo.parse('1.1.0.6/2'), throwsFormatException);
    });

    test('throws when there are not four version components', () {
      expect(() => FirmwareInfo.parse('1.1.0/0'), throwsFormatException);
    });

    test('throws on non-numeric components', () {
      expect(() => FirmwareInfo.parse('1.x.0.6/0'), throwsFormatException);
    });

    test('throws on empty input', () {
      expect(() => FirmwareInfo.parse(''), throwsFormatException);
    });
  });

  group('FirmwareInfo.numericVersion', () {
    test('matches the documented formula', () {
      expect(FirmwareInfo.numericVersion(1, 1, 0), 10100);
      expect(FirmwareInfo.numericVersion(0, 0, 0), 0);
      expect(FirmwareInfo.numericVersion(12, 34, 56), 123456);
    });
  });
}
