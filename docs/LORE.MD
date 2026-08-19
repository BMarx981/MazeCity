# MazeCity Lore & Integration

Companion doc to `PET_EGG_DATA_SPEC.md` and `PETS_PLAN.md`. All lore is written to be delivered in one- or two-sentence fragments. No entry should ever require a scrolling text box.

The enemy roster in Section 3 describes the nineteen enemies as actually built, plus the Splitter Child, which is a twentieth definitions row and not a twentieth type. Lore lines are written to explain real mechanics; if a mechanic changes, its lore line changes in the same branch.

Earlier drafts of this doc said fourteen. Fourteen is the number of behavior modules, not of enemies: Drifter, Stalker and Sprinter share one, and Sentry, Watcher and Gatekeeper share another.

---

## 1. World Premise

**The Maze builds itself.** Every night it grows taller and rearranges its walls. Nobody knows who laid the first stone, and nobody has ever seen the top floor stay the same twice.

**The Nest** sits at the summit, the one place the Maze never touches. Eggs stay dormant until they are carried to the Nest, which is why climbers carry them up.

**The Maze makes creatures.** The ones carried to the Nest and hatched beyond its reach come out free: those are pets. The ones the Maze keeps become its servants: those are **the Kept**. Same origin, different birthplace. Every pet could have been one of the Kept.

**Climbers** are the players. The Maze doesn't want them to reach the top.

| Element | Lore answer |
|---|---|
| Why do pets exist? | Maze-made creatures hatched free at the Nest. Each ability is a survival trait. |
| Why do enemies exist? | Maze-made creatures the Maze kept. They serve it. |
| Why hatch at the summit? | The Nest is beyond the Maze's reach: hatching there is what makes a creature free. |
| Why do accessories exist? | Gear left behind by climbers who never made it. |
| Why do walls change between runs? | The Maze rebuilt itself overnight. |
| What is the Warden? | A climber the Maze kept. |

---

## 2. Pet Lore

Rule: **a pet's story explains its ability.** Lore and utility are the same sentence. Every pet ability belongs to one of the five families in Section 4, so every pet counters a category of the Kept.

### Existing configured pets

**Firefly** (Common, Glow, Watch family)
> Hatched in the lightless lower floors, where the only way to survive was to become the light.

- Evolution "Radiant": *The dark floors fear it now.*
- Evolution "Solar": *Some say a piece of the sky got lost down there.* Written ahead of the game: `PetCatalog` ships one evolution per pet, so this line waits here and is deliberately absent from `Lore.lua`, which refuses an evolution line with no stage under it.

**Compass Crow** (Epic, DeadEndPing, Wayfinding family)
> It has flown every corridor the Maze has ever built. It remembers all of them, especially the ones that go nowhere.

- Evolution "Wayfinder": *It no longer follows the Maze. The Maze follows it.*
- Story role: the Cartographer's companion (Section 9). Journal completion rewards a guaranteed Compass Crow egg or exclusive "Wayworn" variant.

**Lumen Moth** (Uncommon, Glow, Watch family)
> It does not carry the light. It is the light, stretched thin enough to cross a whole corridor as one shape.

- Evolution "Pale": *It has been burning far longer than it has been alive. Whatever colour it started as is gone.*

**Ward Hound** (Rare, Ward, family open, see Section 4)
> The Maze built it to keep things out and never said out of where, so it decided that part for itself. It cannot hold forever, and it will not spend itself on an empty corridor.

- Evolution "Bulwark": *It stopped flinching a long time ago.*

**Coin Bat** (Rare, CoinMagnet, Wayfinding family)
> It found one coin a very long time ago and has never once put it down. Everything else it finds, it brings to you.

- Evolution "Gilded": *Two coins now. It has not explained where the second one came from.*

### Planned pets (one seed per family, expand freely)

**Gilded Mole** (Rare, CoinMagnet, Wayfinding family)
> For a hundred years it has collected what fallen climbers dropped. It shares now, but only with a climber it trusts.

**Echo Snail** (Rare, Checkpoint, Escape family)
> Its trail never fades, even when the walls move. Follow it back and you'll find where you were.

