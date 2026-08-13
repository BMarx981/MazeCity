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

**Slate 2: TimerGui.**
The flagship surface. Floor/timer holder gets the Display font on the floor number and
the par bar becomes the rune seam it was always shaped like. Score, coin and powerup
chips convert to `chip`. The celebration banner moves to the shared `banner` with
Display-font titles. Confetti retints to stone-chips-and-sparks (teal, lantern, pale
stone) instead of party colours. The compass keeps its config-driven colours but its
moon base picks up the etch stroke so it sits in the same family. The powerup chip and
shop banner keep tinting by the semantic config colours.

**Slate 3: AbilityGui.**
Chip converts to `chip`, the selector boxes to `Stone` with the existing selection
UIStroke recoloured to Rune (it is already the one stroke in the game, it was ahead of
its time). Charge bar states map to Rune / Lantern (grace) / Ember (empty), replacing
the `Config.Abilities` colour reads with tokens where the colour is chrome and keeping
them where it is semantic (per-ability accent from `Upgrades[*].Color` stays).

**Slate 4: PetGui and BestiaryGui.**
The big modal: panel to `panel` with Display title, tabs to Stone/Rune active states,
all seven row constructors restyled through the shared helpers, rarity swatches and
portrait chrome untouched (rarity colour is semantic). The hatch reveal keeps its rays
but they tint by rarity over an `Ink` wash, and the reveal title takes the Display font,
which is the single place the carved lettering gets to be huge. BestiaryGui inherits
everything by using the same cell helper.

**Slate 5: the world's plates.**
The five BillboardGui sites in `MazeGenerator` (plaza name sign, EGG ROOST, UPGRADE
SHOP, pedestal boards, roof SurfaceGui) share one plate style today by copy-paste;
give them one `plateGui` helper inside the generator using the same token values
(inlined as generator constants, since shared modules are fine to require from the
server but the generator should not depend on a UI module; a comment names UiTheme as
the source of truth). Determinism ritual applies.

**Slate 6, open: prompts and wordmark.**
Two things to decide after playing Slates 1 to 5, not before. (a) Stock ProximityPrompts
will now be the only unthemed UI in the game; theming them means
`ProximityPromptService.PromptShown` with `Style = Custom` and a client renderer, which
is a real component, worth it only if the clash grates in play. (b) A "The Kept" wordmark
treatment (Display font, etch stroke, rune underline) on the pet panel title and the
tower topped-out banner, cheap, but taste-check it in game first.

## Open decisions

1. **How far down does Grenze Gotisch go?** Plan says hero text only. If it reads well
   at 18 px it could take chip captions too; if it reads badly at 38 px, fall back to
   GothamBlack with a Rune underline and the theme still works.
2. **Does green survive anywhere?** Plan says no, Rune absorbs it. If playtest finds
   equip/success needs to differ from progress, add one `Moss` token then, not now.
3. **Glow intensity.** UIStroke transparency around 0.5 is the starting point; if the
   HUD reads as neon rather than embers, raise it. One token, one knob.

## What done looks like per Slate

`selene src/` clean; the converted file greps clean of `Color3.fromRGB` except semantic
config passthrough; a play test of that surface's states (for TimerGui that is a floor
clear, a death, a powerup, and a shop purchase; for PetGui a hatch reveal and a denied
buy); and for Slate 5 the same-seed double build. No new colour literals outside
UiTheme, MazeConfig, or MazeGenerator.CFG.
