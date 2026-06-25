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
