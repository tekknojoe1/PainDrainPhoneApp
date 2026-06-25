# OTA firmware artifacts

Drop the firmware build's `PainDrain_ota_v<version>.zip` here as
`PainDrain_ota.zip` (the default `BundledOtaSource.assetPath`).

The zip must contain:

- `manifest.json`
  ```json
  {
    "firmware_version": "1.1.0.6",
    "version": 10100,
    "slots": { "0": "PainDrain_slot0.cyacd2", "1": "PainDrain_slot1.cyacd2" }
  }
  ```
- `PainDrain_slot0.cyacd2` and `PainDrain_slot1.cyacd2` — the two per-slot
  Cypress DFU images.

To ship firmware over the network instead of bundling it, implement
`DownloadOtaSource.load()` (see `lib/ota/ota_source.dart`) and pass that source
to `OtaNotifier`.
