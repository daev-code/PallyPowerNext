# Contributing

Issues and pull requests are welcome. All changes go in this addon; the addon it extends is
never modified.

## Commit messages

This repo uses [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <short summary>
```

The usual types are `feat` (new behaviour), `fix` (bug fix), `docs` (README and other docs),
`refactor` (code changes that don't change behaviour) and `chore` (repo setup, tooling).

Pull requests are squash-merged and the PR title becomes the commit message, so please give
the PR a title in the same format, for example `fix: keep the window position after a reload`.

## Testing

There are no automated tests. Try your change in game (`/reload`, or a full relog if you
changed saved settings or the `.toc`) and say in the PR what you tested.

## How it works in detail

The README has the overview. These are the full rules behind it, for anyone changing the
behaviour.

### Cast order

1. Personal: your aura and Righteous Fury, when either is missing from you. Righteous Fury
   only counts if PallyPower's RF button is on and you know the spell. A missing one turns
   the button red.
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

Pets get the Warrior Greater Blessing when their assignment matches, and their own normal
one otherwise. If you don't know the Greater version, or PallyPower is set to regular
blessings, class members get the normal blessing one at a time.

### Clicks

Clicks only ever work on the step the button is showing: the next one, or the one picked
with the wheel. Nothing else gets cast.

- L-click casts a missing blessing, or one whose time left is unknown.
- Shift L-click on a Greater Blessing group casts it even when everyone already has it
  (Greater or normal). On "Individual" it does the same as Shift R-click.
- R-click, on a group: its overrides first, then the normal blessing on a member who'd get
  the Greater one and is missing it. On "Individual": overrides only. It never touches
  anyone who has the blessing and skips anyone out of range.
- Shift R-click: same scope as R-click, then missing first, then unknown time, then whatever
  runs out soonest.

### The button

It uses PallyPower's button style. It shows the group or player the next click is for. If
that's blocked, it shows what's blocking it, and when everything is up, whatever runs out
first. The list only shows your own blessing for each player, and members with an override
aren't listed under a Greater Blessing. "Greater" is shortened to `G.` on the button and in
the tooltip, except in the tooltip's `Next L-click:` / `Shift L-click:` line.

Members out of sight count as fine for the colour, like on PallyPower's own buttons. Yellow
also covers someone dead who is without the blessing. Class-coloured names still need the
blessing; grey ones have it.

`>` marks the player the click is cast on. For a Greater Blessing that's the member it's
aimed at; for overrides it's the first one in reach, so you can see who gets skipped for
being out of range. When an L-click can't do anything, the `R-click:` line appears and `>`
moves to that player.

Holding Shift shows two lines, one per Shift-click (`Shift L-click: G. Might -> Warrior
(Kael)`, `Shift R-click: Might -> Brom`). On "Individual" both clicks do the same thing, so
there's one line: `Shift L/R-click: Kings -> Kael`. The tooltip shows the same lines, with
`Next L-click:` when Shift isn't held. A line that's too long wraps onto a second line.

| Total | Meaning |
|---|---|
| Applied | Has your blessing. Reads "All applied" when nobody you can bless is missing it (Dead, Tank and No config can still be listed) |
| Missing | Missing it, and in reach |
| OOR / LOS / Not Here | Missing it, and out of range / out of sight / not visible |
| Dead | Dead |
| Tank | Marked as a tank, so never gets Salvation |
| No config | You have nothing assigned to them, or don't know that blessing |

Totals of 0 are left out. The totals line wraps between categories, never in the middle of
one, and a thin line separates it from the rest of the button.

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

The button is 180 px wide and grows taller with the list. Clicks and the wheel work anywhere
on it. It refreshes once a second, and straight away when Shift is pressed or released.

The tooltip shows up right away. `->` on a section header marks the step the button is on,
and `>` marks the player the next click is cast on. A player's time is left blank when it's
within 3 s of the group's. With "Other blessing types" on, each row also lists the player's
other blessing types (`Kael  4:32   [Kings] 9:10`), with time left if ClassicAPI is loaded
and `no timer` if not. Your own blessing type always has its own column, whoever cast it.

### Range and line of sight

When you click, the game checks the range itself. Line of sight is checked with UnitXP_SP3
whenever it's loaded, even if PallyPower's own UnitXP option is off. The preview uses UnitXP
for distance and line of sight too.

### Timers

With ClassicAPI loaded, time left comes from each player's actual buff (`/ppnext auras`
shows what it reports for your target). A blessing with no known time gets recast on a
normal click, so from then on its time is known.

A timer starts when the blessing shows up on the player, not when the cast goes out, so a
missed cast leaves no timer. The timer is dropped when the blessing fades, and a missing
blessing always reads `missing`, never a time.

Blessings cast some other way (spellbook, macro, keybind) get picked up when they appear.
An override gets its own timer. Two or more group members getting it at once starts the
Greater Blessing timer. A single member gets the shorter normal-blessing timer, so it errs
towards refreshing early. This only fills in timers that are missing, and like PallyPower it
can't tell which paladin cast a blessing.

### Settings

- Collapsed bar: PallyPower's buttons fold away 0.3 s after the mouse leaves the title. This
  button, its list and the title stay visible, and the empty bar doesn't block clicks.
- Below layout: opening the bar never moves the title or the button. Switching keeps the
  title where it is on screen, and the position is saved per character.
- Out-of-combat opacity: 10-100% in 5% steps, 100 = off.
- Setting explainers show after hovering for half a second. The Tooltips setting turns them
  off along with the button's tooltip.
