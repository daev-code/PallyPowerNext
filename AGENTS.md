# AGENTS.md - PallyPowerNext

Companion addon for [PallyPowerTW](https://github.com/ShikawaLePaladin/PallyPowerTW). What it does for players (order, clicks, options, rules) is in `README.md`; this file covers internals and how to work on it.

Files: `PallyPowerNext.toc`, `PallyPowerNext.lua`, `README.md` (user docs), this file.

## How it hooks into PallyPowerTW

- Reads PallyPowerTW globals: `AllPallys`, `PallyPower_Assignments`, `GetNormalBlessings`,
  `CurrentBuffs`, the timers `LastCast` / `LastCastPlayer`,
  `PallyPower_CastingSalvationOnTank`, `PallyPower_CheckTargetLoS`,
  `PALLYPOWER_*BLESSINGDURATION`.
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
- Collapsed buff bar: PallyPower's buttons are faded out and made click-through rather than
  hidden, because PallyPower shows and hides them itself on every layout update.
- Tooltip: a tooltip line only has a left and a right text, so the icons and middle columns
  are overlays at fixed offsets; the name is padded with spaces so the tooltip is wide
  enough.
- Wraps the globals `PallyPowerBuffBar_MouseUp` and `PallyPower_ScaleFrame` (below layout)
  and the "Pally Buffs" title's `OnEnter` (collapse). The options section is added to
  `PallyPower_OptionsFrame` at file load.
- Settings: `PPNext_Settings` (per character).

## Environment

- Client: WoW 1.12.1, so **Lua 5.0**: `table.getn` (no `#`),
  `string.find` / `string.gsub` (no `string.match` / `gmatch`), `math.mod`, varargs via `arg`.
- Scripts use the 1.12 globals `this`, `event`, `arg1`..`argN`. There is no `HookScript`:
  wrap with `GetScript` / `SetScript`, or replace global functions.
- SavedVariables are loaded after the addon's files: read settings in `ADDON_LOADED` /
  `PLAYER_LOGIN`, not at file load.
- No `_G` in plain Lua 5.0: use `getfenv(0)` or `getglobal()`.

## Working copy vs repo

The live copy is in the game's `Interface\AddOns\PallyPowerNext` folder. Edit there, test in game with
`/reload`, then copy the changed files into this repo and commit. Before committing, check
that both copies are identical (for example by comparing hashes).

## Rules

- Never edit the addon this extends (`PallyPowerTW`). Its folder must stay a clean git clone
  of https://github.com/ShikawaLePaladin/PallyPowerTW. Everything goes in this companion addon.
- UI conventions: prefer buttons and settings over slash commands (slash commands only as
  show/hide/toggle shortcuts); muted, darkened status colours.
- Nothing here needs network access; go easy on external APIs.

## Pre-commit checklist

1. Update `README.md` for any user-visible change (settings, clicks, behaviour) and this file
   for internals (hooks, stored values, timing). Don't repeat one in the other.
2. Keep the header comment in the `.lua` in sync with what the code does.
3. There are no automated tests: verify in game (`/reload`, and a full relog when
   SavedVariables or the `.toc` changed). Say in the report what wasn't tested.
4. Copy the game-folder files into the repo, then commit code and docs together.
5. Don't commit scratch notes, logs or downloaded third-party files. The repo is public:
   keep personal details (names, local paths, account or character names) out of files and
   commit messages, and don't name the specific client, launcher, server or realm this is
   played on. Say "WoW 1.12" and link the repo of the addon being extended instead.
6. Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages
   and PR titles (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`). See `CONTRIBUTING.md`.
