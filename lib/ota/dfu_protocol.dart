// Low-level encode/decode for the Cypress/Infineon DFU host protocol
// (PSoC 6 DFU SDK, see Infineon AN213924). This file is pure and synchronous
// so the byte-level framing can be unit tested without a BLE device.
//
// Matched to the PainDrain bootloader (Cypress `cy_bootload`, PSoC6 BLE,
// example CE215121). Confirmed against the firmware build:
//   * Packet checksum = basic 2's-complement summation
//     (bootload_user.h: CY_BOOTLOAD_OPT_PACKET_CRC == 0), so DfuChecksum
//     defaults to basicSummation below.
//   * .cyacd2 rows are [address 4][data] with no embedded per-row checksum, so
//     Program Data sends address + data (no row CRC-32; dfuRowCrc32 is kept
//     available but unused by default — see DfuTransfer.includeRowCrc).
//   * Product id = 0x01020304 (carried in the .cyacd2 header).

import 'dart:typed_data';

/// DFU command opcodes (PSoC 6 DFU SDK).
class DfuCommand {
  static const int enter = 0x38;
  static const int sync = 0x35;
  static const int exit = 0x3B;
  static const int sendData = 0x37;
  static const int sendDataNoResponse = 0x47;
  static const int programData = 0x49;
  static const int verifyData = 0x4A;
  static const int eraseData = 0x44;
  static const int verifyApp = 0x31;
  static const int setAppMetadata = 0x4C;
  static const int getMetadata = 0x3C;
  static const int setEiv = 0x4D;
}

/// DFU response status codes.
class DfuStatus {
  static const int success = 0x00;
  static const int errVerify = 0x02;
  static const int errLength = 0x03;
  static const int errData = 0x04;
  static const int errCmd = 0x05;
  static const int errChecksum = 0x08;
  static const int errRow = 0x0A;

  /// Write was rejected because the targeted row belongs to the *running*
  /// application (read-only while active). When this arrives early in a
  /// transfer it means the wrong slot file was sent — the device is fine and
  /// stays on its current firmware. Callers should treat this as
  /// "wrong slot / already up to date", not a brick.
  static const int errRowAccess = 0x0B;

  static const int errUnknown = 0x0F;

  static String describe(int status) {
    switch (status) {
      case success:
        return 'Success';
      case errVerify:
        return 'Verification failed';
      case errLength:
        return 'Invalid length';
      case errData:
        return 'Invalid data';
      case errCmd:
        return 'Invalid/unexpected command';
      case errChecksum:
        return 'Checksum mismatch';
      case errRow:
        return 'Invalid flash row';
      case errRowAccess:
        return 'Row access denied (wrong slot / running app)';
      case errUnknown:
        return 'Unknown DFU error';
      default:
        return 'DFU status 0x${status.toRadixString(16)}';
    }
  }
}

/// Packet checksum algorithm, mirroring the device's bootloader configuration.
enum DfuChecksum { basicSummation, crc16 }

/// Framing constants.
const int _sop = 0x01; // Start of packet.
const int _eop = 0x17; // End of packet.

/// A decoded DFU response packet.
class DfuResponse {
  const DfuResponse({required this.status, required this.data});

  final int status;
  final Uint8List data;

  bool get isSuccess => status == DfuStatus.success;
}

/// Thrown when a response packet is structurally invalid (bad SOP/EOP/checksum).
class DfuFramingException implements Exception {
  DfuFramingException(this.message);
  final String message;
  @override
  String toString() => 'DfuFramingException: $message';
}

/// Encodes and decodes DFU packets for a given [checksum] configuration.
class DfuCodec {
  // Defaults to basic summation: the PainDrain bootloader is built with
  // CY_BOOTLOAD_OPT_PACKET_CRC == 0.
  const DfuCodec({this.checksum = DfuChecksum.basicSummation});

  final DfuChecksum checksum;

  /// Builds a command packet:
  /// `[SOP][cmd][lenLo][lenHi][data...][cksumLo][cksumHi][EOP]`.
  /// The checksum spans SOP through the end of the data field, matching the
  /// Cypress host (`CyBtldr_CreateCmdPacket`).
  Uint8List buildPacket(int command, [List<int> data = const []]) {
    final length = data.length;
    final packet = Uint8List(7 + length);
    packet[0] = _sop;
    packet[1] = command;
    packet[2] = length & 0xFF;
    packet[3] = (length >> 8) & 0xFF;
    packet.setRange(4, 4 + length, data);

    final cksum = _checksum(packet.sublist(0, 4 + length));
    packet[4 + length] = cksum & 0xFF;
    packet[5 + length] = (cksum >> 8) & 0xFF;
    packet[6 + length] = _eop;
    return packet;
  }

