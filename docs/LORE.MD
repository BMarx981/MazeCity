# MazeCity Lore & Integration

Companion doc to `PET_EGG_DATA_SPEC.md` and `PETS_PLAN.md`. All lore is written to be delivered in one- or two-sentence fragments. No entry should ever require a scrolling text box.

The enemy roster in Section 3 describes the fourteen enemies as actually built. Lore lines are written to explain real mechanics; if a mechanic changes, its lore line changes in the same branch.

---

## 1. World Premise

**The Maze builds itself.** Every night it grows taller and rearranges its walls. Nobody knows who laid the first stone, and nobody has ever seen the top floor stay the same twice.

**The Nest** sits at the summit — the one place the Maze never touches. Eggs stay dormant until they are carried to the Nest, which is why climbers carry them up.

**The Maze makes creatures.** The ones carried to the Nest and hatched beyond its reach come out free: those are pets. The ones the Maze keeps become its servants: those are **the Kept**. Same origin, different birthplace. Every pet could have been one of the Kept.

**Climbers** are the players. The Maze doesn't want them to reach the top.

| Element | Lore answer |
|---|---|
| Why do pets exist? | Maze-made creatures hatched free at the Nest. Each ability is a survival trait. |
| Why do enemies exist? | Maze-made creatures the Maze kept. They serve it. |
| Why hatch at the summit? | The Nest is beyond the Maze's reach — hatching there is what makes a creature free. |
| Why do accessories exist? | Gear left behind by climbers who never made it. |
| Why do walls change between runs? | The Maze rebuilt itself overnight. |
| What is the Warden? | A climber the Maze kept. |

---

## 2. Pet Lore

Rule: **a pet's story explains its ability.** Lore and utility are the same sentence. Every pet ability belongs to one of the five families in Section 4, so every pet counters a category of the Kept.

### Existing configured pets

**Firefly** (Common, Glow — Watch family)
> Hatched in the lightless lower floors, where the only way to survive was to become the light.

- Evolution "Radiant": *The dark floors fear it now.*
- Evolution "Solar": *Some say a piece of the sky got lost down there.*

**Compass Crow** (Epic, DeadEndPing — Wayfinding family)
> It has flown every corridor the Maze has ever built. It remembers all of them — especially the ones that go nowhere.

- Evolution "Wayfinder": *It no longer follows the Maze. The Maze follows it.*
- Story role: the Cartographer's companion (Section 9). Journal completion rewards a guaranteed Compass Crow egg or exclusive "Wayworn" variant.

### Planned pets (one seed per family, expand freely)

**Gilded Mole** (Rare, CoinMagnet — Wayfinding family)
> For a hundred years it has collected what fallen climbers dropped. It shares now, but only with a climber it trusts.

**Echo Snail** (Rare, Checkpoint — Escape family)
> Its trail never fades, even when the walls move. Follow it back and you'll find where you were.

**Moth** (Rare, Hush — Hush family)
> It flew too close to a Shrieker once. Now it eats sound the way other things eat light.

**Backeyes** (Epic, RearWatch — Watch family)
> It watches behind you so the things that hate being watched can never move. It does not blink. It refuses on principle.

**Twitcher** (Rare, AmbushSense — Warning family)
> It feels footsteps through the floor — including the ones under it.

**Marrow Bat** (Legendary, MapReveal — Wayfinding family)
> It sleeps inside the walls while they rebuild. It has seen the Maze's blueprints from the inside.

### Egg lore

One line per egg, shown when the egg is acquired and while incubating:

- **Summit Egg**: *Warm to the touch. Something inside is waiting for still ground.*
- **Royal Summit Egg**: *The Maze rearranged three floors trying to stop this one from being found.*

---

## 3. The Kept

The Maze's servants. Design rule carried through every entry: **the lore line explains the mechanic.** A player who reads one sentence should play better against that enemy.

Codex unlock: first encounter reveals silhouette + name; surviving/escaping the encounter reveals the lore line.

**Watcher** — stationary eye, 90-stud sight, alerts everything within 70.
> The Maze cannot see. So it grew eyes in the corridors where climbers kept getting past.

**Sprinter** — 14.6 studs/s burst for 3s, then half speed for 2.5s to breathe.
> Built in one night, in a hurry. It runs like it, and it rests like it.

