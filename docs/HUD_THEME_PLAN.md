# HUD Theme Plan: The Kept

Re-theme every screen surface and world plate to match the key art: a night city of dark
stone, teal runes glowing in the seams, and one warm lantern against all of it. The work
is organised in Slates, one slab of UI at a time, and Slate 1 is the only one that
creates anything new. Everything after it is a conversion.

## What the image says, translated to UI

Three ideas carry the whole look:

1. **Stone, not plastic.** Panels are dark blue-gray slabs, edged rather than floating.
   A subtle vertical gradient (lit from above, like moonlight on masonry) and a faint
   stroke replace today's flat translucent rectangles.
2. **Runes glow teal.** The etched teal lines in the maze walls become the HUD's single
   "alive" colour: progress fills, selection borders, the seam line along a chip's
   bottom edge. Anything currently green (par bar, equip, sprint-ready) folds into it.
3. **The lantern is the reward.** Warm amber-gold stays exactly what it already is,
   coins, streaks, banner subtitles, and also absorbs the warning states (grace, winded).
   Red remains only for danger: death, empty, spent.

That collapses today's ad-hoc colours into a three-accent system over a stone base:
**Rune** (positive, progress, selection), **Lantern** (economy, reward, warning),
**Ember** (danger). Fewer colours than now, each meaning one thing.

## The theme layer: `src/shared/UiTheme.lua`

A new ModuleScript, required by every client GUI file. It is the only place chrome is
defined, the same way `WalkSpeedResolver` is the only writer of WalkSpeed. It owns:

**Tokens** (names indicative, tune in place):

| Token | Value | Replaces |
|---|---|---|
| `Ink` | `rgb(8, 11, 20)` | banner/reveal backgrounds `rgb(12,12,16)` |
| `Slab` | `rgb(17, 22, 34)` | the universal panel `rgb(16,16,20)` |
| `Stone` | `rgb(30, 38, 54)` | rows `rgb(28,29,36)` and both inactive-button grays |
| `Track` | `rgb(36, 46, 64)` | the bar track `rgb(50,52,62)` |
| `Etch` | `rgb(74, 86, 108)` | stroke/border colour (new; today borders do not exist) |
| `Rune` | `rgb(92, 230, 208)` | success green `rgb(90,200,140)`, active `rgb(255,240,150)`, sprint `rgb(120,240,170)` |
| `Lantern` | `rgb(255, 205, 105)` | gold `rgb(255,214,110)`, grace `rgb(255,190,90)` |
| `Ember` | `rgb(233, 88, 74)` | red `rgb(230,80,80)` |
| `Text` | `rgb(228, 233, 242)` | white |
| `Dim` | `rgb(146, 160, 182)` | `rgb(150,160,175)` |

