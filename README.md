# PallyPower Next Blessing

One button for [PallyPowerTW](https://github.com/ShikawaLePaladin/PallyPowerTW) or
[Aegis: RallyPower](https://github.com/Torchlite-bit/Aegis_RallyPower) that casts the next
blessing you still owe from your PallyPower assignments, one per click. For WoW 1.12. Use
one of the two, not both: RallyPower carries its own copy of PallyPowerTW.
"PallyPower" below means that shared part (assignments, buff bar, timers), whichever addon
you use.

It works through your list in this order: your aura and Righteous Fury, then Greater
Blessings, then individual overrides (PallyPower's per-player assignments). A Greater
Blessing waits while someone in the class is out of range or out of sight. Hold Shift to cast
it anyway.

## Clicks

Clicks only ever cast the step the button shows.

| Click | Does |
|---|---|
| L-click | Casts the shown step |
| Shift L-click | Casts the shown Greater Blessing anyway: past anyone out of range or sight, and over blessings that are still up (refreshes them and upgrades normal ones) |
| R-click | Normal single-target blessing, one player per click: overrides first, then anyone in range who's missing it |
| Shift R-click | Like R-click, but also refreshes blessings that are still up, soonest to run out first |
| Wheel | Picks a step (Personal, each Greater Blessing group, Individual), shown as `2/4`, until the mouse leaves the button |

## The button

It sits on PallyPower's buff bar and moves, scales and hides with it.

```
Applied (6)  Missing (2)  OOR (3)
[class][blessing] G. Might - Paladin   6:22
> Kael  6:22                                  OK
  Brom  missing                               OOR
R-click: Might -> Brom
```

- **Top line:** totals for everyone you bless (Applied, Missing, OOR, LOS, Dead, Not Here,
  Tank, No config).
- **Header:** the step the next click is for and its time left.
- **List:** who the click affects, with your blessing's time left and whether a cast can
  reach them. `>` marks who the next click is cast on.
- **Click line:** when an L-click can't do anything, what an R-click would cast instead.
  Hold Shift to see what the Shift-clicks would cast.

Red means something is missing, yellow means a time is unknown or under 5 minutes, green
means all is well. The tooltip lists everyone in the order the button works through them.

## Optional addons

- **UnitXP_SP3**: range and line of sight in the preview. Without it, range uses the ~28 yd
  follow distance and everyone counts as in sight.
- **ClassicAPI**: real time left on every blessing, whoever cast it. Without it, the addon
  uses PallyPower's timers plus its own.

## Settings

In the "PallyPower Next" section at the bottom of PallyPower's options window. With
RallyPower, its Options button opens RallyPower's own window instead, and the section is at
the bottom of that window's Buttons tab (PallyPower's window is still there under
`/rpc legacy`). Hover a setting to see what it does.

| Setting | Default | What it does |
|---|---|---|
| Collapsed bar | On | Hides PallyPower's own buttons until you hover the bar's title ("Pally Buffs", or "Rally Buffs" with RallyPower) |
| Below layout | On | Puts this button under the title and makes the bar grow upwards |
| Out-of-combat opacity | 70% | Fades the bar out of combat. Fully visible in combat and on mouseover |
| Other blessing types in the tooltip | Off | Also lists each player's other blessings in the tooltip |

`/ppnext options` opens the window the Options button opens (on the Buttons tab with
RallyPower). `/ppnext show | hide | tooltips | others | list |
collapse | below | opacity 10-100` work as shortcuts.

## Install

Add `https://github.com/daev-code/PallyPowerNext` to your launcher, or `git clone` it into
`Interface\AddOns`. Leave the `.git` folder in place so the launcher can pull updates. You
can also copy the folder to `Interface\AddOns\PallyPowerNext` by hand, but then you have to
update it by hand too.

How it decides what to cast, in full detail, is in [CONTRIBUTING.md](CONTRIBUTING.md#how-it-works-in-detail).