**Brute** — slowest, hardest hit (26 damage, 18 knockback), 0.9s windup, turn lock after swinging.
> A piece of wall that learned to swing. It never learned to turn.

**Spitter** — ranged slowing bolts from 40 studs, backs away when closed on.
> It spits the mortar the Maze builds with. Wet, it slows you. It knows that.

**Blinker** — teleports to within 12–35 studs on a 5s cooldown, can't act for 0.5s after arriving.
> It doesn't use the corridors. It walks inside the walls — and it takes a moment to remember which side it came out on.

**Shrieker** — 5 damage, screams to reveal you within 80 studs, same building and floor band.
> It was never meant to fight. It is the Maze's bell.

**Mimic** — disguises as a crate, lamp, or sign; reveals within 9 studs. Never a coin.
> It practices copying the things the Maze built. It never copies coins. The coins were never the Maze's.

This entry canonizes the no-coin-mimic rule. The game spends every floor teaching players to grab coins; the lore now guarantees that trust is never punished. Do not break this in any future update.

**Shadow** — moves only while unobserved; watched, it freezes with a material change. Facing checked server-side.
> The Maze taught it one rule: never move while a climber is watching. It has never broken it. It is very patient.

**Trapper** — places up to 3 snares (55% speed for 2.5s) rather than attacking.
> It doesn't hunt. It gardens. The snares are roots the Maze hasn't grown yet.

**Burrower** — travels under the floor, emerges 7–16 studs away after a 0.8s warning.
> For it, the floors are just more corridors.

**Gatekeeper** — 65-stud leash (shortest in the roster), 24 damage, dedicated return speed to its post.
> It was a door first. It still thinks like one. It will chase you — but it cannot bear to leave its frame for long.

**Splitter** — splits into two Splitter Children on death. Dormant in practice until enemies can take damage.
> The Maze's answer to being broken: become two.

The lore is written for the mechanic; the day damage ships, the split is a content moment, not a retcon.

**Splitter Child** — fast, weak (4 damage), `spawnable = false`. Codex sub-entry under Splitter, unlocked with the parent.
> Half the thing. Twice the grudge.

**Warden** — the elite. One per building. Telegraphed shockwave (14-stud radius, 1s windup), alerts a 100-stud radius. Enrage wired but dormant.
> One to a building. It does not patrol its floors. It mourns them.

The reveal, delivered by the journal (Section 9): a Warden is a climber the Maze kept. Codex lore line after first survival:
> Something in it is still asleep. Do not be there when it wakes.

That second line is literally true — it describes the dormant enrage. When enrage ships, veteran players get the payoff of a warning they've been reading since v1.

---

## 4. Threat Categories & Pet Counters

Fourteen enemies cannot each have a bespoke counter-pet, and combat is one-sided, so counters are about evasion, information, and recovery — never damage. Five categories:

| Category | Kept | Pet ability family | Example effects |
|---|---|---|---|
| **Alarm** | Watcher, Shrieker, Warden's alert | **Hush** | Shrink alert radius, delay reveal, muffle the scream |
| **Pursuit** | Sprinter, Brute, Gatekeeper, Splitter | **Escape** | Stamina, brief speed, knockback resist, checkpoint recovery |
| **Slows** | Spitter, Trapper | **Cleanse** | Reduce slow strength/duration, reveal snares |
| **Deception** | Mimic, Shadow | **Watch** | Reveal disguised Mimics in radius, hold rear gaze on Shadows |
| **Ambush** | Blinker, Burrower | **Warning** | Extend arrival/emergence warnings, ping incoming direction |

A sixth family, **Wayfinding** (Compass Crow, Marrow Bat, Gilded Mole), counters the Maze itself — navigation, memory, recovery of what was lost.

Design consequences:

- Every future pet ability is assigned a family at design time. No orphan abilities.
- Floor/director composition can bias toward categories, making pet choice matter per building.
- **Multi-equip is the strategic gamepass**: one pet covers one category; three pets cover three. This is the honest, gameplay-first version of the multi-equip pitch.
- Backeyes vs. Shadow is the flagship counter: the Shadow's server-checked facing rule means a rear-watching pet is a real mechanical answer, not a stat bump.

---

## 5. Accessory Lore — Relics

