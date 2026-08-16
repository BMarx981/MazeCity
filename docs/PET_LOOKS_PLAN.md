# Pet Looks Plan

Follows the working agreement in PETS_PLAN.md: one set per branch, server authoritative, nothing invented outside a plan. This plan covers how pets look; what pets do is PETS_PLAN.md and what they wear is PET_ACCESSORIES_PLAN.md.

## Goal

Every pet and every evolution stage a distinct procedural silhouette, built the way enemy rigs already are: a `look` recipe on the catalogue entry, one shared generator, zero Studio art. The same generator drawn into ViewportFrames gives the UI portraits, so the inventory rows and the hatch reveal show the pet instead of a rarity-coloured square.

PETS_PLAN records the gap this closes: "`ServerStorage/Pets/<model>` is empty, so every pet is a coloured placeholder." The bargain it names stays intact. An artist model dropped into `ServerStorage/Pets/<model>` still wins by name with no code change; the generator replaces the neon cube as the fallback, not the artist.

## Non-goals

- ~~**Motion.**~~ Set 4 landed it: `PetRigDriver` beside the generator, exactly the `ModelGenerator` / `EnemyRig` split this bullet predicted, driven from the client. Sets 1 to 3 built no motion and that was the right order; the rigs came out of Set 1 already jointed, so Set 4 was a driver module and not a rebuild.
- **Accessory rendering.** PET_ACCESSORIES_PLAN Set 2 owns putting gear on rigs. This plan only guarantees the generated rigs carry the four slot attachments that plan's rendering section wants, so its computed-from-bounding-box fallback is never needed on a generated rig.
- **New pets, new abilities, balance changes.** The catalogue gains looks, not rows.
- **Egg looks.** The incubating egg in `EggHint` and the egg shelf keep their coloured shapes.
- **Replacing rarity colour in the UI.** Swatches, XP bars and reveal text stay `Config.rarityColor`. The portrait is the pet; the chrome around it is still the rarity.

## Where it lives

| File | What |
|---|---|
| `src/shared/PetModelGenerator.lua` | New. The generator: `DEFAULT_LOOK`, `lookFor`, `build`, `rigOf`. Shared for the same reason `ModelGenerator` is: portraits build on the client from the same recipes, costing the server nothing. |
| `src/shared/PetCatalog.lua` | Each entry and each evolution stage gains a `look`; `placeholder` is deleted once nothing reads it. |
| `src/server/PetInventory.lua` | `Inventory.look(petConfig, stage)` replaces `Inventory.placeholder`, same stage-override resolution. |
| `src/server/PetService.server.lua` | `buildRig` falls back to `PetModelGenerator.build` instead of `makePlaceholder`; the Glow light and the ward ring read `look.primary`. |
| `src/client/PetGui.client.lua` | Portraits: a viewport in each pet row, the model in the hatch reveal. |
| `src/shared/PortraitGenerator.lua` | Set 3. Gains `of(model, opts)`, which frames a model somebody else built; `portrait(typeName, opts)` becomes the enemy convenience over it. Framing a rig is geometry and had nothing enemy-shaped in it. |
| `src/server/IncubatorService.server.lua` | The `hatched` payload gains `petId` and `stage` so the reveal can build the model it is announcing. |
| `src/shared/PetRigDriver.lua` | Set 4. New. The motion: `DEFAULT_MOTION` and `animate(rig, clock, tell)`, pure, writing `Motor6D.Transform` off what `rigOf` hands back. |
| `src/client/PetAnimator.client.lua` | Set 4. New. The loop over `workspace.LivePets`, the camera cull, and the ability state the driver refuses to know. |

No `Config` changes. The recipe vocabulary and its defaults live in `PetModelGenerator` the way `DEFAULT_LOOK` lives in `ModelGenerator`: they are structural, and editing one is editing how a pet is built, not turning a knob between playtests.

## Art direction: deliberate contrast

