# PallyPower Next Blessing

One button for [PallyPowerTW](https://github.com/ShikawaLePaladin/PallyPowerTW) that casts
the next blessing you still owe, based on your PallyPower assignments. Each click casts one.
For WoW 1.12 and Turtle WoW.

## What it casts, in order

1. **Personal**: your assigned aura and Righteous Fury (if PallyPower's RF button is on and
   you know the spell), whenever either is missing from you. A missing one turns the button
   red.
2. **Greater Blessings**: classes with individual overrides go first, because a Greater
   Blessing also replaces your blessing on those members (one blessing per paladin per
   target).
3. **Overrides**: PallyPower's per-player assignments, cast as the normal single-target
   blessing.

A Greater Blessing is cast when at least one class member without an override is missing
it or has it with an unknown time left. Members who only have the normal (10-minute) version
count as covered; Shift + left-click upgrades them. If any class member without an override
is out of range, out of sight or not here, the Greater Blessing is skipped (only overrides
are left) unless you hold Shift. Dead and offline players are ignored. Blessings running low
aren't refreshed early; the button just turns yellow and shows the time.

## Clicks

Every click works on what the button shows: the next step, or the one picked with the
wheel. It never casts on a group or player the button isn't showing.

| Click | Does |
|---|---|
| Left | Casts what the button shows: a missing blessing, or one whose time left is unknown |
| Shift | On a Greater Blessing group: casts it anyway, even if some of the class is out of range, out of sight or not here, or everyone already has the blessing, Greater or normal version (refreshes it, and upgrades the normal ones) |
| Right | Works on what the button shows, one cast per click. On a group: its overrides first, then the normal blessing on a member who'd get the Greater one and is missing it. On "Individual": overrides only. Never touches anyone who has the blessing; skips anyone out of range |
| Shift + Right | Same scope as right-click, but also refreshes blessings that are still up: missing first, then unknown time, then lowest time |
| Wheel | Picks a step (Personal, each Greater Blessing group, then "Individual"), shown as `2/4`; clicks then work on that step. Resets to "next" when the mouse leaves |

## The button

It sits on PallyPower's buff bar, uses its button style, and moves, scales and hides with it.
It shows the group or player the next click is for (or whatever is blocking it, or when all
is up, whatever runs out first), plus a list of who that click affects, with only your own
assigned blessing per player. Members with an override aren't listed under a Greater
Blessing. To save room, the button and the tooltip write "Greater" as `G.`, except in the tooltip's
`Next click:` / `Shift-click:` line.

```
[class][blessing] G. Might - Paladin   6:22
Kael  6:22                                    OK
```

Each row shows the name, time left and a status saying whether a cast would reach them. Red
means something is missing, yellow means a time is unknown, under 5 minutes, or someone dead
is without it, and green means all good. Members out of sight count as fine, as on
PallyPower's own buttons. Class-coloured names still need the blessing; grey ones have it.

`>` marks the player the click is cast on: for a Greater Blessing, the member it's targeted
at; for overrides, the first one in reach (out-of-range players earlier in the list are
skipped). When a left-click can't do anything on what the button shows (say a Greater
Blessing is blocked by someone out of range), a line under the list says what a right-click
would cast instead, e.g. `Right-click: Might -> Brom`, and `>` marks that player. While you
hold Shift, two lines show what each Shift-click would do on what the button shows, e.g.
`Shift-click: G. Might -> Warrior (Kael)` and `Shift-right: Might -> Brom`. The tooltip
shows the same lines (`Next click:` without Shift).

A totals line is always shown at the top of the button, above a thin line, and at the top
of the tooltip. It counts everyone you have a blessing for, plus
anyone you don't, using the same colours as the status column:

```
Applied (6)  Missing (2)  OOR (3)  Dead (1)  Not Here (1)  No config (1)
```

