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

A Greater Blessing is cast when at least one class member without an override needs it. If
one of those members is out of range, out of sight or not here, it's skipped (only overrides
are left) unless you hold Shift. Dead and offline players are ignored. Blessings running low
aren't refreshed early; the button just turns yellow and shows the time.

## Clicks

| Click | Does |
|---|---|
| Left | Casts the next missing blessing, or one whose time left is unknown |
| Shift | Casts Greater Blessings even if some of the class is out of range, out of sight or not here |
| Right | Works on what the button shows, one cast per click. On a group: its overrides first, then the normal blessing on a member who'd get the Greater one and is missing it. On "Individual": overrides only. Never touches anyone who has the blessing; skips anyone out of range |
| Shift + Right | Same scope as right-click, but also refreshes blessings that are still up: missing first, then unknown time, then lowest time |
| Wheel | Picks a step (Personal, each Greater Blessing group, then "Individual"), shown as `2/4`. Clicks then only work on that step, with Shift and right-click still applying. Resets to "next" when the mouse leaves |

## The button

It sits on PallyPower's buff bar, uses its button style, and moves, scales and hides with it.
It shows the group or player the next click is for (or whatever is blocking it, or when all
is up, whatever runs out first), plus a list of who that click affects, with only your own
assigned blessing per player. Members with an override aren't listed under a Greater
Blessing.

```
[class][blessing] Greater Might - Paladin   6:22
Kael  6:22                                    OK
```

Each row shows the name, time left and a status saying whether a cast would reach them. Red
means something is missing, yellow means a time is unknown, under 5 minutes, or someone dead
is without it, and green means all good. Members out of sight count as fine, as on
PallyPower's own buttons. Class-coloured names still need the blessing; grey ones have it.
The button is 170 px wide and grows taller with the list; clicks and the wheel work anywhere
on it. It refreshes once a second, or immediately while you hold Shift.

The tooltip appears right away and lists everyone in the order the button works through
them: each Greater Blessing group, then the overrides, with any other paladin blessings each
player has (`Kael  4:32   [Kings] 9:10`). `>` marks what the next click does. On the button
and in the tooltip, a player's time is left blank when it matches the group's (within 3 s).

| Status | Meaning |
|---|---|
| OK | In range and in sight |
| OOR | Out of range (40 yd Greater, 30 yd normal) |
| LOS | In range but out of sight |
| Dead | Never cast on, never blocks |
| Not Here | Not visible (too far, other zone) |
| Tank | Marked as a tank in PallyPower, so never gets Salvation |

Times show as `4:32`, `no timer` (has the blessing, time unknown) or `missing`.

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
- **Below layout**: puts this button under the title and makes the bar grow upwards, so
  opening it never moves the title or the button. Switching keeps the title where it is on
  screen, and the position is saved per character.
- **Out-of-combat opacity** (10-100% in 5% steps, 100 = off): fades the whole bar out of
  combat; it's fully visible in combat and on mouseover.

All settings are in a **PallyPower Next** section at the bottom of PallyPower's options
window (the one with Global Transparency). `/ppnext options` opens it, and
`/ppnext show | hide | tooltips | list | collapse | below | opacity 10-100` are shortcuts.

## Install

Add `https://github.com/daev-code/PallyPowerNext` to your launcher, or `git clone` it into
`Interface\AddOns`. Leave the `.git` folder in place: launchers that install from git need
it to pull updates.

You can also copy the folder to `Interface\AddOns\PallyPowerNext` yourself, but then
you'll need to update it yourself too.
