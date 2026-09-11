# Portal localization

## Description
Portal's standalone string registry, available before product modules load.

## Purpose
Keep all controls and status messages usable with Orbit absent while preserving nine-locale coverage.

## Implementation
`Generated.lua` contains the existing Portal and common strings exported from Orbit's authored domains by `package-orbit-ui.py`. Its content hash is recorded in the embedding manifest. `Portal.lua` and `Messages.lua` own the standalone controls and status messages added by this product, merging the selected locale into `addon.L`. The legacy Orbit integration may use its own host localization for host-owned controls.

## Gotchas
Never hand-edit `Generated.lua`. New product-owned strings require entries in all nine locales. `enGB` uses `enUS`; `esMX` uses `esES`. These tables use the client locale and do not read another addon's SavedVariables.

## References
Orbit `Localization/README.md`; `Orbit/.scripts/package-orbit-ui.py`.