**Moth** (Rare, Hush, Hush family)
> It flew too close to a Shrieker once. Now it eats sound the way other things eat light.

**Backeyes** (Epic, RearWatch, Watch family)
> It watches behind you so the things that hate being watched can never move. It does not blink. It refuses on principle.

**Twitcher** (Rare, AmbushSense, Warning family)
> It feels footsteps through the floor, including the ones under it.

**Marrow Bat** (Legendary, MapReveal, Wayfinding family)
> It sleeps inside the walls while they rebuild. It has seen the Maze's blueprints from the inside.

### Egg lore

One line per egg, shown when the egg is acquired and while incubating:

- **Summit Egg**: *Warm to the touch. Something inside is waiting for still ground.*
- **Royal Summit Egg**: *The Maze rearranged three floors trying to stop this one from being found.*
- **Streak Egg**: *Seven nights of the Maze rebuilding itself, and this one did not move. Something in it has been counting too.*

The Streak Egg is the day-seven daily reward and the only egg with no price, so its line is read by a player who came back a week running. It answers fragment 13 (Section 9.1) without either one naming the other.

---

## 3. The Kept

The Maze's servants. Design rule carried through every entry: **the lore line explains the mechanic.** A player who reads one sentence should play better against that enemy.

Codex unlock: first encounter reveals silhouette + name; surviving/escaping the encounter reveals the lore line.

**Drifter**: the baseline. Wanders its post, 11 studs/s, 55-stud sight, loses ground on every corner.
> The first thing the Maze ever managed to finish. It has never once learned a corner.

**Stalker**: 9 studs/s while you face it, 15 the moment you look away. 70-stud sight.
> It will not close while you are watching, and that is a rule rather than a mercy. The corridor behind you is the only one it is interested in.

**Sentry**: holds a post, 20 damage, the shortest patience in the roster at a 70-stud leash.
> It was given a place and never anything else to do but hold it. Every climber it ever took walked in knowing exactly where it stood.

**Swarmer**: weakest hit at 6, fastest swing, calls every one of its own within 120 studs.
> Alone it is barely worth the name it was given. It knows that, and it does not intend to be alone for long.

**Lurker**: scenery until you are within 34 studs; goes back to being scenery once you leave.
> It is part of the room until you come close enough to be worth standing up for. Leave it alone long enough and it is part of the room again.

**Charger**: telegraphed rush from up to 95 studs, a locked straight line for 1.6s, then 0.8s to recover.
> It commits. Once it has chosen its line it cannot choose another, and the wall it finds instead of you takes a moment to forgive.

**Watcher**: stationary eye, 90-stud sight, alerts everything within 70.
> The Maze cannot see. So it grew eyes in the corridors where climbers kept getting past.

**Sprinter**: 15 studs/s burst for 3s, then just over half speed for 2.5s to breathe.
> Built in one night, in a hurry. It runs like it, and it rests like it.

**Brute**: slowest, hardest hit (26 damage, 18 knockback), 0.9s windup, turn lock after swinging.
> A piece of wall that learned to swing. It never learned to turn.

**Spitter**: ranged slowing bolts from 40 studs, backs away when closed on.
> It spits the mortar the Maze builds with. Wet, it slows you. It knows that.

**Blinker**: teleports to within 12 to 35 studs on a 5s cooldown, can't act for 0.5s after arriving.
> It doesn't use the corridors. It walks inside the walls, and it takes a moment to remember which side it came out on.

**Shrieker**: 5 damage, screams to reveal you within 80 studs, same building and floor band.
> It was never meant to fight. It is the Maze's bell.

**Mimic**: disguises as a crate, lamp, or sign; reveals within 9 studs. Never a coin.
> It practices copying the things the Maze built. It never copies coins. The coins were never the Maze's.

This entry canonizes the no-coin-mimic rule. The game spends every floor teaching players to grab coins; the lore now guarantees that trust is never punished. Do not break this in any future update.

**Shadow**: moves only while unobserved; watched, it freezes with a material change. Facing checked server-side.
> The Maze taught it one rule: never move while a climber is watching. It has never broken it. It is very patient.