  /// Decodes a response packet, validating framing and checksum.
  DfuResponse parseResponse(List<int> raw) {
    if (raw.length < 7) {
      throw DfuFramingException('Response too short (${raw.length} bytes)');
    }
    if (raw.first != _sop) {
      throw DfuFramingException('Bad start-of-packet 0x${raw.first.toRadixString(16)}');
    }
    if (raw.last != _eop) {
      throw DfuFramingException('Bad end-of-packet 0x${raw.last.toRadixString(16)}');
    }

    final status = raw[1];
    final length = raw[2] | (raw[3] << 8);
    if (raw.length != 7 + length) {
      throw DfuFramingException(
        'Length field ($length) inconsistent with packet size ${raw.length}',
      );
    }

    final data = Uint8List.fromList(raw.sublist(4, 4 + length));
    final expected = _checksum(raw.sublist(0, 4 + length));
    final actual = raw[4 + length] | (raw[5 + length] << 8);
    if (expected != actual) {
      throw DfuFramingException(
        'Checksum mismatch: expected 0x${expected.toRadixString(16)}, '
        'got 0x${actual.toRadixString(16)}',
      );
    }

    return DfuResponse(status: status, data: data);
  }

  int _checksum(List<int> bytes) {
    switch (checksum) {
      case DfuChecksum.basicSummation:
        return dfuBasicSummation(bytes);
      case DfuChecksum.crc16:
        return dfuCrc16(bytes);
    }
  }
}

/// 2's-complement summation checksum (`CyBtldr_ComputeChecksum`, sum mode).
int dfuBasicSummation(List<int> bytes) {
  var sum = 0;
  for (final b in bytes) {
    sum = (sum + b) & 0xFFFF;
  }
  return (1 + (~sum)) & 0xFFFF;
}

/// Cypress bootloader CRC-16 (reflected poly 0x8408, init 0xFFFF, final ~,
/// byte-swapped) — matches `CyBtldr_ComputeChecksum` CRC mode.
int dfuCrc16(List<int> bytes) {
  var crc = 0xFFFF;
  for (final byte in bytes) {
    var data = byte & 0xFF;
    for (var i = 0; i < 8; i++) {
      if (((crc & 0x0001) ^ (data & 0x0001)) != 0) {
        crc = (crc >> 1) ^ 0x8408;
      } else {
        crc >>= 1;
      }
      data >>= 1;
    }
  }
  crc = (~crc) & 0xFFFF;
  return ((crc << 8) | (crc >> 8)) & 0xFFFF;
}

/// CRC-32 guarding each row in Program/Verify Data commands.
///
/// The PainDrain bootloader (cy_bootload) uses CRC-32C / Castagnoli — its
/// metadata CRC is documented as CRC-32C (bootload_user.h) and the same routine
/// guards programmed rows. If a device ever returns a checksum/data error on an
/// otherwise correctly-framed row, swap this to [dfuCrc32Ieee] to rule out the
/// polynomial.
int dfuRowCrc32(List<int> bytes) => dfuCrc32c(bytes);

/// CRC-32C / Castagnoli: reflected poly 0x82F63B78, init/final 0xFFFFFFFF.
int dfuCrc32c(List<int> bytes) => _crc32(bytes, 0x82F63B78);

/// IEEE 802.3 CRC-32: reflected poly 0xEDB88320, init/final 0xFFFFFFFF.
int dfuCrc32Ieee(List<int> bytes) => _crc32(bytes, 0xEDB88320);

int _crc32(List<int> bytes, int reflectedPoly) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte & 0xFF;
    for (var i = 0; i < 8; i++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ reflectedPoly;
      } else {
        crc >>= 1;
      }
    }
  }
  return (~crc) & 0xFFFFFFFF;
}

/// Little-endian 4-byte encoding helper.
Uint8List u32le(int value) {
  return Uint8List(4)
    ..[0] = value & 0xFF
    ..[1] = (value >> 8) & 0xFF
    ..[2] = (value >> 16) & 0xFF
    ..[3] = (value >> 24) & 0xFF;
}
