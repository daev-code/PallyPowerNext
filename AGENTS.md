# AGENTS.md - PallyPowerNext

Companion addon for [PallyPowerTW](https://github.com/ShikawaLePaladin/PallyPowerTW) or
[Aegis: RallyPower](https://github.com/Torchlite-bit/Aegis_RallyPower). `README.md` is a short player overview (purpose, clicks, the button, settings, install). The full behaviour rules (cast order, click scope, statuses, totals, timers) are under "How it works in detail" in `CONTRIBUTING.md`. This file covers internals and how to work on it.

Files: `PallyPowerNext.toc`, `PallyPowerNext.lua`, `README.md` (user overview), `CONTRIBUTING.md` (contributing and detailed behaviour), this file.

## How it hooks into PallyPowerTW

- Host: both addons are `OptionalDeps`; `HOST` holds the loaded one's folder (icon paths)
  and bar title. With neither, the file returns early. RallyPower bundles an older copy of
  the PallyPowerTW engine with the same globals, so everything below applies to both.
- RallyPower's Options button opens its own `AegisRP_OptionsFrame`, so the settings
  section is also added to its Buttons tab from outside (its code is all local): see the
  comment above `rally.build`.
- Reads PallyPowerTW globals: `AllPallys`, `PallyPower_Assignments`, `GetNormalBlessings`,
  `CurrentBuffs`, the timers `LastCast` / `LastCastPlayer`,
  `PallyPower_CastingSalvationOnTank`, `PallyPower_CheckTargetLoS`,
  `PALLYPOWER_*BLESSINGDURATION`, and the icon tables `BuffIcon` (Greater) /
  `BuffIconSmall` (normal) with `RegularBlessings`.
- PallyPower's scan (`CurrentBuffs`) marks a blessing as present for either version. To find
  members who only have the normal one (`normalOnly`), the addon compares their `UnitBuff`
  textures with those two icon tables (cached per unit for 0.5 s). They're shown as `single`
  and count as covered (`memberNeeds`), so only Shift L-click (`overExisting`) recasts the
  Greater Blessing over them.
- PallyPower wipes a class timer when its UI refreshes before the buff scan sees a new buff
  (its own casts are shielded by a local this addon can't reach), so the addon keeps its own
  copy of the timers it sets (`ownTimers`) and restores them.
- Time left: with ClassicAPI loaded, from `C_UnitAuras` (expiration time); otherwise from
  `LastCast` / `LastCastPlayer` and `ownTimers`.
- Casting follows PallyPower's pattern: clear target, autoSelfCast off, `CastSpell`, test with
  `SpellCanTargetUnit`, then `SpellTargetUnit` or `SpellStopTargeting`. After each cast
  PallyPower's timers are updated the way its own buttons do.
- Range / line of sight: UnitXP_SP3 when loaded (`pcall(UnitXP, "nop", "nop")`), otherwise
  `CheckInteractDistance`. Line of sight is checked with UnitXP directly even when
  PallyPower's own UnitXP option is off (its check then always says yes). The preview can't
  put a spell on the cursor, so it uses UnitXP distance instead of `SpellCanTargetUnit`.
- The button uses `PallyPowerBuffButtonTemplate`, parented to `PallyPowerBuffBar`.
- Two markers: the tooltip's `->` (on a header) follows `status.subject`, the step the button
  shows; `>` (on a row, button and tooltip) follows `status.markName`, who the click is cast
  on. The click lines (`status.leftNext` / `status.rightNext`, for the modifiers held), the
  target and the totals are worked out once a second (and when Shift changes) in
  `computeStatus` with the same dry-run `try*` functions as the preview. R-click order
  comes from `rightClickPlan`, which the click handler uses too, so the line and the click
  can't disagree. `collect` also returns the players you have nothing assigned to ("No
  config").
- Clicks route by `status.subject` (what the button shows), not by a fresh preview, so a
  click never works on anything else. `OnClick` sets `nextRefresh = 0` so the button
  refreshes on the next frame; the recent-cast guard then moves it past the step just cast.
  Shift L-click passes `overExisting` to `tryGroup`, which skips the "nobody needs it"
  check.
- Collapsed buff bar: PallyPower's buttons are faded out and made click-through rather than
  hidden, because PallyPower shows and hides them itself on every layout update.
- Tooltip: a tooltip line only has a left and a right text, so the icons and middle columns
  are overlays at fixed offsets; the name is padded with spaces so the tooltip is wide
  enough.
- Wraps the globals `PallyPowerBuffBar_MouseUp` and `PallyPower_ScaleFrame` (below layout)
  and the "Pally Buffs" title's `OnEnter` (collapse). The options section is added to
  `PallyPower_OptionsFrame` at file load.
- Settings: `PPNext_Settings` (per character). A missing value means the default. `below`
  defaults to on: it's stored as `true`/`false` (never nil once set), and on the first login
  without it the layout is switched like the setting does, so the title stays put.
  `oocAlpha` defaults to 0.7; `others` (other blessing types in the tooltip) to off.

## Environment

- Client: WoW 1.12.1, so **Lua 5.0**: `table.getn` (no `#`),
  `string.find` / `string.gsub` (no `string.match` / `gmatch`), `math.mod`, varargs via `arg`.
- Scripts use the 1.12 globals `this`, `event`, `arg1`..`argN`. There is no `HookScript`:
  wrap with `GetScript` / `SetScript`, or replace global functions.
- SavedVariables are loaded after the addon's files: read settings in `ADDON_LOADED` /
  `PLAYER_LOGIN`, not at file load.
- No `_G` in plain Lua 5.0: use `getfenv(0)` or `getglobal()`.
- Max 200 locals per function, and the main chunk has 194: put new helpers in a table.

## Working copy vs repo

Edit the files in this repo, not the game's copy. To test, copy the changed files into the
game's `Interface\AddOns\PallyPowerNext` folder and `/reload` in game. Before copying, check
that the game's copy still matches the last commit (for example by comparing hashes), so you
don't overwrite changes made there; if it doesn't, ask first.

The game folder's location is in your local, private instructions. If it isn't there, ask
for it. Never write it into this repo (it's public).

## Rules

- Never edit the addons this extends (`PallyPowerTW`, `Aegis_RallyPower`). Their folders must
  stay clean git clones of https://github.com/ShikawaLePaladin/PallyPowerTW and
  https://github.com/Torchlite-bit/Aegis_RallyPower. Everything goes in this companion addon.
- UI conventions: prefer buttons and settings over slash commands (slash commands only as
  show/hide/toggle shortcuts); muted, darkened status colours.
- Nothing here needs network access; go easy on external APIs.

## Pre-commit checklist

1. Update the docs for any change: `README.md` only when the overview changes (purpose,
   clicks, settings), the detailed rules in `CONTRIBUTING.md`, and this file for internals
   (hooks, stored values, timing). Keep the README short and don't repeat one doc in another.
2. Keep the header comment in the `.lua` in sync with what the code does.
3. There are no automated tests: verify in game (`/reload`, and a full relog when
   SavedVariables or the `.toc` changed). Say in the report what wasn't tested.
4. Copy the changed files into the game folder and test there, then commit code and docs
   together.
5. Don't commit scratch notes, logs or downloaded third-party files. The repo is public:
   keep personal details (names, local paths, account or character names) out of files and
   commit messages, and don't name the specific client, launcher, server or realm this is
   played on. Say "WoW 1.12" and link the repo of the addon being extended instead.
6. Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages
   and PR titles (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`). See `CONTRIBUTING.md`.
7. Before pushing a change players will notice, bump `## Version:` in the `.toc` once
   per push: minor (1.1.0 -> 1.2.0) when there's a `feat:`, patch (1.1.0 -> 1.1.1) for fixes
   only. Docs-only and other changes players don't notice don't need a bump.
