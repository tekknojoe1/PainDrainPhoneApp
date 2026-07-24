import 'dart:typed_data';

/// One programmable row from a `.cyacd2` file: a 32-bit flash [address] and the
/// raw [data] bytes to write there.
class Cyacd2Row {
  const Cyacd2Row({required this.address, required this.data});

  final int address;
  final Uint8List data;

  @override
  String toString() =>
      'Cyacd2Row(0x${address.toRadixString(16)}, ${data.length} bytes)';
}

/// Parsed Cypress/Infineon DFU image file (`.cyacd2`, file format version 1).
///
/// File layout (each line is ASCII hex, newline separated):
///   * **Header line** (no prefix): `[fileVersion 1][siliconId 4][siliconRev 1]
///     [checksumType 1]` = 7 bytes / 14 hex chars.
///   * Lines beginning with `@`: directives, notably
///       - `@APPINFO:0x<start>,0x<size>` — application start address and length,
///         sent to the device via the Set Application Metadata DFU command.
///       - `@EIV:<hex>` — encryption initialisation vector (Set EIV command).
///   * Lines beginning with `:`: data rows — `[address 4][data...]`, all hex.
///
/// This parser is deliberately transport agnostic and side-effect free so the
/// DFU host logic on top of it can be unit tested without a device.
class Cyacd2File {
  Cyacd2File({
    required this.fileVersion,
    required this.siliconId,
    required this.siliconRev,
    required this.checksumType,
    required this.rows,
    this.appId,
    this.productId,
    this.appInfoAddress,
    this.appInfoSize,
    this.eiv,
  });

  final int fileVersion;
  final int siliconId;
  final int siliconRev;

  /// Row checksum type declared by the file: `0` = 2's-complement sum,
  /// `1` = CRC-16. (PainDrain images are built with `0` — basic summation, see
  /// the bootloader's `CY_BOOTLOAD_OPT_PACKET_CRC == 0`.)
  final int checksumType;

  /// Application/slot id from the header (header byte 7), if present. For the
  /// PainDrain dual-app build this is the slot the image was linked for.
  final int? appId;

  /// Product id from the header (header bytes 8..11), if present
  /// (PainDrain = `0x01020304`). Sent with the Enter command.
  final int? productId;

  /// Application start address from `@APPINFO`, if present.
  final int? appInfoAddress;

  /// Application size from `@APPINFO`, if present.
  final int? appInfoSize;

  /// Encryption initialisation vector from `@EIV`, if present.
  final Uint8List? eiv;

  final List<Cyacd2Row> rows;

  /// Total number of data bytes across every row — useful for progress UIs.
  int get totalDataBytes =>
      rows.fold(0, (sum, row) => sum + row.data.length);

  factory Cyacd2File.parse(String contents) {
    final lines = contents
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      throw const FormatException('Empty .cyacd2 file');
    }

    // --- Header line -------------------------------------------------------
    final header = _hexToBytes(lines.first);
    if (header.length < 7) {
      throw FormatException('Truncated .cyacd2 header: "${lines.first}"');
    }
    final fileVersion = header[0];
    final siliconId = header[1] |
        (header[2] << 8) |
        (header[3] << 16) |
        (header[4] << 24);
    final siliconRev = header[5];
    final checksumType = header[6];
    // The PainDrain header extends the 7-byte standard with appId + productId:
    // [fileVersion 1][siliconId 4][siliconRev 1][checksumType 1][appId 1]
    // [productId 4].
    final appId = header.length >= 8 ? header[7] : null;
    final productId = header.length >= 12
        ? header[8] |
            (header[9] << 8) |
            (header[10] << 16) |
            (header[11] << 24)
        : null;

    int? appInfoAddress;
    int? appInfoSize;
    Uint8List? eiv;
    final rows = <Cyacd2Row>[];

    for (final line in lines.skip(1)) {
      if (line.startsWith('@')) {
        _parseDirective(
          line,
          onAppInfo: (addr, size) {
            appInfoAddress = addr;
            appInfoSize = size;
          },
          onEiv: (bytes) => eiv = bytes,
        );
      } else if (line.startsWith(':')) {
        rows.add(_parseRow(line.substring(1)));
      } else {
        throw FormatException('Unrecognised .cyacd2 line: "$line"');
      }
    }

    if (rows.isEmpty) {
      throw const FormatException('.cyacd2 file contained no data rows');
    }

    return Cyacd2File(
      fileVersion: fileVersion,
      siliconId: siliconId,
      siliconRev: siliconRev,
      checksumType: checksumType,
      appId: appId,
      productId: productId,
      appInfoAddress: appInfoAddress,
      appInfoSize: appInfoSize,
      eiv: eiv,
      rows: rows,
    );
  }

  static void _parseDirective(
    String line, {
    required void Function(int address, int size) onAppInfo,
    required void Function(Uint8List eiv) onEiv,
  }) {
    final colon = line.indexOf(':');
    if (colon < 0) return; // Unknown directive without a value — ignore.
    final key = line.substring(1, colon).toUpperCase();
    final value = line.substring(colon + 1).trim();

    switch (key) {
      case 'APPINFO':
        final parts = value.split(',');
        if (parts.length >= 2) {
          onAppInfo(_parseInt(parts[0]), _parseInt(parts[1]));
        }
        break;
      case 'EIV':
        onEiv(_hexToBytes(value));
        break;
      default:
        // Forward-compatible: ignore directives we do not understand.
        break;
    }
  }

  static Cyacd2Row _parseRow(String hex) {
    final bytes = _hexToBytes(hex);
    if (bytes.length < 4) {
      throw FormatException('Row too short: "$hex"');
    }
    final address =
        bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
    final data = Uint8List.sublistView(bytes, 4);
    return Cyacd2Row(address: address, data: data);
  }

  static int _parseInt(String value) {
    final v = value.trim();
    return v.toLowerCase().startsWith('0x')
        ? int.parse(v.substring(2), radix: 16)
        : int.parse(v);
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.trim();
    if (clean.length.isOdd) {
      throw FormatException('Hex string has odd length: "$hex"');
    }
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byte = int.tryParse(clean.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) {
        throw FormatException('Invalid hex byte in "$hex"');
      }
      out[i] = byte;
    }
    return out;
  }
}
