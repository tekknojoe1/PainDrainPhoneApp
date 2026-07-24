/// Outcome of comparing the firmware available in an OTA artifact against the
/// version currently running on the device.
enum UpdateStatus {
  /// Manifest version equals the device version — nothing to do.
  upToDate,

  /// Manifest version is newer than the device version — offer the update.
  updateAvailable,

  /// Manifest version is older than the device version — a downgrade, which we
  /// skip/warn about rather than perform automatically.
  downgrade,
}

/// Pure decision logic: should we offer to flash [manifestVersion] onto a device
/// currently running [deviceVersion]?
///
/// Both arguments are the numeric form (`MAJOR * 10000 + MINOR * 100 + PATCH`).
/// The device firmware also self-protects (it rejects writes to its running
/// slot), but we check here first to avoid a pointless multi-thousand-row
/// transfer.
UpdateStatus decideUpdate({
  required int deviceVersion,
  required int manifestVersion,
}) {
  if (manifestVersion > deviceVersion) {
    return UpdateStatus.updateAvailable;
  }
  if (manifestVersion < deviceVersion) {
    return UpdateStatus.downgrade;
  }
  return UpdateStatus.upToDate;
}

/// Returns a human-readable reason the image is NOT compatible with the
/// connected device, or `null` if it is compatible.
///
/// [compatibleModels] and [compatibleHardwareRevisions] are exact-match
/// allow-lists from the manifest; an empty list means "accept any". A null /
/// unknown device value fails a non-empty allow-list (fail safe — we won't flash
/// if we can't confirm the device matches).
String? incompatibilityReason({
  required List<String> compatibleModels,
  required List<String> compatibleHardwareRevisions,
  required String? deviceModel,
  required String? deviceHardwareRevision,
}) {
  if (compatibleModels.isNotEmpty &&
      (deviceModel == null || !compatibleModels.contains(deviceModel))) {
    return 'This update is not for your device model'
        '${deviceModel != null ? ' ($deviceModel)' : ''}.';
  }
  if (compatibleHardwareRevisions.isNotEmpty &&
      (deviceHardwareRevision == null ||
          !compatibleHardwareRevisions.contains(deviceHardwareRevision))) {
    return 'This update is not compatible with your hardware revision'
        '${deviceHardwareRevision != null ? ' ($deviceHardwareRevision)' : ''}.';
  }
  return null;
}