Every accessory is a **relic of a previous climber**. Format per item, shown in an inspect panel: one inscription line plus where it was recovered (floor number or drop source).

- **Cracked Lantern** — *"Recovered from Floor 12. Still lit."*
- **Cartographer's Satchel** — *"Its owner mapped forty floors. The Maze built a forty-first."*
- **Hollow Mask** — *"Dropped by a Warden. Do not wear it near the walls."* (Warden drop, rare)

**Named sets** create collection targets and future set-bonus monetization:

- The Cartographer's Set (satchel, compass, ink-stained gloves)
- The Lamplighter's Set (lantern, oil flask, singed cloak)
- The Hollow Set (mask, gauntlets, tattered banner) — Warden drops only

Floor numbers in inscriptions double as soft worldbuilding, and two of them (12 and 47) pay off inside the journal.

---

## 6. Integration Systems

Ordered roughly by retention value per unit of effort.

### 6.1 Hatch flavor lines (near-zero effort)
The pet's lore line appears in the hatch moment. For Epic+ hatches, the summit broadcast includes it: *"[Player] hatched Compass Crow — it remembers every dead end."* Piggybacks on the rarity broadcast stubbed in Clutch 2.

### 6.2 The Codex (the big one)
A book/monument at the Nest. Entries unlock on:
- First hatch of each pet
- First encounter of each of the Kept (silhouette + name); surviving/escaping unlocks the lore line
- First recovery of each relic
- Journal fragments via accomplishment triggers (Section 9) — locked fragments render as `???`

Completion rewards per chapter (Pets / The Kept / Relics / Journal) and a 100% reward. The Codex converts lore into a visible collection meter, which is the actual retention mechanic — the lore is the paint on it.

### 6.3 Wall writings — The Cartographer's Trail
The wall writings are a serialized journal, unlocked in order by player accomplishments. Full story and trigger table in Section 9.

