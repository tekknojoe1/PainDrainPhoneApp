import 'package:flutter_test/flutter_test.dart';
import 'package:pain_drain_mobile_app/ota/ota_manifest.dart';
import 'package:pain_drain_mobile_app/ota/update_decision.dart';

void main() {
  group('incompatibilityReason', () {
    test('empty allow-lists accept any device', () {
      expect(
        incompatibilityReason(
          compatibleModels: const [],
          compatibleHardwareRevisions: const [],
          deviceModel: 'ANYTHING',
          deviceHardwareRevision: 'ANYTHING',
        ),
        isNull,
      );
      // Even unknown device values are accepted when the lists are empty.
      expect(
        incompatibilityReason(
          compatibleModels: const [],
          compatibleHardwareRevisions: const [],
          deviceModel: null,
          deviceHardwareRevision: null,
        ),
        isNull,
      );
    });

    test('matching model and hardware revision is compatible', () {
      expect(
        incompatibilityReason(
          compatibleModels: const ['BDC-PD-SD-001'],
          compatibleHardwareRevisions: const ['PD-SD-001'],
          deviceModel: 'BDC-PD-SD-001',
          deviceHardwareRevision: 'PD-SD-001',
        ),
        isNull,
      );
    });

    test('model not in a non-empty allow-list is rejected', () {
      final reason = incompatibilityReason(
        compatibleModels: const ['BDC-PD-SD-001'],
        compatibleHardwareRevisions: const [],
        deviceModel: 'OTHER-MODEL',
        deviceHardwareRevision: 'PD-SD-001',
      );
      expect(reason, isNotNull);
      expect(reason, contains('model'));
    });

    test('hardware revision not in a non-empty allow-list is rejected', () {
      final reason = incompatibilityReason(
        compatibleModels: const [],
        compatibleHardwareRevisions: const ['PD-SD-001'],
        deviceModel: 'BDC-PD-SD-001',
        deviceHardwareRevision: 'PD-SD-999',
      );
      expect(reason, isNotNull);
      expect(reason, contains('hardware revision'));
    });

    test('unknown device value fails a non-empty allow-list (fail safe)', () {
      expect(
        incompatibilityReason(
          compatibleModels: const ['BDC-PD-SD-001'],
          compatibleHardwareRevisions: const [],
          deviceModel: null,
          deviceHardwareRevision: null,
        ),
        isNotNull,
      );
    });

    test('model is checked before hardware revision', () {
      final reason = incompatibilityReason(
        compatibleModels: const ['BDC-PD-SD-001'],
        compatibleHardwareRevisions: const ['PD-SD-001'],
        deviceModel: 'WRONG',
        deviceHardwareRevision: 'ALSO-WRONG',
      );
      expect(reason, contains('model'));
    });
  });

  group('OtaManifest compatibility fields', () {
    test('parses product id and allow-lists', () {
      final m = OtaManifest.fromJson(const {
        'firmware_version': '1.1.2.7',
        'version': 10102,
        'product_id': '0x50440001',
        'compatible_models': ['BDC-PD-SD-001'],
        'compatible_hardware_revisions': ['PD-SD-001'],
        'slots': {'0': 'a.cyacd2', '1': 'b.cyacd2'},
      });
      expect(m.productId, '0x50440001');
      expect(m.compatibleModels, ['BDC-PD-SD-001']);
      expect(m.compatibleHardwareRevisions, ['PD-SD-001']);
    });

    test('absent compatibility fields default to accept-any', () {
      final m = OtaManifest.fromJson(const {
        'firmware_version': '1.1.0.6',
        'version': 10100,
        'slots': {'0': 'a.cyacd2', '1': 'b.cyacd2'},
      });
      expect(m.productId, isNull);
      expect(m.compatibleModels, isEmpty);
      expect(m.compatibleHardwareRevisions, isEmpty);
    });
  });
}