**Trapper**: places up to 3 snares (55% speed for 2.5s) rather than attacking.
> It doesn't hunt. It gardens. The snares are roots the Maze hasn't grown yet.

**Burrower**: travels under the floor, emerges 7 to 16 studs away after a 0.8s warning.
> For it, the floors are just more corridors.

**Gatekeeper**: 65-stud leash (shortest in the roster), 24 damage, dedicated return speed to its post.
> It was a door first. It still thinks like one. It will chase you, but it cannot bear to leave its frame for long.

**Splitter**: splits into two Splitter Children on death. Dormant in practice until enemies can take damage.
> The Maze's answer to being broken: become two.

The lore is written for the mechanic; the day damage ships, the split is a content moment, not a retcon.

**Splitter Child**: fast, weak (4 damage), `spawnable = false`. Codex sub-entry under Splitter, unlocked with the parent.
> Half the thing. Twice the grudge.

**Warden**: the elite. One per building. Telegraphed shockwave (14-stud radius, 1s windup), alerts a 100-stud radius. Enrage wired but dormant.
> One to a building. It does not patrol its floors. It mourns them.

The reveal, delivered by the journal (Section 9): a Warden is a climber the Maze kept. Codex lore line after first survival:
> Something in it is still asleep. Do not be there when it wakes.

That second line is literally true: it describes the dormant enrage. When enrage ships, veteran players get the payoff of a warning they've been reading since v1.

---

## 4. Threat Categories & Pet Counters

Nineteen enemies cannot each have a bespoke counter-pet, and combat is one-sided, so counters are about evasion, information, and recovery, never damage. Five categories:

| Category | Kept | Pet ability family | Example effects |
|---|---|---|---|
| **Alarm** | Watcher, Shrieker, Warden's alert | **Hush** | Shrink alert radius, delay reveal, muffle the scream |
| **Pursuit** | Sprinter, Brute, Gatekeeper, Splitter | **Escape** | Stamina, brief speed, knockback resist, checkpoint recovery |
| **Slows** | Spitter, Trapper | **Cleanse** | Reduce slow strength/duration, reveal snares |
| **Deception** | Mimic, Shadow | **Watch** | Reveal disguised Mimics in radius, hold rear gaze on Shadows |
| **Ambush** | Blinker, Burrower | **Warning** | Extend arrival/emergence warnings, ping incoming direction |

A sixth family, **Wayfinding** (Compass Crow, Marrow Bat, Gilded Mole), counters the Maze itself: navigation, memory, recovery of what was lost.

Design consequences:

- Every future pet ability is assigned a family at design time. No orphan abilities.

**Open: Ward has no family, and it is the one ability that already shipped.** The Ward Hound (Clutch 6) makes an enemy inside its radius drop its target and walk home. That is not Alarm, Escape, Cleanse, Watch, Warning or Wayfinding: it repels rather than hides, informs or recovers. Two ways out, both fine and neither chosen yet. Either a seventh family, **Repel**, counters Pursuit alongside Escape by ending a chase where Escape survives one; or Ward is folded into Escape on the grounds that both answer the same category and differ only in method. This decides one line of Section 2 and nothing in code.

**Open: CoinMagnet is assigned to two pets.** The Coin Bat ships with it (Rare, Wayfinding by the table above) and the planned Gilded Mole is written around it. Either the Mole takes a different Wayfinding ability, or it becomes the Coin Bat's evolution line rather than a separate pet, or the duplication stands on the grounds that two pets may share an ability at different strengths. Also purely a Section 2 decision.
- Floor/director composition can bias toward categories, making pet choice matter per building.
- **Multi-equip is the strategic gamepass**: one pet covers one category; three pets cover three. This is the honest, gameplay-first version of the multi-equip pitch.
- Backeyes vs. Shadow is the flagship counter: the Shadow's server-checked facing rule means a rear-watching pet is a real mechanical answer, not a stat bump.

---

## 5. Accessory Lore: Relics

Every accessory is a **relic of a previous climber**. Format per item, shown in an inspect panel: one inscription line plus where it was recovered (floor number or drop source).

