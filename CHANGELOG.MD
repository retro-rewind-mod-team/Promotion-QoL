# Changelog

## 1.2
- Extracted inline `CONFIG` block into a separate `config.lua` for RRMM support
- `conversionRate` changed from a nullable float (`nil` / 0.0–1.0) to an integer 0–100, where `0` retains the native store popularity rate — aligns with the RRMM YAML schema
- Added `Promotion-QoL.yaml` with full config definition for RRMM

## 1.1
- Added `flyerDelay` — new walkby NPCs that spawn while the store is open are queued and receive their flyer after a configurable ingame delay instead of being missed entirely
- Added `conversionRate` override — set a fixed acceptance chance instead of using the native store popularity rate
- Conversion chance is now read from the AI Director on store open and refreshed every ingame hour
- Daily stats logged on store close (customers gained, flyers given)

## 1.0
- Initial release
