import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ota_state.dart';
import '../ota/dfu_transfer.dart';
import '../ota/ota_service.dart';
import '../ota/ota_source.dart';
import '../ota/update_decision.dart';
import 'bluetooth_notifier.dart';

/// Kept-alive provider for the OTA flow. Hand-written (rather than codegen) so
/// the feature does not depend on the build_runner toolchain — see [OtaState].
final otaNotifierProvider =
    NotifierProvider<OtaNotifier, OtaState>(OtaNotifier.new);

/// Drives the OTA flow on top of the existing BLE connection:
/// check -> (offer) -> update -> reconnect & verify.
class OtaNotifier extends Notifier<OtaState> {
  final OtaService _service = OtaService(log: _log);
  final OtaSource _source = const BundledOtaSource();
  DfuCancelToken? _cancelToken;

  static void _log(String message) {
    // ignore: avoid_print
    print('[OTA] $message');
  }

  @override
  OtaState build() => const OtaState();

  BluetoothDevice? get _device =>
      ref.read(bluetoothNotifierProvider).connectedDevice;

  /// Reads the running firmware/slot, loads the bundled artifact, and decides
  /// whether an update is available.
  Future<void> checkForUpdate() async {
    final device = _device;
    if (device == null) {
      state = state.copyWith(
        status: OtaStatus.failed,
        message: 'No device connected',
      );
      return;
    }

    state = state.copyWith(status: OtaStatus.checking, message: null);
    try {
      final firmware = await _service.readFirmwareInfo(device);
      final package = await _source.load();

      // Compatibility pre-flight: model + hardware-revision allow-lists from the
      // manifest, matched against the device's DIS values (read at connect). The
      // device also enforces the product ID itself at DFU ENTER. Block here with
      // a clear message rather than failing mid-transfer.
      final bt = ref.read(bluetoothNotifierProvider.notifier);
      final incompatible = incompatibilityReason(
        compatibleModels: package.manifest.compatibleModels,
        compatibleHardwareRevisions:
            package.manifest.compatibleHardwareRevisions,
        deviceModel: bt.deviceModelNumber,
        deviceHardwareRevision: bt.deviceHardwareRevision,
      );
      if (incompatible != null) {
        state = state.copyWith(
          status: OtaStatus.incompatible,
          currentFirmware: firmware,
          manifest: package.manifest,
          message: incompatible,
        );
        return;
      }

      final decision = decideUpdate(
        deviceVersion: firmware.version,
        manifestVersion: package.manifest.version,
      );

      switch (decision) {
        case UpdateStatus.updateAvailable:
          state = state.copyWith(
            status: OtaStatus.updateAvailable,
            currentFirmware: firmware,
            manifest: package.manifest,
            message: 'Update available: '
                '${firmware.versionString} → ${package.manifest.firmwareVersion}',
          );
          break;
        case UpdateStatus.upToDate:
          state = state.copyWith(
            status: OtaStatus.upToDate,
            currentFirmware: firmware,
            manifest: package.manifest,
            message: 'Firmware is up to date (${firmware.versionString})',
          );
          break;
        case UpdateStatus.downgrade:
          state = state.copyWith(
            status: OtaStatus.upToDate,
            currentFirmware: firmware,
            manifest: package.manifest,
            message: 'Device firmware (${firmware.versionString}) is newer '
                'than the bundled image (${package.manifest.firmwareVersion})',
          );
          break;
      }
    } catch (e) {
      state = state.copyWith(
        status: OtaStatus.failed,
        message: 'Could not check for updates: $e',
      );
    }
  }

