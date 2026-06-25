import 'package:flutter_test/flutter_test.dart';
import 'package:pain_drain_mobile_app/ota/dfu_protocol.dart';

void main() {
  group('DfuCodec framing', () {
    for (final checksum in DfuChecksum.values) {
      group('with $checksum', () {
        final codec = DfuCodec(checksum: checksum);

        test('build then parse round-trips command, data and framing', () {
          final data = [0x04, 0x03, 0x02, 0x01];
          final packet = codec.buildPacket(DfuCommand.enter, data);

          // Structural checks.
          expect(packet.first, 0x01, reason: 'start of packet');
          expect(packet.last, 0x17, reason: 'end of packet');
          expect(packet[1], DfuCommand.enter);
          expect(packet[2], data.length & 0xFF);
          expect(packet[3], (data.length >> 8) & 0xFF);

          final parsed = codec.parseResponse(packet);
          expect(parsed.status, DfuCommand.enter);
          expect(parsed.data, data);
        });

        test('round-trips an empty payload', () {
          final packet = codec.buildPacket(DfuCommand.exit);
          final parsed = codec.parseResponse(packet);
          expect(parsed.status, DfuCommand.exit);
          expect(parsed.data, isEmpty);
          expect(parsed.isSuccess, isFalse); // exit opcode != success status
        });

        test('rejects a corrupted checksum', () {
          final packet = codec.buildPacket(DfuCommand.programData, [1, 2, 3]);
          // Flip a payload byte; the stored checksum no longer matches.
          packet[4] ^= 0xFF;
          expect(() => codec.parseResponse(packet),
              throwsA(isA<DfuFramingException>()));
        });

        test('rejects a bad start-of-packet', () {
          final packet = codec.buildPacket(DfuCommand.sync);
          packet[0] = 0x00;
          expect(() => codec.parseResponse(packet),
              throwsA(isA<DfuFramingException>()));
        });

        test('rejects a too-short packet', () {
          expect(() => codec.parseResponse([0x01, 0x00]),
              throwsA(isA<DfuFramingException>()));
        });
      });
    }
  });

  group('checksums', () {
    test('basic summation is the 2s-complement of the byte sum', () {
      // sum(0x01,0x38,0x00,0x00) = 0x39; (1 + ~0x39) & 0xFFFF = 0xFFC7
      expect(dfuBasicSummation([0x01, 0x38, 0x00, 0x00]), 0xFFC7);
    });

    test('crc16 is stable and 16-bit', () {
      final crc = dfuCrc16([0x01, 0x38, 0x00, 0x00]);
      expect(crc, inInclusiveRange(0, 0xFFFF));
      // Deterministic for a fixed input.
      expect(dfuCrc16([0x01, 0x38, 0x00, 0x00]), crc);
    });

    test('row crc32 is 32-bit and deterministic', () {
      final crc = dfuRowCrc32([0xDE, 0xAD, 0xBE, 0xEF]);
      expect(crc, inInclusiveRange(0, 0xFFFFFFFF));
      expect(dfuRowCrc32([0xDE, 0xAD, 0xBE, 0xEF]), crc);
    });
  });

  group('u32le', () {
    test('encodes little-endian', () {
      expect(u32le(0x01020304), [0x04, 0x03, 0x02, 0x01]);
      expect(u32le(0), [0, 0, 0, 0]);
      expect(u32le(0xFF), [0xFF, 0, 0, 0]);
    });
  });
}
