import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

import '../../models/ota_state.dart';
import '../../providers/ota_notifier.dart';
import '../../utils/app_colors.dart';
import '../../widgets/battery_indicator.dart';

/// Firmware update screen. Shows the current vs available firmware version and
/// surfaces the OTA states: up-to-date, update available, updating (%),
/// success, and failed (retryable).
class OtaScreen extends ConsumerStatefulWidget {
  const OtaScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<OtaScreen> createState() => _OtaScreenState();
}

class _OtaScreenState extends ConsumerState<OtaScreen> {
  @override
  void initState() {
    super.initState();
    // Kick off a check as soon as the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(otaNotifierProvider.notifier).checkForUpdate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ota = ref.watch(otaNotifierProvider);
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text('Firmware Update',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.blue.shade800,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [Center(child: BatteryIndicator())],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            _versionCard(ota),
            const SizedBox(height: 24),
            Expanded(child: Center(child: _statusBody(ota))),
            _actions(ota),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _versionCard(OtaState ota) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _versionRow('Current firmware',
                ota.currentVersionString ?? '—'),
            const Divider(),
            _versionRow('Available firmware',
                ota.availableVersionString ?? '—'),
            if (ota.currentFirmware != null) ...[
              const Divider(),
              _versionRow(
                'Running slot → update slot',
                '${ota.currentFirmware!.runningSlot} → '
                    '${ota.currentFirmware!.inactiveSlot}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _versionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16, color: Colors.black87)),
          Text(value,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _statusBody(OtaState ota) {
    switch (ota.status) {
      case OtaStatus.checking:
        return _centered(
          const CircularProgressIndicator(),
          'Checking for updates…',
        );
      case OtaStatus.updating:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearPercentIndicator(
              lineHeight: 14,
              percent: ota.progress.clamp(0.0, 1.0),
              barRadius: const Radius.circular(7),
              progressColor: AppColors.blue,
              backgroundColor: Colors.grey.shade300,
              center: Text('${(ota.progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 10)),
            ),
            const SizedBox(height: 16),
            Text(ota.message ?? 'Updating…',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 8),
            const Text('Keep the device close and powered.',
                style: TextStyle(color: Colors.black38, fontSize: 12)),
          ],
        );
      case OtaStatus.success:
        return _centered(
          const Icon(Icons.check_circle, color: AppColors.green, size: 64),
          ota.message ?? 'Update complete',
        );
      case OtaStatus.upToDate:
        return _centered(
          const Icon(Icons.verified, color: AppColors.green, size: 64),
          ota.message ?? 'Firmware is up to date',
        );
      case OtaStatus.updateAvailable:
        return _centered(
          const Icon(Icons.system_update, color: AppColors.blue, size: 64),
          ota.message ?? 'An update is available',
        );
      case OtaStatus.wrongSlot:
        return _centered(
          const Icon(Icons.sync_problem, color: AppColors.amber, size: 64),
          ota.message ?? 'Re-checking the device…',
        );
      case OtaStatus.failed:
        return _centered(
          const Icon(Icons.error_outline, color: Colors.red, size: 64),
          ota.message ?? 'Update failed',
        );
      case OtaStatus.idle:
        return _centered(
          const Icon(Icons.system_update_alt, color: Colors.black38, size: 64),
          'Tap “Check for updates” to begin',
        );
    }
  }

  Widget _centered(Widget icon, String text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(height: 16),
        Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.black87)),
      ],
    );
  }

  Widget _actions(OtaState ota) {
    final notifier = ref.read(otaNotifierProvider.notifier);

    switch (ota.status) {
      case OtaStatus.updateAvailable:
        return _primaryButton('Update now', AppColors.blue, notifier.startUpdate);
      case OtaStatus.updating:
        return _primaryButton('Cancel', Colors.red, notifier.cancel);
      case OtaStatus.failed:
        return _primaryButton('Retry', AppColors.blue, notifier.checkForUpdate);
      case OtaStatus.success:
      case OtaStatus.upToDate:
      case OtaStatus.wrongSlot:
        return _primaryButton(
            'Check again', Colors.blue.shade800, notifier.checkForUpdate);
      case OtaStatus.checking:
        return const SizedBox.shrink();
      case OtaStatus.idle:
        return _primaryButton(
            'Check for updates', AppColors.blue, notifier.checkForUpdate);
    }
  }

  Widget _primaryButton(String label, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onPressed,
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
    );
  }
}