- **Cracked Lantern**: *"Recovered from Floor 12. Still lit."*
- **Cartographer's Satchel**: *"Its owner mapped forty floors. The Maze built a forty-first."*
- **Hollow Mask**: *"Dropped by a Warden. Do not wear it near the walls."* (Warden drop, rare)

**Named sets** create collection targets and future set-bonus monetization:

- The Cartographer's Set (satchel, compass, ink-stained gloves)
- The Lamplighter's Set (lantern, oil flask, singed cloak)
- The Hollow Set (mask, gauntlets, tattered banner), Warden drops only

Floor numbers in inscriptions double as soft worldbuilding, and two of them (12 and 47) pay off inside the journal.

**None of this exists in the game yet, and the Codex's Relics chapter is deferred because of it.** `AccessoryCatalog` ships twenty-two items and not one of the ids above is among them; the near misses are `lantern_hat`, `cartographers_circlet` and `coin_satchel`. There is no `set` field on an accessory row for the named sets to live in, and nothing in the game drops anything, so the Hollow Set has no source. `Lore.relics` ships empty and the chapter arrives when the gear economy does (PET_ACCESSORIES_PLAN Set 5). The three inscriptions above stay here as the writing target for that day.

---

## 6. Integration Systems

Ordered roughly by retention value per unit of effort.

### 6.1 Hatch flavor lines (near-zero effort)
The pet's lore line appears in the hatch moment. For Epic+ hatches, the summit broadcast includes it: *"[Player] hatched Compass Crow. It remembers every dead end."* Piggybacks on the rarity broadcast stubbed in Clutch 2.

### 6.2 The Codex (the big one)
A book/monument at the Nest. Entries unlock on:
- First hatch of each pet
- First encounter of each of the Kept (silhouette + name); surviving/escaping unlocks the lore line
- First recovery of each relic
- Journal fragments via accomplishment triggers (Section 9): locked fragments render as `???`

Completion rewards per chapter (Pets / The Kept / Relics / Journal) and a 100% reward. The Codex converts lore into a visible collection meter, which is the actual retention mechanic; the lore is the paint on it.

### 6.3 Wall writings: The Cartographer's Trail
The wall writings are a serialized journal, unlocked in order by player accomplishments. Full story and trigger table in Section 9.