### 6.4 First-encounter name cards
One-time name card per Kept type: name plus silhouette, no lore line yet (that's earned by surviving). No cutscenes, no movement lock.

### 6.5 Seasonal lore drops
Each seasonal egg ships with one new chapter: a new Kept, a new relic set, a new journal (Section 9.4). Lore becomes the framing for content updates instead of separate work.

---

## 7. LoreConfig Data Pattern

Flavor text lives in config keyed by the same ids as `Pets.luau` / `Eggs.luau` / the enemy config, so lore never migrates and Claude Code can extend it without touching gameplay code.

`src/shared/Config/Lore.luau`

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
			hatchLine = "It has flown every corridor the Maze has ever built. It remembers the ones that go nowhere.",
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
		watcher = {
			loreLine = "The Maze cannot see. So it grew eyes in the corridors where climbers kept getting past.",
		},
		shadow = {
			loreLine = "The Maze taught it one rule: never move while a climber is watching. It has never broken it. It is very patient.",
		},
		warden = {
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

Keys under `kept` must match the enemy config ids exactly. Codex unlock state in player data:

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
3. The Maze is never explained. Its origin stays an open question forever — that's the franchise hook.
4. Tone: mysterious, a little eerie, never gory. The Warden reveal is as dark as it gets.
5. Every named thing (pet, Kept, relic, floor number) should be able to appear in a future update without contradiction. When in doubt, be vague about history and specific about objects.
6. Never punish taught trust. The no-coin-Mimic rule is lore-locked (Section 3). Any new deception mechanic must respect what the game has trained players to grab.
7. If a mechanic changes, its lore line changes in the same branch. The lore describes the shipped game, always.

---

## 9. The Cartographer's Trail

The game's central story, told entirely through wall writings. One climber — **the Cartographer** — whose relics (satchel, lantern) players already collect, and whose companion was Compass Crow. Fragments unlock **in order**, each gated by a player accomplishment. The player lives the Cartographer's climb while reading it.

The reveal: the Cartographer found the first egg, carried it to the Nest, realized the Maze is a shell, and was kept. The final fragments unlock at the player's first Warden encounter and first Warden survival — the player learns what happened to the Cartographer at the same moment the Cartographer did.

### 9.1 Fragments and triggers

Fragments unlock sequentially: a trigger only counts once all earlier fragments are unlocked. Out-of-order accomplishments are banked and granted when their turn comes. (Implementation: on each trigger event, check whether it satisfies the next locked fragment; on each unlock, re-check banked stats and banked event flags, since `stats` totals make late satisfaction free to detect.)

**Fragment order is tunable.** Reorder the array to match the director's real encounter pacing per floor — the Shrieker fragment should land near where Shriekers actually first appear. The current order is a best guess.

| # | Trigger (server event / stat) | Fragment text |
|---|---|---|
| 1 | First maze completed | *Day 1. I came here to map it. How hard can a maze be?* |
| 2 | mazesCompleted >= 5 | *Day 3. Finished mapping the third floor. Woke up. There is a different third floor now.* |
| 3 | First summit reached | *Day 9. The walls moved again. I have stopped drawing in ink.* |
| 4 | First spotted by a Watcher | *Day 11. The Maze grew an eye at the end of the corridor. It saw me first. Everything came.* |
| 5 | First egg acquired | *Day 14. Found something warm inside a wall the Maze hadn't finished. It is not a stone.* |
| 6 | First egg placed at the Nest | *Day 15. Carried it to the top. The summit is the only place my maps still work.* |
| 7 | First hatch | *Day 16. It hatched where the Maze can't reach — and it came out free. It glows. It already knows the way down.* |
| 8 | Any pet reaches first evolution | *Day 22. It grows faster than the Maze does. I think that frightens the walls.* |
| 9 | First Shrieker scream survived | *Day 25. It didn't want to hurt me. It wanted everything else to. I ran before the echo finished.* |
| 10 | First Mimic revealed | *Day 30. The lamp was not a lamp. I trust the coins and nothing else now.* |
| 11 | First Shadow frozen by watching it | *Day 33. Something follows me that only moves when I look away. I have started walking backward.* |
| 12 | mazesCompleted >= 25 | *Day 40. I was wrong about everything. The Maze is not a wall.* |
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

- **Unlock moment**: toast + brief scribble sound. *"New wall writing discovered — Journal 9/17."* No modal, no interruption to the run.
- **On walls**: once unlocked, a fragment can spawn on maze walls during generation, weighted toward thematically matching areas. Unlocked-only spawning means two players in the same maze see different writings — good "how did you get that one?" social chatter.
- **In the Codex**: Journal chapter lists fragments in order, locked ones as `???` with a subtle trigger hint ("Survive the bell").
- **Completion**: Journal 17/17 grants the Compass Crow reward plus a "Cartographer" chat tag or title.

### 9.3 Config pattern

`src/shared/Config/Journal.luau`

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

Array order is unlock order. `Stat` triggers check the existing `stats` table. `Event` triggers should fire from the enemy systems' existing detection/alert events — Watcher spotting, Shrieker scream, Mimic reveal, Shadow freeze, Gatekeeper leash reset, and Warden encounter all already exist as server-side moments in the enemy code; the journal just listens to them.

### 9.4 Sequels ship free

Season 2 is another climber's journal — someone who read the Cartographer's writings and climbed anyway. Same system, new fragment config, zero new code. Each season's journal can reference the previous one, which rewards veterans without confusing new players.

---

## 10. Build Integration

For PETS_PLAN.md — the lore system is its own Clutch, dependent on the enemy work and the Codex:

**Clutch: Lore & Journal**
- Lore.luau and Journal.luau configs (this doc is the source of truth for all text)
- Codex data (`codex` table in player data, migration)
- Sequential unlock + banking logic
- Toast + wall-spawn presentation, `???` Codex rendering
- Exit: a fresh save can unlock fragments 1–17 by playing, in order, with out-of-order accomplishments banked correctly.

Additions to the integration audit checklist:
- [ ] Where each Kept detection/alert event fires server-side (Watcher spot, Shrieker scream, Mimic reveal, Shadow freeze, Gatekeeper reset, Warden encounter/survival): `TODO`
- [ ] What counts as "surviving" an encounter (leaving aggro radius? timer? maze completion after the event?): `TODO`
- [ ] Login streak tracking — exists in daily rewards or needs building: `TODO`

CLAUDE.md rule to add: **all player-facing lore text lives in this doc first, then in Lore/Journal configs.** Claude Code must not invent lore lines mid-task; new content means updating LORE.md in the same branch.