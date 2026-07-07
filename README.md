# Orbit Portal

## Description
Dock-style portal UI with arc-wrap layout, centre-out edge-fade, and a hover reveal animation. A separate sub-addon (`Orbit_Portal.toc`, `## Dependencies: Orbit`) — it depends on Orbit Core; Orbit Core must never reference it.

## Purpose
Replaces standalone portal addons with a compact dock of available teleports, portals, hearthstones, toys, and housing. Icons lie along a configurable arc and dim per step outward from the centre; shift+scroll jumps categories; while hovering, typing filters the dock to the matching portals — short code like `MT`, a name, or a category like `Legion` (surfaces the whole Legion Dungeons category), prefix/substring ranked with prefixes on top. The readout turns red on no match, `TAB`/wheel page any overflow, and cursor movement over the dock keeps the filter up so a result can be moused over and clicked.

## Implementation
`PortalDock.lua` is the plugin root: it calls `Orbit:RegisterPlugin("Portal Dock", "Orbit_Portal", …)`, owns the dock frame, and owns a shared `ctx` table (exposed as `addon.PortalDockContext`) that every extracted module receives — `ctx.plugin`, `ctx.dock`, `ctx.content` (the icon-bearing child), `ctx.state` (`portalList`, `visibleIcons`, `scrollOffset`, `mythicPlusCache`, `pendingRefresh`, …), and three repaint doors:

