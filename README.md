# PallyPower Next Blessing

Companion addon for [PallyPowerTW](https://github.com/ShikawaLePaladin/PallyPowerTW) (WoW 1.12 / Turtle WoW). Adds one button that
casts the **next** blessing you still need to do, based on your PallyPower assignments: one
cast per click.

## Order

0. **Personal**: your aura (when PallyPower assigns you one) and Righteous Fury (when
   PallyPower's Righteous Fury button is enabled and you know it). When one of them is not
   on you, it's cast first, before any blessing. It's its own step on the wheel and its own
   page on the button and in the tooltip (`on` / time left / `missing`); a missing one makes
   the button red.
1. **Greater Blessings**: classes that have individual overrides go first. A Greater Blessing
   also replaces your blessing on the override members (one blessing per paladin per target),
   so these all go before the overrides.
2. **Overrides**: PallyPower's per-player blessing assignments (the ones its buff bar casts
   on right-click), cast as the normal single-target blessing.

## Clicks

| Click | Does |
|---|---|
| Left | Next missing blessing, or one whose time left PallyPower doesn't know |
| Shift | "Cast anyway": Greater Blessings even if some of the class is not here, out of range or out of line of sight |
| Right | Works on what the button shows. A group: that class's overrides first, then the normal (single-target) version of the group's blessing on one member who'd otherwise get the Greater Blessing and is missing it, one per click. An override / "Individual": overrides only. Members who have the blessing are never touched; out-of-range ones are skipped. |
| Shift + Right | "Cast anyway" for right-click: same scope, but also refreshes blessings that are still on, starting with the one that runs out first (missing, then unknown time, then lowest time). |
| Wheel | Pick a step: each Greater Blessing group, then "Individual" (all overrides), wrapping around. Clicks then work on that step only (Shift and right-click still apply). The list, icons and tooltip follow the pick, and the notice shows its position (`2/4`). Back to "next" when the mouse leaves the button. |

Low time left isn't refreshed early: it only shows on the button (yellow + time).
`/ppnext` toggles the button; `/ppnext show | hide | tooltips | list | collapse | below | opacity 10-100`.

The button sits on top of PallyPower's buff bar and moves, scales and hides with it. It uses
PallyPower's own buff-button template (same backdrop colours) and shows the same "page" as
the tooltip for the group / player it's on, but only your assigned blessing per player:

```
[class][blessing] Greater Might - Paladin   6:22
Kael  6:22                                    OK
```

or, for the overrides:

```
Individual
Velandra         [Light]  6:03                OK
```

- **Colour**: red = something is missing, yellow = unknown time left, < 5 min left, or
  someone dead is without it, green = all good. Members out of sight count as fine, like on
  PallyPower's buttons.
- **Header**: the group (class and blessing icons) or "Individual", the wheel position
  when you've picked one (`2/4`), and the time left on the right (`missing` / `no timer`).
- **Rows**, in fixed columns: name, the blessing icon (overrides), time left on the assigned blessing (`missing` in muted red, or
  `no timer`), and on the right, under a grey **Can cast?** label, whether a cast reaches
  them: `OK`, `OOR`, `LOS`, `Dead`, `Not Here`, `Tank`. Class-coloured names still need it, grey ones have it.
- The button is on the next click's group / player (or the blocked one). When everything is
  up, it's on whatever runs out first; right-click and the wheel start from there. The
  choice follows a once-a-second preview (holding Shift updates it).

## Options

PallyPower's own options window (the one with Global Transparency) gets a **PallyPower Next**
section at the bottom; the window grows to make room. It has checkboxes for the button, the
collapsed buff bar, the "below" layout, the target list and the tooltip, plus an
**Out-of-combat opacity** slider (10% - 100% in 5% steps). The `/ppnext` commands are
shortcuts for the same settings; `/ppnext options` opens the window.

## Target list

A list inside the button, under its icons, shows who the next click is about: the Greater Blessing group
it would cast (or the one that's blocking, e.g. when it shows `OOR`), or the single override
target. Each name gets a status:

| Status | Meaning |
|---|---|
| OK | In range and in line of sight |
| OOR | Out of range (40 yd Greater, 30 yd normal) |
| LOS | In range, but out of line of sight (UnitXP) |
| Dead | Dead or ghost; never cast on and never blocking |
| Not Here | Not visible (too far away, other zone) |

Names in class colour still need the blessing; grey names already have it. Members with an
override aren't listed for a Greater Blessing. `/ppnext list` toggles the list.

Each row shows the player, their time left on the assigned blessing (same wording as the
tooltip: a time, `no timer` or `missing`) and their status. The button has a constant width
(170 px; long names are cut off) and grows taller to hold
the list: up when it sits on top of the bar, down in the "below" layout. It's anchored by its
left edge, lined up with PallyPower's buttons. Clicks and the mouse wheel work anywhere on it.

## Collapsed buff bar

PallyPower's own buff-bar buttons (Righteous Fury, aura, seal, class buttons, resize grip) stay
hidden until you mouse over the **Pally Buffs** title. They fold away again 0.3 s after the
mouse leaves the bar. This button, its target list and the title always stay visible.
`/ppnext collapse` toggles it (on by default). While collapsed, the empty bar area doesn't
block clicks.

## Below layout

`/ppnext below` puts this button **under** the "Pally Buffs" title instead of on top of the
bar, moves the title under PallyPower's buttons, and anchors the bar by its bottom-left
corner, so the bar grows **upwards**: opening the collapsed bar (or PallyPower adding class
buttons) never moves the title or this button. Switching keeps the title where it was on
screen. The position is saved per character and re-saved after you drag or rescale the bar.

## Out-of-combat opacity

`/ppnext opacity 10-100` fades the whole buff bar (PallyPower's buttons, the title, this
button and its list) to that opacity out of combat. In combat, and while the mouse is over
any of it, it's fully opaque. 100 (the default) turns it off.

## Tooltip

Shows up immediately on mouseover and lists everyone, in the order the button works through
them: each Greater Blessing group (time left on the right, members with their status) and
then the individual overrides (`Name: Blessing (time left)`). Time left is the timer when
known, `no timer` when someone has the blessing but there's no timer, and `missing` when nobody
has it. Each player also shows the time left on the assigned blessing (just the time, since
the line already names it: `4:32`, `no timer` or `missing`), then any other paladin
blessings they have with their time, whoever cast them: `Kael  4:32   [Kings] 9:10`.
In a Greater Blessing group, a player's time is left blank when it matches the group's time
in the header (within 3 s), in the tooltip and on the button.
Rows are in aligned columns: name, blessing icon (overrides), time left, other blessings
(icon + time), and the status on the right. Group headers get the class and blessing icons.
`>` marks what the next click does. Same colours and statuses as the target list, plus `Tank` for PallyPower-marked tanks
that never get Salvation. `/ppnext tooltips` turns it off.

## Range and line of sight

- **On click** the game itself checks spell range. Line of sight is checked with UnitXP_SP3
  whenever the DLL is loaded, even if PallyPower's own UnitXP option is off.
- **Preview** (button colour/icons) uses UnitXP's distance (30 yd for blessings, 40 yd for
  Greater Blessings) plus line of sight. Without UnitXP it falls back to the ~28 yd follow
  distance and no line-of-sight check.

## Rules

- A Greater Blessing is cast when at least one class member **without** an override needs it.
- For a Greater Blessing only members without an override count. If one of them is **not
  here** (not visible), **out of range** or **out of line of sight**, it's skipped unless
  Shift. A skipped Greater Blessing leaves only overrides. Dead and offline members are
  ignored.
- Time left is per player. With **ClassicAPI** loaded it's read from each player's actual
  buff, whoever cast it; `/ppnext auras` lists what it reports for your target. Where that
  isn't known, it falls back to PallyPower's own timers and this addon's. With no timer
  (cast by hand, after a reload...) the time left is unknown and the blessing is recast on a
  normal click, so its timer is known from then on.
- Pets: Greater Blessings on Warriors also land on pets. With the same assignment they're
  part of the Warrior group; with a different one they get the normal blessing individually.
- If you don't know the Greater version (or PallyPower is in regular-blessings mode), class
  members get the normal blessing one by one.
- Salvation is never cast on PallyPower-marked tanks (PallyPower's own rule).
- A blessing's timer starts when it appears on the player (cast by this button or any
  other way), not when the cast is sent, so a cast that didn't land leaves no timer. A
  timer is dropped when the blessing goes, and restarted when it's cast again. A missing
  blessing always shows `missing`, never a time.
- Blessings cast some other way (spellbook, macro, keybind) are noticed when they appear:
  someone who was in sight and missing their blessing has it a second later, so a timer
  starts. An override gets its individual timer; two or more members of a group at once
  start the group's Greater Blessing timer; a single group member gets a normal-blessing
  timer (the shorter one, so it errs towards refreshing early). Only missing timers are
  filled in, and like PallyPower's own scan it can't tell which paladin cast it.

## Install

- **With a launcher or git:** add `https://github.com/daev-code/PallyPowerNext` as an addon, or
  `git clone` it into `Interface\AddOns`. Keep the `.git` folder: launchers that install
  from git use it to fetch updates.
- **By hand:** copy this folder to `Interface\AddOns\PallyPowerNext`. Updates are then manual too.