| Total | Meaning |
|---|---|
| Applied | Has your blessing. Shown as **All applied** when nobody you can bless is missing it (Dead, Tank and No config may still be listed) |
| Missing | Missing it, and in reach |
| OOR / LOS / Not Here | Missing it, and out of range / out of sight / not visible |
| Dead | Dead |
| Tank | Marked as a tank, so never gets Salvation |
| No config | You have nothing assigned to them (or don't know that blessing) |

A total of 0 isn't shown. When the line doesn't fit, it wraps between categories, never
inside one.

The button is 180 px wide and grows taller with the list; clicks and the wheel work anywhere
on it. It refreshes once a second, and right away when you press or release Shift.

The tooltip appears right away and lists everyone in the order the button works through
them: each Greater Blessing group, then the overrides. With the **other blessing types**
setting on, each player's other blessings are listed too (`Kael  4:32   [Kings] 9:10`).
`->` on a section header marks the step the button is on (the next one, or the one picked
with the wheel), and `>` marks the player the next click is cast on, as on the button. On
the button and in the tooltip, a player's time is left blank when it matches the group's
(within 3 s).

| Status | Meaning |
|---|---|
| OK | In range and in sight |
| OOR | Out of range (40 yd Greater, 30 yd normal) |
| LOS | In range but out of sight |
| Dead | Never cast on, never blocks |
| Not Here | Not visible (too far, other zone) |
| Tank | Marked as a tank in PallyPower, so never gets Salvation |

Times show as `4:32`, `no timer` (has the blessing, time unknown), `single` (only the
normal, 10-minute version; PallyPower's own scan can't tell it from the Greater one) or
`missing`.

## Range and line of sight

When you click, the game checks range itself, and line of sight is checked with UnitXP_SP3
whenever it's loaded, even if PallyPower's own UnitXP option is off. The button's preview uses
UnitXP's distance and line of sight; without UnitXP it falls back to the ~28 yd follow
distance and assumes everyone is in sight.

## Timers

With **ClassicAPI** loaded, time left comes from each player's actual buff, whoever cast it
(`/ppnext auras` shows what it reports for your target). Otherwise the addon uses
PallyPower's timers and its own. A blessing with no known time is recast on a normal click,
so its time is known from then on.

A timer starts when the blessing shows up on the player, not when the cast is sent, so a
missed cast leaves no timer. It's dropped when the blessing fades, and a missing blessing
always shows `missing`, never a time. Blessings you cast another way (spellbook, macro,
keybind) are picked up when they appear: an override gets its own timer, two or more group
members at once start the Greater Blessing timer, and a single member gets the shorter
normal-blessing timer, so it errs towards refreshing early. Only missing timers are filled
in this way, and like PallyPower it can't tell which paladin cast a blessing.

Pets get the Warrior Greater Blessing when their assignment matches, otherwise their own
normal one. If you don't know the Greater version, or PallyPower is set to regular
blessings, class members get the normal blessing one by one.

## Layout and options

- **Collapsed bar** (on by default): PallyPower's own buttons stay hidden until you hover
  the "Pally Buffs" title, and fold away 0.3 s after the mouse leaves. This button, its list
  and the title stay visible, and the empty bar doesn't block clicks.
- **Below layout** (on by default): puts this button under the title and makes the bar grow
  upwards, so opening it never moves the title or the button. Switching keeps the title where
  it is on screen, and the position is saved per character.
- **Out-of-combat opacity** (10-100% in 5% steps, 100 = off; 70% by default): fades the whole
  bar out of combat; it's fully visible in combat and on mouseover.
- **Other blessing types in the tooltip** (off by default): after your blessing, each
  tooltip row lists the player's other blessing types (say Kings and Wisdom when you give them
  Might) with their time left (only known with ClassicAPI, otherwise `no timer`). Your own
  blessing type is always shown in its own column, whoever cast it, Greater or normal.

All settings are in a **PallyPower Next** section at the bottom of PallyPower's options
window (the one with Global Transparency). Hovering a setting explains it after half a
second; the **Tooltips** setting turns these explainers off together with the button's
tooltip. `/ppnext options` opens it, and
`/ppnext show | hide | tooltips | others | list | collapse | below | opacity 10-100` are
shortcuts.

## Install

Add `https://github.com/daev-code/PallyPowerNext` to your launcher, or `git clone` it into
`Interface\AddOns`. Leave the `.git` folder in place: launchers that install from git need
it to pull updates.

You can also copy the folder to `Interface\AddOns\PallyPowerNext` yourself, but then
you'll need to update it yourself too.
