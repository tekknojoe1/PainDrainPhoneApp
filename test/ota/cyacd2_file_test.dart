import 'package:flutter_test/flutter_test.dart';
import 'package:pain_drain_mobile_app/ota/cyacd2_file.dart';

void main() {
  group('Cyacd2File.parse', () {
    // Header: fileVersion=01, siliconId=2E103404 (LE bytes 2E 10 34 04),
    // siliconRev=00, checksumType=00.
    final header = '012E103404 0000'.replaceAll(' ', '');

    test('parses header, APPINFO and data rows', () {
      final contents = [
        header,
        '@APPINFO:0x10000000,0x00020000',
        // Row: address 0x10000000 (LE: 00 00 00 10) + data DE AD BE EF
        ':00000010DEADBEEF',
        ':04000010CAFE',
      ].join('\n');

      final file = Cyacd2File.parse(contents);

      expect(file.fileVersion, 0x01);
      expect(file.siliconId, 0x0434102E);
      expect(file.siliconRev, 0x00);
      expect(file.checksumType, 0x00);
      expect(file.appInfoAddress, 0x10000000);
      expect(file.appInfoSize, 0x00020000);

      expect(file.rows.length, 2);
      expect(file.rows[0].address, 0x10000000);
      expect(file.rows[0].data, [0xDE, 0xAD, 0xBE, 0xEF]);
      expect(file.rows[1].address, 0x10000004);
      expect(file.rows[1].data, [0xCA, 0xFE]);

      expect(file.totalDataBytes, 6);
    });

    test('parses an @EIV directive', () {
      final contents = [
        header,
        '@EIV:00112233445566778899AABBCCDDEEFF',
        ':00000010AA',
      ].join('\n');

      final file = Cyacd2File.parse(contents);
      expect(file.eiv, isNotNull);
      expect(file.eiv!.length, 16);
      expect(file.eiv!.first, 0x00);
      expect(file.eiv!.last, 0xFF);
    });

    test('ignores blank lines and unknown directives', () {
      final contents = [
        header,
        '',
        '@SOMETHINGELSE:ignored',
        ':00000010AA',
        '',
      ].join('\n');

      final file = Cyacd2File.parse(contents);
      expect(file.rows.length, 1);
    });

    test('throws on an empty file', () {
      expect(() => Cyacd2File.parse(''), throwsFormatException);
    });

    test('throws when there are no data rows', () {
      final contents = [header, '@APPINFO:0x0,0x10'].join('\n');
      expect(() => Cyacd2File.parse(contents), throwsFormatException);
    });

    test('throws on a malformed (non-hex) row', () {
      final contents = [header, ':00000010ZZ'].join('\n');
      expect(() => Cyacd2File.parse(contents), throwsFormatException);
    });

    test('parses the real PainDrain 12-byte header (appId + productId)', () {
      // Real slot 0 header from PainDrain_slot0.cyacd2:
      // 01 | 0021F0E2 | 21 | 00 | 00 | 04030201
      const slot0Header = '010021F0E221000004030201';
      final file = Cyacd2File.parse([
        slot0Header,
        '@APPINFO:0x10010000,0x77ffc',
        ':00000110DEADBEEF', // address 0x10010000 (LE 00 00 01 10)
      ].join('\r\n')); // real files use CRLF line endings

      expect(file.checksumType, 0x00, reason: 'basic summation');
      expect(file.appId, 0x00, reason: 'slot 0');
      expect(file.productId, 0x01020304);
      expect(file.appInfoAddress, 0x10010000);
      expect(file.rows.single.address, 0x10010000);
    });

    test('reads slot 1 appId from the header', () {
      const slot1Header = '010021F0E221000104030201';
      final file = Cyacd2File.parse([slot1Header, ':00800810AA'].join('\r\n'));
      expect(file.appId, 0x01);
      expect(file.productId, 0x01020304);
    });
  });
}