The enemies are one silhouette family: dark translucent hoods, lit eyes, hands with no arms, segments trailing into smoke. Pets are the opposite of that on every axis that reads at corridor distance:

| | Enemy | Pet |
|---|---|---|
| Body | translucent, tapering | opaque, rounded |
| Material | Neon, glowing | SmoothPlastic, lit by the world |
| Eyes | lit points on a dark head | dark pupils on a bright body, large |
| Edges | smoke, tendrils, horns | ears, wings, tails, antennae |
| Palette | one dark colour per type | warm primary, lighter secondary, one small neon accent |

The rule behind the table: **a pet must never be mistakable for a threat**, and the Ward Hound is why the rule is load-bearing rather than taste. It is the one pet whose job is being near enemies, and a silhouette that reads as a seventh enemy type next to six real ones is a player sprinting away from their own defence.

Neon appears only as small accents that mean something: the Firefly's lantern is its Glow, the Ward Hound's collar is its ward, the Coin Bat's coin is its magnet. The accent is the ability made visible, which is also what makes an evolution legible (a stronger ability is a bigger or brighter accent).

Followers still hover at `FollowHeight`, but the Hound and Moth now use small named gait cycles: the Hound alternates diagonal pairs and the Moth alternates insect tripods. These are pose cycles, not navigation; PetService still owns follower movement, while the steps keep legs from reading as inert decoration.

## The recipe

Same construction as the enemy recipes, restated because the details are the contract. `DEFAULT_LOOK` is the whole baseline; a pet's `look` merges over it shallowly; a stage's `look` merges over the pet's. Nested tables (wings, ears, tail, motes) replace whole rather than merging key by key, because a stage that overrides its wings means different wings, not the old wings with one field edited. A group absent or sized 0 is left off entirely.

Vocabulary, all optional except the first four:

- `scale`, `primary`, `secondary`, `accent`, `primaryMaterial`, `secondaryMaterial`, `accentMaterial`: the whole-rig multiplier, the three colour channels and their Roblox materials. `primary` is the body, `secondary` the soft parts (belly, wings, muzzle, beak), `accent` the ability group. Materials are broad species texture: Fabric for fur/fuzz/feathers, Pebble for the Firefly's shell, SmoothPlastic for membranes and hard beaks, Neon for ability tells.
- `body`: the torso ellipsoid (number for a sphere, Vector3 for an ellipsoid, same rule as enemy sizes).
- `belly`: a secondary-coloured ellipsoid sunk into the body, showing only underneath (the Hound).
- `head`, `headOffset`: a second ball, or 0 for the one-ball pets whose face sits on the body.
- `eyeCount`, `eyeSize`, `eyeColor`, `eyeSpread`, `eyeHeight`, `eyeDepth`, `eyeTilt`, `eyePitch`, `eyeYaw`, `eyeRim`, `pupilSize`, `pupilColor`, `catchlight`: the face. The default is still the old friendly white eye with a dark pupil, but pets can now push away from it: insect bead eyes, soft moth ovals, framed hound eyes, glossy bat eyes and sharp crow eyes.
- `ears`, `wings`, `antennae`: symmetric pairs, `{ size, spread, height, z, tilt, sweep, pitch, forward, color }`. Anchor, orient, then push out along the part's own axis, same order as the enemy pairs and for the same reason.
- `beak`, `muzzle`: a single part forward of the head (the Crow; the Hound).
- `tail`: one solid part with size and offset. Not the enemy's fading segment chain: a pet tail is a tail rather than a thing trailing into smoke.
- `crest`: a single upright accent on the head (the Crow's compass needle).
- `collar`, `halo`, `motes`: one ring builder, three uses, `{ count, radius, size, height, z, tilt, upright }`. Flat by default, which is a halo above the head or a dial at a needle's base; `upright` stands the ring in the XY plane, which is a collar around a neck. **The plane is the whole difference between an accent that reads and one that is buried**, and it cost a fix in Set 1: a flat ring wide enough to clear the Hound's chest at the sides puts its rear beads inside the ribs, where they read as parts coming loose. The same trap took the Wayfinder's compass ring back into the shoulders, which is why it ended up a dial above the skull instead.
- `charms`: a list of accent props the pet carries rather than wears, each `{ size, offset, color }`. The Firefly's lantern and the Coin Bat's coin. A list because a stage can add a second one, which is how Gilded reads: two coins is a thing you can count from across a room and 20% more coin is not.
- `details`: static animal-specific parts, each `{ name, size, offset, attach, attachTo, gait, mirrored, pitch, yaw, roll, color, colorKey, material }`. `attach` mounts a detail to the body, head or an individual wing; `attachTo` chains it to an earlier named detail on the same side, so paws follow legs, toes fan from paws, fangs follow the face and wing ribs flap with their membrane. `gait` gives a leg or paw a named step phase, letting a hound alternate diagonal pairs and an insect alternate tripods. This is deliberately not a new first-class group for every feature. It covers stripes, paws, fangs, wing spots, feet and feather marks while keeping the builder pure and the catalogue data-shaped.

`look.primary` is the stage's colour in the world, and the two runtime reads move to it: the Glow light colour ([PetService.server.lua:156](src/server/PetService.server.lua#L156)) and the ward ring colour ([PetService.server.lua:201](src/server/PetService.server.lua#L201)). One colour source per stage; `placeholder` is deleted, not left beside it to drift.

## The eleven looks

Five bases and six evolution stages. The standing rule: **an evolution adds or changes a group, never only scale and tint.** Enemies learned that lesson as "one rig in six colours is one rig"; here it is one pet in two sizes is one pet, and an evolution a player paid twenty-five levels for should read across a corridor.

- **Firefly**: small segmented amber beetle body, dark bead eyes with gold glints, stub wings, antennae, six tiny tucked legs, shell seam and neon lantern at the tail. *Radiant* (10): brighter lantern, gains a halo. *Solar* (25): flame palette, halo plus orbiting spark motes.
- **Lumen Moth**: pale insect body with separate fuzzy thorax and abdomen, large soft cyan oval eyes, oversized flat wings, feathery antennae, six tiny fuzzy legs, wing veins and wing eyespots. *Pale* (12): wings grow past body length, secondary goes near-white.
- **Ward Hound**: compact long hound body, warm framed eyes, muzzle, nose, cheeks, embedded shoulders and haunches, real leg columns with padded two-toed paws, drooped ears, short tail, neon collar. *Bulwark* (15): broader body, upright ears, the collar widens into a shoulder ring (the ward, worn).
- **Coin Bat**: tiny dark torso under broad wings, glossy dark eyes with catchlights, big ears, chest and belly masses, small hind legs ending in three hooked toes, membrane wing ribs, tiny fangs and a gold coin held under it. *Gilded* (15): gold secondary, second coin, wing edges go accent.
- **Compass Crow**: sleek dark slate bird body, sharp gold eyes, gold beak, small legs ending in three splayed toes and a rear claw, chest/back feather masses, fanned tail feathers, wing tips, needle crest. *Wayfinder* (15): crest becomes a spinning needle mote on a ring, lighter palette.

Exact numbers are Set 1's work, tuned by eye in a play test. The list above is the contract for what each stage must visibly add.

## Rig construction

Where the enemy rig is a Humanoid with unanchored skin, a pet follower is anchored and moved by `PivotTo`, and the rig has to be built for that:

- **No Humanoid, no HipHeight.** An invisible root Part is the PrimaryPart, sized to the body so `GetPivot` stays honest; skin parts hang off it on Motor6Ds. Sets 1 to 3 anchored every part in `sterilise` and the motors were inert geometry. Set 4 made them real: `sterilise` now anchors a part unless a joint holds it, so the root anchors and the skin does not, and the rig is one anchored assembly that `PivotTo` carries and the joints pose. Nothing is simulated either way.
- **The four slot attachments** (`HeadAttachment`, `NeckAttachment`, `BackAttachment`, `AuraAttachment`) are created on the root at build time, placed per silhouette. PET_ACCESSORIES_PLAN's rendering section prefers an authored attachment over its bounding-box fallback; generated rigs author theirs.
- **`build(petId, stage)` is pure**: no randomness, no yielding, never touches ServerStorage, assigns no collision group. Client-callable is the point.
- **No `ensureTemplates`.** Enemies template because hundreds of rigs clone per session; a follower is one build per equip at `MaxEquipped = 1`, a dozen-odd instances, cheaper than the folder.
- **`rigOf`** reads the joints back by name, and it and `build` are the only functions that know the names, same two-function rule as `ModelGenerator`. Set 4 started from that readback rather than from a scan, which is what it was for.

## Portraits

The generator being shared is the whole reason this set is small. The client requires `PetModelGenerator`, builds the same model the server built, and parents it to a ViewportFrame with its own camera.

- **Inventory rows**: a square viewport at the left edge of each pet row, the rarity swatch staying beside it. The projection already carries `petId` and `stage`, so there is nothing to add server-side.
- **Hatch reveal**: the model centred under the name, slowly turning, torn down with the reveal. The rays and the arpeggio stay; the payload gains `petId` and `stage`, which is the one server edit in the set. Set 3 turns the model rather than orbiting the camera, which is the same picture and is what `PortraitGenerator` already did for the bestiary; the teardown is guarded against a second hatch landing inside the first reveal, because a spinning viewport left on a hidden frame is a connection running for the session.
- **The caveat, recorded and accepted**: a portrait always draws the *generated* look. An artist model in `ServerStorage/Pets` is invisible to clients, so a pet whose follower is artist-made still shows its generated silhouette in the UI until a replicated template folder exists, which is a different bargain and out of scope. Same trade the bestiary portraits made.

## Sets

### Set 1: The generator and the recipes

**Done.** `PetModelGenerator.lua` with `DEFAULT_LOOK`, `lookFor`, `build`, `rigOf`; `look` on all five catalogue entries and six stages; `Inventory.look` beside the not-yet-deleted `Inventory.placeholder`; `PetLookPreview.server.lua`, the temporary `RunService:IsStudio()` branch CLAUDE.md names as the way to eyeball generated geometry, since replaced by `PreviewService.server.lua` under [PREVIEW_PLAN.md](PREVIEW_PLAN.md) Set 1.

Checked two ways, and the cheap one found the bug. `build` touches no service and yields nothing, so it runs outside Roblox: `tools/petlooks/check.sh` stubs Color3/Vector3/CFrame/Instance under the `luau` CLI already in the toolchain, builds all eleven looks, and reports each one's part count and bounding box. That caught three accents sitting inside the body they were meant to hang off, including the Ward Hound's collar, which is the accent that *is* its ability. The check is now in the harness (an accent's centre inside the body or head ellipsoid is a failure, and the run exits non-zero), so a future recipe cannot reintroduce it silently.

`tools/` sits outside the three `src/` folders Rojo maps, so like `docs/` it reaches nothing in the place file.

Worth keeping in mind for anything else in this repo that is pure geometry: `MazeGenerator` is the same shape of function and the same trick would run it.


It became `/petlook` and `/petlook clear` rather than a row that builds itself on first spawn (and is `/preview pets` and `/preview clear` now that PREVIEW_PLAN Set 1 has folded the file in), which is the correction the plan's own command surface was always going to make and which could not wait for it: eleven `AlwaysOnTop` billboards stack into one unreadable pile at the distance the row sits, and they did that to every playtest of anything else. A debug surface that cannot be not-looked-at is worse than no debug surface. The spin connection is held and dropped by `clear` for the same reason, a row now being buildable more than once per session.

### Set 2: The follower wears it

**Done.** `buildRig` falls back to `PetModelGenerator.build`; `makePlaceholder` deleted; the Glow light and ward ring read `look.primary` through `Inventory.look`; `Inventory.placeholder` deleted; `placeholder` deleted from all five catalogue entries and all six stages, and with it the `Placeholder` type in `Types.lua` (`AccessoryPlaceholder` is a different type and stays: gear never grew a recipe).

The artist path is untouched and still checked the same way: drop any Model into `ServerStorage/Pets/Firefly` in a play session and the Firefly is that model.

One thing the set surfaced and did not change: the bounding-box fallback in `slotCFrame` is now dead for every pet in the catalogue, because a generated rig authors all four slot attachments. It stays for an artist's model that authors none, which is the case it was always for.

Done looks like: equip each pet, watch it follow, slide, zipline and respawn; a Glow pet lights the maze in its stage colour; a ward trigger draws the ring in the Hound's colour.

### Set 3: Portraits

**Done.** A 58 pixel viewport in `petRow` beside the rarity swatch, the model in `showReveal`, `petId` and `stage` on the `hatched` payload. The projection already carried both fields, so the shelf costs the server nothing at all and the one server edit in the set is the four-line payload change.

The set was smaller than planned because the framing already existed. `PortraitGenerator` was written for the bestiary and every line of it except one was generator-agnostic, so it split into `of(model, opts)` and a two-line `portrait(typeName, opts)` over `ModelGenerator`, and the pets went through `of`. That is deliberately the opposite call to the one this plan makes about the *model* generators, and the two are consistent: a camera framed off a bounding box is the same job for any silhouette, where a shared `skinPart` would have coupled what the two families look like.

Three things worth knowing before touching it:

- **The rows do not spin, the reveal does.** A spin is a RenderStepped connection per portrait and a shelf holds twenty five of them, so the picture on a row is a picture. The reveal is the one a player is watching rather than reading.
- **Rows are rebuilt, not cached.** `refresh` returns early with the panel closed, so portraits are built only while the Pets tab is open and only when the projection changes, which is an equip, a wear or a tower. Cheap enough to leave alone; the place to look first if it ever is not is a cache keyed by `petId .. stage`, which is at most eleven models for a shelf of twenty five.
- **The text column went from 190 pixels to 132** and the name truncates, because the picture took the left edge and the button column at x=218 is where it always was.

Done looks like: the shelf shows eleven distinguishable pets at a glance with no server round-trip beyond the projection it already had; a hatch shows the hatched pet turning.

### Set 4: Motion

**Done.** `PetRigDriver.lua` beside the generator, `PetAnimator.client.lua` driving it, `sterilise` anchoring a part only when no joint holds it, a `motion` group on the recipes, and the offline harness extended to run a simulated minute of it over every rig.

Both edits this section named are the ones that landed, and the second one moved: **the driver writes `Motor6D.Transform`, never C0.** C0 is what `rigOf` reads its bases back from, so a driver writing C0 writes into its own measuring stick, and it has to remember to put every joint back. `Transform` composes on top of C0, is the channel the engine reserves for per-frame posing, and is local to whoever writes it. That last property is what makes the client decision safe rather than merely cheap. (`EnemyRig` writes C0 and should stay as it is: it runs on the server, its rigs carry Humanoids, and the pattern there has years of play behind it.)

**The loop runs on the client**, which settles the open decision below the way it was leaning and for a firmer reason than cost. A follower's position is authoritative, because everyone sees the same pet in the same maze; its pose is not, and a wing angle nobody can act on has no business being computed once and replicated to everybody. `PetAnimator` walks `workspace.LivePets`, culls to `Config.Pets.AnimateRange` off the camera, and pays one CFrame per joint per visible pet. The server pays nothing and does not know the driver exists.

What each thing does, and every one of them is the recipe made legible rather than decoration:

- **Wings** hinge at the inner edge, not at their centre, so they beat rather than see-saw. `flapRate` and `flapAngle` are the two numbers that separate the Firefly (14 and 0.26, a blur) from the Lumen Moth (2.4 and 0.78, a shape crossing in front of a light), and the Pale stage names only the rate, keeping the depth the pet already had.
- **Ears** flick on a pulse rather than a sine, the two sides half a cycle apart: a dog flicking both at once is a dog shaking its head. The Bulwark's ears go up in geometry and steady in motion, which is the same tell twice.
- **Tails** sway from the base, **antennae** wave from theirs, the crest leans on its own.
- **Gaits** lift and pitch each named leg/paw pair together. The Hound's front-left/back-right pair alternates with its other diagonal; the Moth's front-left/middle-right/rear-left tripod alternates with the opposite three legs.
- **Rings** turn *and* ripple outward, and the ripple is the part that reads: a turn is invisible on twelve identical collar beads and legible on four motes, so both are needed. The ripple is outward only, because a bead pulled inward lands in the ribs the recipe was sized to clear.
- **Blink** is the eye sinking back into the face for a tenth of a second, the pupil riding in on its own joint. This is the one change to `build`: eyes and pupils are on Motor6Ds now instead of WeldConstraints. A pet with no eyelids blinks by taking its eyes away, and the depth comes off the eye itself so it works on a Ward Hound and on a Firefly a third the size.
- **The two ability tells.** A Glow pet's lantern breathes out and back a lot further than a carried prop otherwise does, which gives the light a pulse without touching the `PointLight` (that is the server's, and it replicates once for everyone). The Ward Hound's collar rides a wide tight wave while the ward is up, falls almost flat on an empty charge, and swells back as it recharges.

  **Both tells are amplitudes and wave shapes, never rates, and that is a rule the driver states in its own header.** Everything here reads an absolute clock, so a phase written as `clock * rate` with a rate that changes while the pet stands there has an angular speed of `rate + clock * rateChange`: the first draft slowed the collar down as the ward drained, and an hour into a server that recharge would have spun the ring thousands of times a second. It never showed up in the harness because the harness starts its clock at zero. A stateless driver may vary how far a thing moves and how a wave wraps around a ring; it may not vary how fast its own clock runs. Anything that genuinely needs a changing rate needs accumulated phase, and that means state, and state means it is no longer this module.

**The ward tell is reconstructed, not replicated.** PetService already publishes `WardRadius` on the rig while a ward runs and clears it when it lapses; the recharge that follows is a fixed length on the pet's own catalogue row, which every client has. So the moment the attribute goes is enough to draw the collar filling back up, and nothing new crosses the wire. It cannot drift into a lie either: a full collar means ready, and PetService only ever re-arms a ready ward, so the worst case is a full collar over an empty corridor, which is what ready looks like.

**The numbers live in `PetRigDriver.DEFAULT_MOTION`, not in `Config.Juice`**, which is this plan's "no Config changes" rule applied to motion for the same reason it applied to geometry: editing a flap angle is editing how a pet is built. It also keeps the whole family runnable under the luau CLI, since the driver requires nothing. One `Config.Pets` knob did land, `AnimateRange`, because a cull distance is a cost knob and not a look. The recipes override the baseline with absolute values rather than multipliers, and `motion` is the one look group merged key by key at every level: it holds only scalars, so a stage naming a rate means that rate and the rest of what the pet already was.

**Checked the same way Set 1 was, and the check grew teeth.** `tools/petlooks/check.sh` now runs sixty seconds of `animate` over every rig at four samples a second, driving the ward tell through all of its states, and asks where each part actually ends up: an accent must not swing inside the body it was placed to clear, nothing may leave its own silhouette by more than a stud, and nothing may reach NaN. Verified by inverting `ringWave` and watching the Bulwark's collar fail. Part counts and bounding boxes are unchanged from Set 1, which is the other thing the run confirms: swapping two welds for two motors moved no geometry.

**One thing to watch in the play test**, because it is the one claim here that a headless run cannot check: the server moves a follower with `model:PivotTo` every Heartbeat, and this assumes an anchored root plus jointed skin replicates as an assembly rather than as a dozen per-part CFrames fighting the client's pose. If pets ever read as flickering between posed and rigid, that is what it is, and the fix is to move `entry.primary.CFrame` instead of pivoting the whole model for generated rigs. `PivotTo` stays the default regardless, because an artist's model may have no joints at all and only `PivotTo` carries that.

**One regression fixed on the way in, and it is worth reading twice.** Set 1's catalogue pass replaced each row's `placeholder` and `ability` lines with the new `look`, and `ability` was not meant to go with it. Every one of the five rows lost it, so `petConfig.ability.type` was indexing nil in `applyGlow`, in `applyWard` and in `Inventory.project`: no follower could spawn and the projection every client draws its UI from threw before it returned. It survived Sets 2 and 3 because both were checked against the offline harness and the portraits, neither of which reads an ability. The five lines are restored at their original values. The lesson is the one the harness was built on and it now has a second data point: a check that runs is worth more than a check that is intended, and "equip each pet and watch it follow" is a Studio session nobody had run since the field disappeared.

**Not done, and deliberately.** Portraits do not animate: a ViewportFrame steps no physics, `PortraitGenerator` anchors what it is handed, and a picture in an inventory row is a thing a player reads. The reveal still turns the model, which is the motion that belongs there.

## Invariants this adds

1. `PetModelGenerator.build` is a pure function of `(petId, stage)`: no randomness, no yields, no ServerStorage, no collision groups. Anything less and the client portrait stops matching the server follower.
2. `ServerStorage/Pets/<model>` wins by name over the generator, always. The generator replaced the placeholder, not the artist.
3. `look.primary` is the only world colour for a stage. `Config.rarityColor` is the only UI accent. Neither reads the other.
4. Only `build` and `rigOf` know part and joint names. Accessories land on attachments, effects land on the rig or its root, nothing hunts for `WingLeft` by name outside the module.
5. An evolution stage adds or changes a group, never only scale and tint.
6. Rigs stay `sterilise`-safe: non-colliding, non-touch, non-query, massless, moved only by `PivotTo`, and anchored except where a joint holds the part. An anchored root is what makes that safe, so nothing may join the skin to something the root does not reach.
7. Motion writes `Motor6D.Transform` and never C0. C0 is the as-built offset `rigOf` measures from; a driver that edits it is editing its own baseline, and there is then a way to leave a rig permanently bent.
8. The driver stays pure: no services, no yields, no clock of its own, no instance beyond the joints handed to it. That is what keeps `tools/petlooks` able to run a minute of it in milliseconds, which is where a buried accent gets caught.
9. Nothing in the driver varies a *rate*. A tell may change an amplitude, a shape or a spread; the clock it multiplies is absolute and hours old, so a rate that moves is an angular speed that runs away with it.

## Open decisions

- ~~Where Set 4's animation loop runs.~~ Settled in Set 4: each client, in `PetAnimator`. The deciding argument turned out not to be cost but authority. A pose nobody can act on is not a thing the server should be deciding, and `Motor6D.Transform` written on a client is local to that client, so there is no channel for the two sides to disagree over.
- ~~Whether the portrait camera is one framing for all looks or a per-look override key.~~ Settled in Set 3: one framing, `PortraitGenerator`'s, which sizes the distance off each model's own bounding box and so already handles the Lumen Moth being three times wider than its body. No look has needed an override; add the key when one clips.

## What is not covered

- Artist-model portraits (needs a replicated template folder; a different bargain than `ServerStorage/Pets`).
- Egg and `EggHint` looks.
- Enemy looks: `ModelGenerator` is untouched. The two generators share an approach, deliberately not code; a shared skinPart helper would couple the pet silhouettes to the enemy ones for thirty saved lines.