### 6.4 First-encounter name cards
One-time name card per Kept type: name plus silhouette, no lore line yet (that's earned by surviving). No cutscenes, no movement lock.

### 6.5 Seasonal lore drops
Each seasonal egg ships with one new chapter: a new Kept, a new relic set, a new journal (Section 9.4). Lore becomes the framing for content updates instead of separate work.

---

## 7. LoreConfig Data Pattern

Flavor text lives in config keyed by the same ids as `Pets.luau` / `Eggs.luau` / the enemy config, so lore never migrates and Claude Code can extend it without touching gameplay code.

**Shipped as `src/shared/Lore.lua`**, directly under `src/shared` and `.lua` rather than `.luau`, which is this repo's shared-module convention rather than the spec-generic path below. The sketch that follows is the shape; the file is the content, and it validates every key against the four real source tables at require time, so an id that does not exist is a startup error rather than a Codex row that never appears.

```luau
local Lore = {
	pets = {
		firefly = {
			hatchLine = "Hatched in the lightless lower floors, where the only way to survive was to become the light.",
			evolutionLines = {
				"The dark floors fear it now.",
				"Some say a piece of the sky got lost down there.",
			},
		},
		compass_crow = {
			hatchLine = "It has flown every corridor the Maze has ever built. It remembers all of them, especially the ones that go nowhere.",
			evolutionLines = {
				"It no longer follows the Maze. The Maze follows it.",
			},
		},
	},
	eggs = {
		summit_common = { flavor = "Warm to the touch. Something inside is waiting for still ground." },
		summit_royal = { flavor = "The Maze rearranged three floors trying to stop this one from being found." },
	},
	kept = {
		Watcher = {
			loreLine = "The Maze cannot see. So it grew eyes in the corridors where climbers kept getting past.",
		},
		Shadow = {
			loreLine = "The Maze taught it one rule: never move while a climber is watching. It has never broken it. It is very patient.",
		},
		Warden = {
			loreLine = "One to a building. It does not patrol its floors. It mourns them.",
			survivalLine = "Something in it is still asleep. Do not be there when it wakes.",
		},
	},
	relics = {
		cracked_lantern = {
			inscription = "Recovered from Floor 12. Still lit.",
			set = "Lamplighter",
		},
	},
}

return Lore
```

Keys under `kept` must match the enemy config ids exactly, which is why they are PascalCase where the three catalogues are snake_case: a key mirrors the case of the table it points at. Codex unlock state in player data:

```luau
codex = {
	pets = {},
	kept = {},
	relics = {},
	journal = {},
}
```

---

## 8. Writing Rules

1. One or two sentences per entry. If it needs a paragraph, cut it.
2. Lore must explain a mechanic or point at a collectible. No freestanding backstory.
3. The Maze is never explained. Its origin stays an open question forever, and that is the franchise hook.
4. Tone: mysterious, a little eerie, never gory. The Warden reveal is as dark as it gets.
5. Every named thing (pet, Kept, relic, floor number) should be able to appear in a future update without contradiction. When in doubt, be vague about history and specific about objects.
6. Never punish taught trust. The no-coin-Mimic rule is lore-locked (Section 3). Any new deception mechanic must respect what the game has trained players to grab.
7. If a mechanic changes, its lore line changes in the same branch. The lore describes the shipped game, always.

---

## 9. The Cartographer's Trail

The game's central story, told entirely through wall writings. One climber, **the Cartographer**, whose relics (satchel, lantern) players already collect, and whose companion was Compass Crow. Fragments unlock **in order**, each gated by a player accomplishment. The player lives the Cartographer's climb while reading it.

The reveal: the Cartographer found the first egg, carried it to the Nest, realized the Maze is a shell, and was kept. The final fragments unlock at the player's first Warden encounter and first Warden survival: the player learns what happened to the Cartographer at the same moment the Cartographer did.

### 9.1 Fragments and triggers

Fragments unlock sequentially: a trigger only counts once all earlier fragments are unlocked. Out-of-order accomplishments are banked and granted when their turn comes. (Implementation: on each trigger event, check whether it satisfies the next locked fragment; on each unlock, re-check banked stats and banked event flags, since `stats` totals make late satisfaction free to detect.)

**Fragment order is tunable.** Reorder the array to match the director's real encounter pacing per floor: the Shrieker fragment should land near where Shriekers actually first appear. The current order is a best guess.

| # | Trigger (server event / stat) | Fragment text |
|---|---|---|
| 1 | First floor cleared | *Day 1. I came here to map it. How hard can a maze be?* |
| 2 | floorsCleared >= 5 | *Day 3. Finished mapping the third floor. Woke up. There is a different third floor now.* |
| 3 | First summit reached | *Day 9. The walls moved again. I have stopped drawing in ink.* |
| 4 | First spotted by a Watcher | *Day 11. The Maze grew an eye at the end of the corridor. It saw me first. Everything came.* |
| 5 | First egg acquired | *Day 14. Found something warm inside a wall the Maze hadn't finished. It is not a stone.* |
| 6 | First egg placed at the Nest | *Day 15. Carried it to the top. The summit is the only place my maps still work.* |
| 7 | First hatch | *Day 16. It hatched where the Maze can't reach, and it came out free. It glows. It already knows the way down.* |
| 8 | Any pet reaches first evolution | *Day 22. It grows faster than the Maze does. I think that frightens the walls.* |
| 9 | First Shrieker scream survived | *Day 25. It didn't want to hurt me. It wanted everything else to. I ran before the echo finished.* |
| 10 | First Mimic revealed | *Day 30. The lamp was not a lamp. I trust the coins and nothing else now.* |
| 11 | First Shadow frozen by watching it | *Day 33. Something follows me that only moves when I look away. I have started walking backward.* |
| 12 | summitsReached >= 5 | *Day 40. I was wrong about everything. The Maze is not a wall.* |
| 13 | 7-day login streak | *Day 41. It builds every night. Shells grow before the thing inside them does.* |
| 14 | First Gatekeeper leash reset survived | *Day 44. Even the doors hunt now. But they always go home. Remember that. They always go home.* |
| 15 | summitsReached >= 10 | *Day 47. Lost my satchel today. Floor 47 wants me to forget what I mapped. I won't.* |
| 16 | First Warden encounter | *Day 50. Something on the high floors wears a climber's boots. It walked like it remembered walking.* |
| 17 | First Warden escape/survival | *Day 53. If you are reading this, the Maze finished my map for me. Leave the eggs at the Nest. Keep climbing. Do not look for me in the walls.* |

Notes:
- Fragments 4 and 15 pay off the Cracked Lantern ("Floor 12") and Cartographer's Satchel relic inscriptions. Players who connect them get the "I figured it out" moment; players who don't lose nothing.
- Fragment 10 reinforces the no-coin-Mimic rule inside the story itself.
- Fragment 11 teaches Shadow counter-play (keep it watched) as the Cartographer's own coping behavior.
- Fragment 14 teaches the Gatekeeper leash as advice from a survivor.
- Fragment 12 is deliberately incomplete; fragment 13 finishes the thought behind a 7-day streak. The story itself enforces the daily loop. This is the highest-leverage pair in the system.
- Fragment 17 spawns only at the Nest. The story ends where the player's every run ends.
- Rule 3 holds: "shell" is never explained. Shell around what, or under what, is the update hook forever.

### 9.2 Presentation

- **Unlock moment**: toast + brief scribble sound. *"New wall writing discovered. Journal 9/17."* No modal, no interruption to the run.
- **On walls**: once unlocked, a fragment is written on the maze itself, and **the client draws it, not the generator**. Written as a generation spawn above, which is not possible here and never was: `MazeGenerator` is deterministic and per section while an unlocked-only writing is per player, so baking one in would break generation invariant 6 and the two-players-see-different-writings property in the same stroke. It is a client draw over walls the server already built, in a model beside `MazeCity` and never inside it, the way `TimerGui` draws its route markers.

  Which wall carries one is a **hash of the wall's own position**, so it is not a roll and there is no per-player state anywhere: positions are a pure function of the world seed, so the same wall carries a writing on every machine and in every session, and a corridor walked back down says the same thing it said. What differs between two players standing in it is which fragment, the pool being what each of them has unlocked, which is the social chatter this bullet wanted and it costs nothing on the wire. One eligible wall in `Config.Lore.WritingSpacing` carries one, which is tuned so a corridor holds at most one: a wall writing is a find, and a maze papered in them is a maze nobody reads.

  A wall is eligible if it is in the `MazeWall` collision group (generation invariant 7, which is what makes "is this a maze wall" answerable by construction rather than by a name check), is not a moving wall (it would leave its writing behind) or a phantom (that wall is something the player is meant to be reading for itself), and it fits: its own vertical extent has to contain the writing's band, which is the floor filter and needs no storey height, and its run has to be at least the writing's width, which keeps a sentence off the short panels flanking a doorway. The face is the hash's choice of the panel's two sides, falling back to the other when the first has no open air in front of it, which is what keeps a writing off the outward side of a boundary wall without the client knowing what a boundary wall is.

  Two things in the config are **not** implemented and are worth knowing about rather than finding: `spawnHint` on a fragment has no values written and nothing reads it, so "weighted toward thematically matching areas" is a placement rule the content does not yet exist for, and it is a doc edit before it is a code one. `nestOnly` is implemented and is the exception: fragment 17 is out of the wall pool entirely and stands beside the Egg Roost instead, lettered on both faces because a roof is walked around and a wall is not.
- **In the Codex**: Journal chapter lists fragments in order, locked ones as `???` with a subtle trigger hint ("Survive the bell").
- **Completion**: Journal 17/17 grants the Compass Crow reward plus a "Cartographer" chat tag or title.

### 9.3 Config pattern

**Shipped as `src/shared/Journal.lua`**, on the same path convention as `Lore.lua`, and the module is the array itself so `#Journal` is the chapter's size. `src/server/LoreService.server.lua` is what reads it, and it is the only file that knows an event string means a fragment: services publish facts about what happened and the service maps them, so reordering this array reaches nothing else. Its exported types live in `src/shared/Types.lua` beside the profile's `JournalState`, which is where this repo documents shapes. It checks itself at require time the way `Lore.lua` does: unique ids, well formed triggers, no two fragments on one event, and a `Stat` trigger may only name `floorsCleared` or `summitsReached`.

```luau
export type JournalTrigger =
	{ type: "Stat", stat: string, value: number }
	| { type: "Event", event: string }

export type JournalFragment = {
	id: string,
	day: number,
	text: string,
	trigger: JournalTrigger,
	spawnHint: string?,
	nestOnly: boolean?,
}

local Journal: { JournalFragment } = {
	{
		id = "day_1",
		day = 1,
		text = "I came here to map it. How hard can a maze be?",
		trigger = { type = "Event", event = "FirstMazeComplete" },
	},
	{
		id = "day_11",
		day = 11,
		text = "The Maze grew an eye at the end of the corridor. It saw me first. Everything came.",
		trigger = { type = "Event", event = "FirstWatcherSpotted" },
	},
	{
		id = "day_53",
		day = 53,
		text = "If you are reading this, the Maze finished my map for me. Leave the eggs at the Nest. Keep climbing. Do not look for me in the walls.",
		trigger = { type = "Event", event = "FirstWardenSurvived" },
		nestOnly = true,
	},
}

return Journal
```

Array order is unlock order. `Event` triggers fire from the enemy systems' detection and alert moments, and the audit in PETS_PLAN.md found that claim to be two thirds true when it was written: Watcher spotting, Shrieker scream, Mimic reveal, Shadow freeze and Warden encounter all existed as discrete server-side moments and needed only a channel to be heard on, while the Gatekeeper leash reset and the Warden survival existed in no form. All seven are sources now. The last two turned out to be one moment rather than two features: an encounter's close, which is the enemy giving up while the player is alive, and which carries whether it gave up on a leash or on a lost line of sight.

Four of the five pet-side fragments are not fired by anything, because the saved profile already answers them: an egg in the shelf, an incubator with something in it, a hatch counter, a pet past its first stage. Those are predicates rather than events, and the service banks what they say the first time it sees it. The seven-day streak is the one that cannot be a predicate and has to be caught at the claim, for the reason in the third checklist item in Section 11.

`Stat` triggers read the existing `stats` table, and deliberately not the `mazesCompleted` field in it: that one counts whatever `Config.Pets.HatchUnit` currently says a maze is, so a journal gated on it would have its pacing silently rewritten by a config flip meant for eggs. The stat triggers use `floorsCleared` and `summitsReached`, both of which mean one thing forever.

### 9.4 Sequels ship free

Season 2 is another climber's journal, someone who read the Cartographer's writings and climbed anyway. Same system, new fragment config, zero new code. Each season's journal can reference the previous one, which rewards veterans without confusing new players.

---

## 10. The City: Districts and Towers

The Maze rebuilds its floors overnight. It rebuilds the streets too, only slower, and that difference is the whole of why the ground level is survivable and the towers are not.

### 10.1 Why the streets are a maze at all

**The street is the Maze's ground floor.** It moves on a longer clock than the floors above it, slow enough that a climber can learn a route and slow enough that somebody once had time to write the route down. That is the premise the whole street layer hangs off: everything a player finds down there was put there by a climber, and the Maze has never bothered to take any of it back.

**Signposts.** Climbers put them up. They are hand-cut, they point at towers by name, and they are correct because the streets have not moved since the last climber corrected them. A sign is a kindness from somebody who is not coming back.

**The empty homes and shopfronts.** From before. The Maze grew through a city that was already standing, and the doors it did not need it simply sealed. Nobody lives there. Nothing in them is for sale.

> **Rule this encodes, and it is an implementation rule as much as a lore one: nothing on the street sells anything.** The only counter in the city that trades is the lit one with the canopy, and the only roost is the one at the summit. A shuttered shopfront carries no light, no sign, no prompt and no name. A player must never walk up to a decoration expecting a shop.

**The overlooks.** Climbers built them to read the streets from above, and the Maze allowed it on one condition, which it has never once relaxed: an overlook must lead nowhere. One stair up, the same stair down, glass on every side. You may see the way out. You may not take it from up there.

### 10.2 Districts

A section of the city is a district. Eight names, in order, wrapping when the city runs past them:

| # | District |
|---|---|
| 1 | Lowwater |
| 2 | Ashfall |
| 3 | Thirdmarch |
| 4 | Netherstair |
| 5 | Greyhollow |
| 6 | Coldmouth |
| 7 | Lanternreach |
| 8 | Saltgate |

They wrap rather than run out because the city does not end. A climber who reaches Lowwater a second time has gone further than anyone has records for, and the name coming back around is the point rather than a bug.

### 10.3 Towers

A tower is named for what it was before the Maze took it. The six names are the six building themes, already carried on each style, and they are used with the definite article:

| Style | Tower | Line |
|---|---|---|
| Cobalt | **The Drowned Archive** | Everything written here was written twice, because the first copy is under the water and the second is a guess. |
| Ochre | **The Buried Reliquary** | It was a place for keeping things safe. It is still very good at the keeping and has forgotten the rest. |
| Slate | **The Silent Monolith** | No door was ever cut in it. The one you are walking through was not cut by anybody. |
| Verdigris | **The Alchemist Stack** | Ten floors of somebody trying to turn one thing into another. The Maze finished the work and did not say what into what. |
| Bone | **The Ivory Ossuary** | The climbers who did not come down are all still here, and the building is politely built out of the fact. |
| Ember | **The Cinder Sanctum** | It burned. It is still burning, somewhere around floor six, and has been for longer than the district has had a name. |

### 10.4 Display format

Full name, for the plaza billboard and anywhere a tower must be unambiguous across the whole city:

> **The Drowned Archive, Lowwater**

Short name, for the roof sign and for a signpost arm, where the reader is already standing in the district:

> **The Drowned Archive**

The short name is safe to use alone because a tower's style index is `((section + building) % 6) + 1`, and building index runs 1 to 6, so **all six themes appear exactly once in every district**. Two towers can never share a name inside a section, and `theme + district` is unique city-wide until the districts wrap at section 9.

---

## 11. Build Integration

For PETS_PLAN.md, the lore system is its own Clutch, dependent on the enemy work and the Codex:

**Clutch: Lore & Journal**
- Lore.luau and Journal.luau configs (this doc is the source of truth for all text)
- Codex data (`codex` table in player data, migration)
- Sequential unlock + banking logic
- Toast + wall-spawn presentation, `???` Codex rendering
- Exit: a fresh save can unlock fragments 1 to 17 by playing, in order, with out-of-order accomplishments banked correctly.

Additions to the integration audit checklist, answered 2026-08-10 in PETS_PLAN.md's "Lore integration audit", which carries the file and line for each:
- [x] Where each Kept detection/alert event fires server-side: **answered in full by `Enemy/EnemyLore.lua`, 2026-08-19, and all seven now leave the enemy system on the `LoreEvent` channel.** As found, five of seven were discrete server-side moments, the Shadow freeze was discrete but did not record which player caused it, and the Gatekeeper leash reset and Warden survival did not exist. The Shadow's `watchedBy` returns the watcher instead of a boolean, which is the same loop at the same cost. The other two turned out to be the same moment as each other: an encounter's close, which the controller already reaches from `loseTarget`, `goHome` and `stop`, carrying a reason that distinguishes a leash from a lost line of sight because the leash is directly answerable at that instant.
- [x] What counts as "surviving" an encounter: **decided 2026-08-11. The enemy gives up while you are alive.** An encounter opens at a start moment the enemy system already holds and closes when that same rig loses you or walks away and despawns; a death between the two cancels it. Not a timer and not a maze completed afterward, both of which are equally true of a climber who was never in danger. Fragment 14 is the one this does not rescue, because it names *why* the enemy gave up and nothing distinguishes a leash from a lost line of sight.
- [x] Login streak tracking: exists as `data.daily.streak`, but it counts daily *claims* rather than logins, and it wraps back to 1 past seven, so fragment 13 must be caught at the claim and can never be a poll.

CLAUDE.md rule to add: **all player-facing lore text lives in this doc first, then in Lore/Journal configs.** Claude Code must not invent lore lines mid-task; new content means updating LORE.md in the same branch.