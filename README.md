# PallyPower Next Blessing

One button for [PallyPowerTW](https://github.com/ShikawaLePaladin/PallyPowerTW) that casts
the next blessing you still owe, based on your PallyPower assignments. Each click casts one.
For WoW 1.12 and Turtle WoW.

## What it casts, in order

1. Personal: your aura and Righteous Fury, when either is missing from you. Righteous Fury only counts
   if PallyPower's RF button is on and you know the spell. A missing one turns the button red.
2. Greater Blessings. Classes with individual overrides go first, because a Greater Blessing
   also replaces your blessing on those members (each paladin gets one blessing per target).
3. Overrides: PallyPower's per-player assignments, cast as the normal single-target blessing.

A Greater Blessing goes out when at least one class member without an override is missing
it, or has it with an unknown time left. Members who only have the normal (10-minute)
version count as covered, and Shift L-click upgrades them. If anyone in the class without an
override is out of range, out of sight or not here, the Greater Blessing is skipped and only
the overrides are left, unless you hold Shift. Dead and offline players are ignored.
Blessings running low aren't refreshed early. The button turns yellow and shows the time
instead.

## Clicks

Clicks only ever work on the step the button is showing: the next one, or the one you picked
with the wheel. Nothing else gets cast.

| Click | Does |
|---|---|
| L-click | Casts the shown step: a missing blessing, or one whose time left is unknown |
| Shift L-click | On a Greater Blessing group, casts it anyway: past anyone out of range, out of sight or not here, and even when everyone already has it (Greater or normal), which refreshes it and upgrades the normal ones. On "Individual" it does the same as Shift R-click |
| R-click | One cast per click on the shown step. On a group, its overrides come first, then the normal blessing on a member who'd get the Greater one and is missing it. On "Individual", overrides only. It never touches anyone who has the blessing and skips anyone out of range |
| Shift R-click | Same scope as R-click, but also refreshes blessings that are still up: missing first, then unknown time, then whatever runs out soonest |
| Wheel | Picks a step (Personal, each Greater Blessing group, then "Individual"), shown as `2/4`. Clicks then work on that step until the mouse leaves the button |

## The button

It sits on PallyPower's buff bar, uses PallyPower's button style, and moves, scales and hides
with the bar. It shows the group or player the next click is for. If that's blocked, it shows
what's blocking it, and when everything is up, whatever runs out first. Below that is a list
of who the click affects, with only your own blessing for each player. Members with an
override aren't listed under a Greater Blessing. "Greater" is shortened to `G.` to save room,
on the button and in the tooltip, except in the tooltip's `Next L-click:` / `Shift L-click:`
line.

```
[class][blessing] G. Might - Paladin   6:22
Kael  6:22                                    OK
```

Each row has the name, time left, and whether a cast would reach them. The button is red
when something is missing, yellow when a time is unknown or under 5 minutes or someone dead
is without it, and green when all is well. Members out of sight count as fine, like on
PallyPower's own buttons. Class-coloured names still need the blessing; grey ones have it.

`>` marks the player the click is cast on. For a Greater Blessing that's the member it's
aimed at; for overrides it's the first one in reach, so you can see who gets skipped for
being out of range.

Sometimes an L-click can't do anything, say when a Greater Blessing is held back by someone
out of range. Then a line under the list says what an R-click would cast instead, like
`R-click: Might -> Brom`, and `>` moves to that player.

Hold Shift and you get two lines, one per Shift-click:

```
Shift L-click: G. Might -> Warrior (Kael)
Shift R-click: Might -> Brom
```

On "Individual" both clicks do the same thing, so there's just one line:
`Shift L/R-click: Kings -> Kael`. The tooltip shows the same lines, with `Next L-click:` when
Shift isn't held. A line that's too long for the button wraps onto a second line.

The top of the button and the top of the tooltip have a totals line. It counts everyone you
have a blessing for, and anyone you don't, in the same colours as the status column:

```
Applied (6)  Missing (2)  OOR (3)  Dead (1)  Not Here (1)  No config (1)
```

| Total | Meaning |
|---|---|
| Applied | Has your blessing. Reads "All applied" when nobody you can bless is missing it (Dead, Tank and No config can still be listed) |
| Missing | Missing it, and in reach |
| OOR / LOS / Not Here | Missing it, and out of range / out of sight / not visible |
| Dead | Dead |
| Tank | Marked as a tank, so never gets Salvation |
| No config | You have nothing assigned to them, or don't know that blessing |

Totals of 0 are left out. If the line doesn't fit, it wraps between categories, never in the
middle of one. A thin line separates it from the rest of the button.

The button is 180 px wide and grows taller with the list. Clicks and the wheel work anywhere
on it. It refreshes once a second, and straight away when you press or release Shift.

The tooltip shows up right away and lists everyone in the order the button works through
them: each Greater Blessing group, then the overrides. With the "Other blessing types"
setting on, it also lists each player's other blessings (`Kael  4:32   [Kings] 9:10`).
`->` on a section header marks the step the button is on, and `>` marks the player the next
click is cast on, same as on the button. A player's time is left blank when it's within 3 s
of the group's.

| Status | Meaning |
|---|---|
| OK | In range and in sight |
| OOR | Out of range (40 yd Greater, 30 yd normal) |
| LOS | In range but out of sight |
| Dead | Never cast on, never blocks |
| Not Here | Not visible (too far, other zone) |
| Tank | Marked as a tank in PallyPower, so never gets Salvation |

Times show as `4:32`, `no timer` (has the blessing, time unknown), `single` (only the
normal, 10-minute version, which PallyPower's own scan can't tell apart from the Greater one)
or `missing`.

## Range and line of sight

When you click, the game checks the range itself. Line of sight is checked with UnitXP_SP3
whenever it's loaded, even if PallyPower's own UnitXP option is off. The button's preview
uses UnitXP for distance and line of sight too. Without UnitXP it falls back to the ~28 yd
follow distance and assumes everyone is in sight.

## Timers

With ClassicAPI loaded, time left comes from each player's actual buff, whoever cast it
(`/ppnext auras` shows what it reports for your target). Without it, the addon uses
PallyPower's timers plus its own. A blessing with no known time gets recast on a normal
click, so from then on its time is known.

A timer starts when the blessing shows up on the player, not when the cast goes out, so a
missed cast leaves no timer. The timer is dropped when the blessing fades, and a missing
blessing always reads `missing`, never a time.

Blessings you cast some other way (spellbook, macro, keybind) get picked up when they appear.
An override gets its own timer. Two or more group members getting it at once starts the
Greater Blessing timer. A single member gets the shorter normal-blessing timer, so it errs
towards refreshing early. This only fills in timers that are missing, and like PallyPower it
can't tell which paladin cast a blessing.

Pets get the Warrior Greater Blessing when their assignment matches, and their own normal
one otherwise. If you don't know the Greater version, or PallyPower is set to regular
blessings, class members get the normal blessing one at a time.

## Settings

| Setting | Default | What it does |
|---|---|---|
| Collapsed bar | On | PallyPower's own buttons stay hidden until you hover the "Pally Buffs" title, and fold away 0.3 s after the mouse leaves. This button, its list and the title stay visible, and the empty bar doesn't block clicks |
| Below layout | On | Puts this button under the title and makes the bar grow upwards, so opening it never moves the title or the button. Switching keeps the title where it is on screen, and the position is saved per character |
| Out-of-combat opacity | 70% | Fades the whole bar out of combat (10-100% in 5% steps, 100 = off). It's fully visible in combat and on mouseover |
| Other blessing types in the tooltip | Off | After your blessing, each tooltip row lists the player's other blessing types (Kings and Wisdom when you give them Might, say), with time left if ClassicAPI is loaded and `no timer` if not. Your own blessing type always has its own column, whoever cast it, Greater or normal |

You'll find them in a "PallyPower Next" section at the bottom of PallyPower's options window
(the one with Global Transparency). Hover a setting for half a second to see what it does.
The Tooltips setting turns those explainers off along with the button's tooltip.

`/ppnext options` opens the window, and `/ppnext show | hide | tooltips | others | list |
collapse | below | opacity 10-100` work as shortcuts.

## Install

Add `https://github.com/daev-code/PallyPowerNext` to your launcher, or `git clone` it into
`Interface\AddOns`. Leave the `.git` folder in place, since launchers that install from git
need it to pull updates.

You can also copy the folder to `Interface\AddOns\PallyPowerNext` by hand, but then you'll
have to update it by hand too.