- `ctx.RefreshDock()` — full rescan + filter + sort + paint, combat-gated. Set-change events only (category toggle, rescan, `SPELLS_CHANGED`, `PLAYER_ENTERING_WORLD`).
- `ctx.RepaintIcons()` — paint-only from cached `state.portalList`, no Scanner call. Hot paths: scroll, type-to-search, cooldown ticker. Renders `state.searchFilter` (ranked matches) when set, else the full list; shows each item once — `min(count, maxVisible)` centred — windowing `renderList` with wraparound so the wheel cycles a short result set (a single match can't scroll). The dock **frame** always sizes to the full-list `maxVisible` so the hover zone never collapses under the cursor while filtering.
- `ctx.RequestRefresh()` — debounced (`Orbit.Async`, key `OrbitPortal_Refresh`): coalesces the PEW/ApplySettings/housing/`SPELLS_CHANGED` burst into one trailing scan, refreshing now or deferring `pendingRefresh` to `PLAYER_REGEN_ENABLED` when combat starts mid-window. Use in any handler that may fire in combat or in bursts.

Load order (`Orbit_Portal.toc`) is data → pure helpers → runtime → root; no sibling requires `PortalDock` at file-scope load, runtime lookups via `addon.Portal*` are fine:

| File | Job |
|---|---|
| `PortalData.lua` | static portal/toy/hearthstone definitions, category order, seasonal lists |
| `PortalLayout.lua` | pure arc-wrap + centre-out fade math, stateless |
| `PortalCanvas.lua` | Canvas Mode per-icon apply (DungeonScore, DungeonShort, Timer, FavouriteStar) |
| `PortalScanner.lua` | runtime detection — spells, toys, items, housing, cooldowns |
| `State/PortalFavorites.lua` | favourite persistence via `Plugin:GetSetting/SetSetting` |
| `State/PortalCombat.lua` | `CanInteract` gate + reconciler on `PLAYER_REGEN_*` / `ENCOUNTER_*` |
| `View/PortalTooltip.lua` | hover tooltip (M+ season best, cooldowns) |
| `View/PortalIcon.lua` | secure action-button factory + per-data configure |
| `View/PortalReveal.lua` | hover reveal/conceal animation (Off / Slide / Fade) |
| `Input/PortalNavigation.lua` | scroll + shift-category-jump + typeahead search capture frame |
| `Settings/PortalSchema.lua` | settings UI schema (Layout + Categories tabs) |
| `Settings/PortalCommands.lua` | `scan` command from Spotlight — wipes the M+ cache, refreshes |
| `PortalDock.lua` | plugin root — registration, ctx, dock frame, RefreshDock, lifecycle |

Orbit Core surface used: `Orbit:RegisterPlugin` / `PluginMixin` (`GetSetting`/`SetSetting`, standard + visibility events), `OrbitEngine.Config:Render`, `OrbitEngine.Frame` (settings listener, `RestorePosition`), `OrbitEngine.Pixel`, `OrbitEngine.PositionUtils` / `OverrideUtils` for Canvas Mode text, `Orbit.EventBus`, `Orbit.L`.

## Gotchas
- Dependency direction is inward only: `PortalDock` → sibling modules → `PortalLayout` / `PortalCanvas` / `PortalData`.
- Secure button attributes must be cleared during Edit Mode; scanning is combat-safe by queuing through `pendingRefresh`. The dock is hidden in combat and the reveal tween snaps and stops under lockdown.
- The cast binds to `type1` (left mouse) only, leaving right-click free to toggle favourite (insecure `PreClick`, gated on `down` so the up-edge doesn't double-toggle) — right-click never casts.
- Mouse-enabled icons swallow the wheel instead of passing it to the dock, so each icon forwards `OnMouseWheel` to the dock handler via `ctx.HandleWheel` — otherwise scrolling over a result (which covers the dock) wouldn't scroll/page.
- Filter engage/clear fades the new icon set in (`state.animatePaint` one-shot → `Icon.PlayAppear`); it animates **alpha only** because `SetScale` on the secure buttons would taint in combat. Refines (query→query) and scroll/cooldown repaints snap, so fast typing doesn't strobe.
- The reveal animation moves/fades `ctx.content` only, never the dock — the dock stays a fixed hover-summon zone. `ctx.HoverEnter`/`ctx.HoverExit` (both keyed on `ctx.IsCursorOverDock()`, hit rect padded by `HOVER_HIT_INSET`) are the single hover path for the dock, every icon, and the search reconciler, so moving Slide icons never pump hover state.
- Typeahead consumes printable keys (typing `M` must not also open the map) but passes through ESC/Enter/F-keys/arrows/modifiers and everything while an editbox is focused. Matching is prefix-then-substring ranked (prefixes win); a live query **filters** the dock to the matches (`state.searchFilter`, each shown once and centred, windowed with wraparound so the wheel cycles a short set) and prints in the bottom-right readout (red on no match). The reset timer (~0.8s) is extended by typing, `TAB`, wheel, and **cursor movement over the dock** (`KeepSearchAlive`), so the results persist while the user reaches for one; it fires only once the cursor is idle/gone, clearing the filter back to the full list. `TAB`/wheel cycle/page the results and are consumed only while a query is live (else `TAB` targets normally). The dock frame stays full-size while filtering so the hover zone can't collapse under the cursor. RepaintIcons can `Hide` an icon out from under a stationary cursor and eat its `OnLeave`, so the shown (keyboard-capturing) search frame polls `IsCursorOverDock()` throttled and runs `HoverExit` on miss, and `HideSearch` restores key propagation — together they stop the frame being stranded shown and eating the keyboard. `RestorePropagationDefault` re-seats propagation after a combat-time `/reload` (`SetPropagateKeyboardInput` is protected in combat).
- Cooldown display uses `SetCooldown()` — no manual OnUpdate tickers.
- User-visible strings go through `Orbit.L` (`PLU_PORTAL_*` plugin UI, `CMD_PORTAL_*` slash output).

## Secrets
`C_MythicPlus.GetSeasonBest*` returns and item cooldown start/duration can be secret: `PortalTooltip`, `PortalCanvas`, and `PortalScanner` guard with `issecretvalue()` before any comparison, arithmetic, or caching. Never use `pcall` as a secret-value shield.

## References
- `Orbit/Localization/README.md` — string conventions; Orbit repo `CLAUDE.md` — architecture and secret-value rules.
- `Orbit_Portal.toc` — load order and packaging metadata (CurseForge project 1439533).