  /// Flashes the image for the device's inactive slot, then reconnects and
  /// re-reads the DIS to confirm the new version.
  Future<void> startUpdate() async {
    final device = _device;
    final firmware = state.currentFirmware;
    if (device == null || firmware == null) {
      state = state.copyWith(
        status: OtaStatus.failed,
        message: 'Run a check before updating',
      );
      return;
    }

    _cancelToken = DfuCancelToken();
    state = state.copyWith(
      status: OtaStatus.updating,
      progress: 0,
      message: 'Preparing image for slot ${firmware.inactiveSlot}…',
    );

    try {
      // Redundancy: make sure no stimulus is active before flashing begins.
      // The firmware also disables all functionality during an update; this is
      // a belt-and-suspenders in case that path is ever missed.
      await ref.read(bluetoothNotifierProvider.notifier).shutOffAllStimuli();

      final package = await _source.load();
      final image = package.imageForSlot(firmware.inactiveSlot);

      final result = await _service.flashImage(
        device,
        image,
        cancelToken: _cancelToken,
        onProgress: (p) {
          state = state.copyWith(status: OtaStatus.updating, progress: p);
        },
      );

      switch (result.type) {
        case DfuResultType.success:
          state = state.copyWith(
            status: OtaStatus.success,
            progress: 1,
            message: 'Update sent. Device is restarting…',
          );
          await _verifyAfterReset(device);
          break;
        case DfuResultType.wrongSlot:
          // Device refused the write and is unharmed. Surface the message and
          // stop — do NOT auto re-check (that would overwrite this state and
          // silently bounce back to "update available" with no explanation).
          // The user can re-check from the screen.
          state = state.copyWith(
            status: OtaStatus.wrongSlot,
            message: result.message ?? 'Wrong slot file or already up to date.',
          );
          break;
        case DfuResultType.cancelled:
          // User cancelled: the device aborted the DFU in place and stayed
          // connected, so return to the "update available" state — the user can
          // retry on the same link with no reconnect. Not an error.
          state = state.copyWith(
            status: OtaStatus.updateAvailable,
            progress: 0,
            message: result.message ?? 'Update cancelled',
          );
          break;
        case DfuResultType.incompatible:
          // Device rejected DFU ENTER (product-ID mismatch) — terminal, not
          // retryable with this image.
          state = state.copyWith(
            status: OtaStatus.incompatible,
            message: result.message ?? 'Incompatible firmware for this device.',
          );
          break;
        case DfuResultType.failed:
          state = state.copyWith(
            status: OtaStatus.failed,
            message: result.message ?? 'Update failed',
          );
          break;
      }
    } catch (e) {
      state = state.copyWith(
        status: OtaStatus.failed,
        message: 'Update failed: $e',
      );
    } finally {
      _cancelToken = null;
    }
  }

  /// Cancels an in-progress transfer.
  ///
  /// Order matters: halt the bootloader (DFU) writes first via the cancel
  /// token, THEN tell the device to abort in place by writing "cancel" on the
  /// custom characteristic. The firmware resets its DFU session and re-enables
  /// all functions while keeping the BLE link up, so the update can be retried
  /// on the same connection. Stopping the token before sending "cancel" avoids
  /// a queued ProgramData write landing after the firmware's reset.
  Future<void> cancel() async {
    _cancelToken?.cancel();
    await ref.read(bluetoothNotifierProvider.notifier).sendOtaCancel();
  }

  /// After the device resets into the new slot, reconnect and re-read the DIS
  /// to confirm success and refresh the displayed version/slot.
  Future<void> _verifyAfterReset(BluetoothDevice device) async {
    // The device drops the link as it resets — give it a moment to reboot.
    await Future<void>.delayed(const Duration(seconds: 3));

    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (device.isDisconnected) {
          await device.connect(timeout: const Duration(seconds: 10));
        }
        final firmware = await _service.readFirmwareInfo(device);
        state = state.copyWith(
          status: OtaStatus.success,
          currentFirmware: firmware,
          message: 'Updated to ${firmware.versionString} '
              '(slot ${firmware.runningSlot})',
        );
        return;
      } catch (e) {
        _log('Verify attempt ${attempt + 1} failed: $e');
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }

    // The flash itself succeeded; we just could not auto-reconnect to confirm.
    state = state.copyWith(
      status: OtaStatus.success,
      message: 'Update sent. Reconnect to the device to confirm the new '
          'version.',
    );
  }
}
