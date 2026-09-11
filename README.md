# Orbit: Portal

## Description
A portal launcher with arc layout, hover reveal, favorites, category navigation and keyboard search. This development preview runs independently or attaches to an installed Orbit host; `Orbit_Portal` embeds LibOrbitUI and has its own `OrbitPortalDB`.

## Purpose
Prove that the shared movement and settings UI can serve both Orbit and standalone products while retaining Portal's travel behavior. This is the standalone library pilot, not the completed migration/export release.

## Implementation
The TOC loads the embedded library and product localization first. `PortalDefaults.lua` owns basic defaults; `PortalStore.lua` owns the standalone preview store. `PortalServices.lua` creates the private UI context and binds LibOrbitUI.Text/TextPosition for cached default fonts and basic authored placement. `Integrations/Orbit.lua` selects the legacy host bridge before feature registration; `Integrations/OrbitCanvas.lua` retains rich Canvas previews.

`Portal.lua` owns one controller and frame, an icon pool and a shared context (`ctx`). Data enters through `PortalData.lua` and `PortalScanner.lua`, geometry through `PortalLayout.lua`, and live decoration through `PortalCanvas.lua`. Secure button construction/configuration belongs to `View/PortalIcon.lua`; tooltips and reveal animations remain separate view owners. `State/PortalCombat.lua` reconciles combat/encounter restrictions, while `State/PortalFavorites.lua` persists copied preferences through the selected controller.

`ctx.Refresh()` scans and paints; `ctx.RepaintIcons()` paints the cached list. Gameplay, reveal and search frames are created during Portal's TOC load in both modes. `ctx.RequestRefresh()` queues timer creation through the gameplay frame's one-shot update; the private library runtime owns scan delays, cooldown ticks and refresh debouncing. Navigation captures search input only during frame interaction and preserves cursor/timeout behavior. Disabling cancels queued and timed gameplay work; a stable visibility reconciler remains available to finish restricted changes.

`Settings/PortalSchema.lua` declares one set of tabs and controls. Orbit and `PortalBoot.lua` bind them to the same LibOrbitUI window, panel, tab strip, scrollbar and common widget implementations. The independent dialog uses shared defaults and compact footer actions; Boot also registers an AddOns Settings entry. Without Orbit, the shared Edit Mode overlay selects/moves the existing frame and commits position at successful drag stop. Orbit owns advanced movement and Canvas when its bridge is selected.

Use `/orbitportal` for settings, `/orbitportal move` for native Edit Mode, `/orbitportal reset` for placement, `/orbitportal scan` for rescan and `/orbitportal status` for the active settings provider.

## Gotchas
- This preview deliberately preserves the existing Orbit settings path when integrated. Standalone settings are a separate store. Automatic migration, independent preset management, full external-profile export and the negotiated generic host provider remain pending; disabling Orbit does not yet transfer its profile configuration.
- The workspace-root `Orbit-Libs/LibOrbitUI/LibOrbitUI-1.0` runtime owns the shared library; consumers link directly to it during development. `Orbit/.scripts/package-orbit-ui.py` verifies the link, generates localization and records content hashes; staged packages contain regular files. Never hand-edit `Localization/Generated.lua`.
- `.pkgmeta` pins the full commit SHA of [LibOrbitUI release 1.2](https://github.com/MoONSHO7/Orbit-Libs/releases/tag/LibOrbitUI-1.2), which provides API 1.5, and selects `LibOrbitUI/LibOrbitUI-1.0`. `python .scripts/fetch-libs.py` materializes that runtime for clean-checkout validation while preserving development junctions, including with `--force`. GitHub packaging reads the same pin. Portal has no color settings and embeds no ColorPicker dependency.
- Orbit-Libs is public. CI retains its `ORBIT_PAT` Git credential policy and skips the full package check for fork and Dependabot pull requests. Trusted validation runs before tagging and publishing.
- Blizzard Edit Mode Save/Revert does not govern standalone commits. A forced hidden/combat session aborts an unfinished drag; successful drag stop commits to the product store.
- Secure action attributes are cleared during editing and when recycling icons. Left click activates travel; right-button down toggles a favorite once and never casts. The frame uses an installed secure combat visibility driver; encounter policy is checked separately before protected mutations.
- Reveal moves/fades the icon content, leaving the frame as a fixed summon zone. Search must restore keyboard propagation on hover loss, repaint, disable and combat transitions. Icon wheel handlers forward to the same navigation owner.
- `IconSize` is logical UI size; `Spacing` is physical pixels. Text and optional media have standalone defaults; advanced Canvas rendering stays in the Orbit bridge.
- Future unsupported standalone stores stay untouched and inactive. The addon does not claim to import an unavailable Orbit SavedVariables file.
- `Orbit-Portal` is the project and host plugin name; `Orbit_Portal` and `OrbitPortalDB` retain the installed addon and saved-data identity. Orbit migrates legacy enablement, visibility and frame-anchor names before hydration.

## Secrets
Season scores and cooldown values may be secret. Scanner, tooltip and live decoration guard before comparisons/arithmetic/caching; native cooldown rendering receives supported values directly. The shared library does not grant access to restricted data.

## References
`Localization/README.md`, `Libs/LibOrbitUI-1.0/README.md`, workspace standalone requirements, `Orbit_Portal.toc` and the `.scripts` source checks. In-game verification uses `/reload`, real secure clicks, native Edit Mode and BugSack; mocked checks do not certify WoW behavior.