Plus non-colour tokens: corner radii (chip 6, panel 10), stroke transparency, panel
transparency (keep today's 0.25 chip / 0.08 modal convention), and the two fonts below.

**Constructors**, which are the consolidation of every duplicated helper the survey
found: `panel` (slab + gradient + etch stroke + rune seam option), `chip`, `label`,
`button` (with the accent variants), `bar` (track + fill, returns both), `banner`
(one implementation with size/position options, ending the TimerGui/PetGui fork),
`tween`, and `playSound`. The four private `rounded` copies, four `playSound` copies,
two `label` copies, two `tween` copies and two `showBanner` near-duplicates all die here.

**Fonts.** Body text stays Gotham/GothamBold: it is doing legibility work at 11 to 14 px
and a blackletter face there would be unreadable. Hero text only, the floor number,
banner titles, panel titles, and the hatch reveal, moves to the carved look via
`Font.fromName("GrenzeGotisch", Enum.FontWeight.Bold)`, which is in the Roblox font
catalogue and ships with the client, no asset upload. `UiTheme.Display` and
`UiTheme.Body` are the only two font values; no file names a font itself.

## Rules (hold these through every Slate)

- **Chrome comes from UiTheme and nowhere else.** After a file is converted, it contains
  zero `Color3.fromRGB` literals for chrome. A new colour is a new token, argued for in
  this doc first.
- **Semantic colours stay in config and stay authoritative.** `Config.Pets.RarityColors`,
  `Config.Shop.Upgrades[*].Color`, `Config.Collectibles.PowerupKinds[*].color`, and
  `Config.Compass` are shared with world geometry (shop orbs, eggs, route trails) and
  the theme only frames them, never absorbs them. Retuning their *values* toward the
  palette (sprint green to Rune, compass gold to Lantern) is a config edit, made in
  MazeConfig, not a theme rule.
- **No image assets.** The look is built from UICorner, UIStroke, UIGradient and
  gradients on frames, same as the compass moon already does. The game stays fully
  playable from a cold `rojo build` with nothing uploaded, and nothing here can 404.
- **ScreenGui names are frozen.** `BuildingLights.client.lua` parents its button into
  `PlayerGui.FloorTimer` by name; every ScreenGui keeps its name so nothing outside the
  file being themed can notice the change.
- **Server plates are a generator change.** Slate 5 edits `MazeGenerator`, so it gets
  the full generator ritual: run twice on the same seed, identical output. Adding
  UICorner/UIStroke instances moves the descendant count, which is fine because the
  delta is countable per plate; note the new baseline in the determinism memory.

## Slates

**Slate 1: the theme module, proven on the smallest surface.**
Write `UiTheme.lua`, then convert SprintGui (195 lines, one chip, no catalogue reads)
as the pilot. Exit: the sprint chip is a stone slab with a rune seam, its three bar
states read Rune / Lantern / Ember, every other GUI is untouched, `selene src/` clean.

*Done, with four decisions recorded.* (1) The state mapping is ready = Rune,
running = Lantern, winded = Ember: this doc listed "winded" under Lantern's warnings,
but winded is the below-minimum state, which is "empty, spent", and that is Ember's
whole job; the burn of an active sprint is what Lantern takes. (2) The sprint meter
*is* the chip's rune seam, one line along the bottom edge doing both jobs, the same
move Slate 2 makes with the par bar, rather than a static seam with a second bar
above it. (3) `Config.Sprint.Color` turned out to have exactly one reader, the chip,
so it is chrome and Rune absorbed it; the config field is now unread and should be
deleted in a later MazeConfig pass (left alone for now because the Robux Registers
are in that file). (4) "Two font values" is two families: the Body family ships as
`Body`/`BodyBold`/`BodyBlack`, three weights of GothamSSm, because the old files used
all three and a weight option on every label call read worse.

**Slate 2: TimerGui.**
The flagship surface. Floor/timer holder gets the Display font on the floor number and
the par bar becomes the rune seam it was always shaped like. Score, coin and powerup
chips convert to `chip`. The celebration banner moves to the shared `banner` with
Display-font titles. Confetti retints to stone-chips-and-sparks (teal, lantern, pale
stone) instead of party colours. The compass keeps its config-driven colours but its
moon base picks up the etch stroke so it sits in the same family. The powerup chip and
shop banner keep tinting by the semantic config colours.

*Done, pending the play test of its four states, with four decisions recorded.*
(1) The celebration mapping is floor clear = Rune, topped out = Lantern, death =
Ember: a floor cleared is progress and the tower is the reward, which is the same
reading the sprint chip settled and the reverse of the old green/gold split only in
name. (2) "Pale stone" in the confetti is two tokens, `Text` chips and `Etch` dust,
beside the two accents: four colours keep the fall varied without reopening the
party-colour box, and every one of them is already in the theme. (3) The compass
arrow's label stays full white via `Color3.new(1, 1, 1)`, the file's one remaining
colour literal, because it is the multiplicative identity under the semantic tip
gradient and not chrome; retinting it `Text` would muddy the two config colours the
gradient exists to show. The moon's new etch stroke fades with the erased half, the
UIStroke being subject to the same transparency gradient that cuts the circle, which
is why the flat edge needs no second treatment. (4) The clock under the floor number
dropped from near-white to `Dim`: the hierarchy the old file drew with two grays now
comes from the Display face on the number, and a second bright line was competing
with it.

**Slate 3: AbilityGui.**
Chip converts to `chip`, the selector boxes to `Stone` with the existing selection
UIStroke recoloured to Rune (it is already the one stroke in the game, it was ahead of
its time). Charge bar states map to Rune / Lantern (grace) / Ember (empty), replacing
the `Config.Abilities` colour reads with tokens where the colour is chrome and keeping
them where it is semantic (per-ability accent from `Upgrades[*].Color` stays).

*Done, pending the play test of its states, with four decisions recorded.* (1) The
Rune of the three-state mapping is USING: the old active yellow is exactly the
literal the token table assigned to Rune, grace takes Lantern's warning, empty takes
Ember, and ready is deliberately none of them, staying the selected ability's own
accent so the bar names its ability the way the stall's orbs do. (2) The selection
stroke is Rune always, per the plan, and the selected box keeps its accent fill
underneath it with `Ink` digits: selection belongs to the theme, the accent to the
ability, and the two read together rather than competing. (3) `EmptyColor` and
`GraceColor` in `Config.Abilities` are now unread and join `Config.Sprint.Color` in
the deferred MazeConfig cleanup, left in place while the Robux Registers are active
in that file. (4) The charge bar stays mid-chip rather than becoming the seam: the
seam move belongs to a chip whose bar was already its bottom edge, and this chip's
bottom edge is the hint line that carries the key. This file now holds zero colour
literals of any kind, the compass identity white being TimerGui's alone.

**Slate 4: PetGui and BestiaryGui.**
The big modal: panel to `panel` with Display title, tabs to Stone/Rune active states,
all seven row constructors restyled through the shared helpers, rarity swatches and
portrait chrome untouched (rarity colour is semantic). The hatch reveal keeps its rays
but they tint by rarity over an `Ink` wash, and the reveal title takes the Display font,
which is the single place the carved lettering gets to be huge. BestiaryGui inherits
everything by using the same cell helper.

*Done, pending the play test (a hatch reveal and a denied buy), with five decisions
recorded.* (1) The token table's "both inactive-button grays fold into Stone" was
written before the survey noticed the buttons sit on Stone rows, where Stone on Stone
is invisible; they fold into `Slab` instead, one idle colour, so a row's verbs read
as carved into the stone rather than raised off it. Active verbs are Rune (equip,
wear, place), Lantern with Ink lettering (buy, claim), and Ember (sell); the two
Robux buttons went Rune with the rest of the affirmative verbs. (2) The open tab is
Rune with Ink lettering, the same selection the ability row's border makes, and the
tab painter now writes text colour beside background so the state cannot half-change.
(3) The incubating egg's row is `Track`, one step up the stone stair from the shelf
rows, replacing its bespoke gray; XP and hatch fills keep rarity and egg colours.
(4) The PETS toggle and BuildingLights' reset button are chips that happen to be
pressable, so they wear the full chip chrome (slab, gradient, etch stroke).
BuildingLights postdates this plan's survey and joined the Slate for its one chrome
surface; its six style colours are semantic fallbacks for the generator's
`CompletionLightColor` and stay. (5) PetGui's banner fork is dead: `UiTheme.banner`
took this file's size, position and z-order as options, and both `showBanner` copies
the survey counted are now gone from the repo.

**Slate 5: the world's plates.**
The five BillboardGui sites in `MazeGenerator` (plaza name sign, EGG ROOST, UPGRADE
SHOP, pedestal boards, roof SurfaceGui) share one plate style today by copy-paste;
give them one `plateGui` helper inside the generator using the same token values
(inlined as generator constants, since shared modules are fine to require from the
server but the generator should not depend on a UI module; a comment names UiTheme as
the source of truth). Determinism ritual applies.

*Done, pending the play test (a walk from a plaza to a shop counter and up to a roost),
with six decisions recorded.* (1) It is **two helpers, not one**: `plateGui` is a
billboard holding a stone slab with the full HUD chrome, and `carvedPlate` is lettering
cut into a part's own face with nothing behind it. The plan counted the roof SurfaceGui
among "the five BillboardGui sites" and it is not one of them; putting a slab behind
letters already painted on a lit neon plate would have hung a floating rectangle on a
sign the city itself made. (2) **The seam marks a door.** The plaza name, EGG ROOST and
UPGRADE SHOP carry it; the pedestal boards do not, because a pedestal is a row inside
the stall and the sign over the counter is what marks the way in. That is the HUD's own
rule outdoors: chips and panels seam, rows do not. (3) **Both storefront signs are
Lantern.** The roost was pale blue and the stall was gold, and they are the two counters
in this city that spend coins, so one colour with one meaning beats two colours telling
the player nothing. What tells them apart is what they stand on. (4) Open decision 1 is
answered for the world, not yet for the HUD: **Display goes on a plate that names a
place** (the tower in its plaza, the roof board, EGG ROOST, UPGRADE SHOP) and **Body on
a plate that states a number or a direction** (the pedestal boards, the signposts). The
face sets wider than the Gotham these boxes were measured for, so the roost and stall
plates took ten more pixels of width and the tower's name became TextScaled under a
22 px ceiling: clipping a tower's name is the one failure that plate has, and the
ceiling is what stops a short name ballooning to fill the slab. (5) The pedestal board's
single newline-joined string became **two lines**: the name keeps the upgrade's accent,
which is the orb's colour and semantic, and the cost ladder underneath goes Lantern like
every other coin number in the game. (6) The street's signposts postdate this plan's
survey and joined the Slate for their one plate, the way BuildingLights joined Slate 4.

The determinism ritual passed and is the sharpest form of it yet: **+246 instances per
section, uniform across all three, and not one dumped line carrying a position changed.**
Per building that is 8 chrome instances at the plaza plate, 6 each at the roost and the
stall sign and 6 at each of five pedestals, against the 9 bare TextLabels removed; the
two carved plates are unchanged in shape and so do not appear in the diff at all. Both
sides double-built byte-identical. The harness needed three fixes to run it, all stub
gaps rather than generator ones, and they are recorded in the determinism memory.

**Slate 6: prompts and wordmark.**
Two things to decide after playing Slates 1 to 5, not before. (a) Stock ProximityPrompts
will now be the only unthemed UI in the game; theming them means
`ProximityPromptService.PromptShown` with `Style = Custom` and a client renderer, which
is a real component, worth it only if the clash grates in play. (b) A "The Kept" wordmark
treatment (Display font, etch stroke, rune underline) on the pet panel title and the
tower topped-out banner, cheap, but taste-check it in game first.

*Done, pending the play test (a walk up to a stall pedestal with both prompts in range,
a roost prompt, and one topped-out tower), with six decisions recorded.* (1) **`Style =
Custom` is set on the client, never in the generator.** The server keeps shipping stock
prompts; `PromptGui.client.lua` switches the ones it finds and draws them itself. So
there is no generator change and no determinism ritual for what is only a look, and the
file can be deleted without a single shop closing. (2) **Prompts are found through the
tags their parts already carry** (`EggPedestal`, `ShopItem`) rather than by sweeping
workspace for a class, which is the line CLAUDE.md draws for everything else crossing
from generation to runtime, and is why lazy sections theme themselves with no extra
wiring. The rule that falls out is that a prompt on an untagged part keeps the stock
look, which is the right failure: it still reads and still opens what it opens. The
renderer draws only prompts it adopted itself, so a chip can never be laid over one the
engine is still drawing. (3) **The chip carries the seam, because a prompt is a door**:
the same mark Slate 5 hung over the two counters outdoors, now on the near side of the
same doors. The hold is the keycap filling with Rune rather than the seam growing, which
is where Slate 1 put a meter: the seam is up the whole time the chip is, and the fill
belongs on the one thing the player is actually pressing. (4) **Display names the thing,
Body states the verb**, which is Slate 5's plate rule brought indoors, a prompt being a
plate you can press. The verb is Rune on every prompt including the Robux one, so the
renderer holds no per-prompt special case; Slate 4 had already put the Robux buttons in
with the affirmative verbs. (5) The billboard is deliberately much larger than the chip
and the chip takes the prompt's `UIOffset` as its own position, a BillboardGui having no
pixel offset of its own: that is what keeps the stall's stacked pair stacked. Width comes
off the labels' measured `AbsoluteSize`, so "Eggs" and "Buy with Robux" are the same chip
and neither is padded out to the other. (6) The wordmark is an etch stroke on the glyphs
plus a rune rule **sized to the text and not to the label**, capped to the label so a long
tower name cannot run a rule off the side of a banner, with alignment read off the label
so no caller states it twice. It is permanent on the pet panel title, where it redraws
itself to whichever of the four tabs is open, and hero-only on the banner: `show`'s last
argument already meant the topped-out tower and nothing else, so it became the hero flag
rather than a sixth argument, and a hero subtitle drops eight pixels because the rule
under a 52 px title lands exactly where a 22 px subtitle otherwise starts.

The prompt's object line is 15 px Display, the smallest carved lettering in the game and
the sharpest read on open decision 1 below.

## Open decisions

1. **How far down does Grenze Gotisch go?** Plan says hero text only. If it reads well
   at 18 px it could take chip captions too; if it reads badly at 38 px, fall back to
   GothamBlack with a Rune underline and the theme still works. Slate 5 answered it for
   the world (a plate that names a place) and Slate 6 pushed the face to 15 px on the
   prompt chip's object line, which is the floor: if that one reads muddy in play, the
   prompt line goes Body and the rest of the answer stands.
2. **Does green survive anywhere?** Plan says no, Rune absorbs it. If playtest finds
   equip/success needs to differ from progress, add one `Moss` token then, not now.
3. **Glow intensity.** UIStroke transparency around 0.5 is the starting point; if the
   HUD reads as neon rather than embers, raise it. One token, one knob.

## The deferred MazeConfig cleanup

Done, the Robux Registers having cleared that file.
`Config.Sprint.Color` went with Slate 1's own decision; `Config.Abilities.EmptyColor` and
`GraceColor` are deleted, the three-state charge bar reading Rune / Lantern / Ember off
the theme since Slate 3. A sweep of every `*Color` field in `MazeConfig` found no others
unread: `Pets.RarityColors` looks unread to a grep and is not, being reached through
`Config.rarityColor`.

## What done looks like per Slate

`selene src/` clean; the converted file greps clean of `Color3.fromRGB` except semantic
config passthrough; a play test of that surface's states (for TimerGui that is a floor
clear, a death, a powerup, and a shop purchase; for PetGui a hatch reveal and a denied
buy); and for Slate 5 the same-seed double build. No new colour literals outside
UiTheme, MazeConfig, or MazeGenerator.CFG.
