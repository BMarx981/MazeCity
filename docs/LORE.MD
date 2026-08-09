# MazeCity Lore & Integration

Companion doc to `PET_EGG_DATA_SPEC.md` and `PETS_PLAN.md`. All lore is written to be delivered in one- or two-sentence fragments. No entry should ever require a scrolling text box.

---

## 1. World Premise

**The Maze builds itself.** Every night it grows taller and rearranges its walls. Nobody knows who laid the first stone, and nobody has ever seen the top floor stay the same twice.

**The Nest** sits at the summit — the one place the Maze never touches. Eggs laid anywhere inside the Maze stay dormant until they are carried to the Nest, which is why climbers carry them up.

**Climbers** are the players. The Maze doesn't want them to reach the top.

This premise answers every design question:

| Element | Lore answer |
|---|---|
| Why do pets exist? | Creatures born inside the shifting walls. Each ability is a survival trait. |
| Why do enemies exist? | The Maze's immune system. They defend it from climbers. |
| Why do accessories exist? | Gear left behind by climbers who never made it. |
| Why hatch at the summit? | The Nest is the only still ground in a living Maze. |
| Why do walls change between runs? | The Maze rebuilt itself overnight. |

---

## 2. Pet Lore

Rule: **a pet's story explains its ability.** Lore and utility are the same sentence.

### Existing configured pets

**Firefly** (Common, Glow)
> Hatched in the lightless lower floors, where the only way to survive was to become the light.

- Evolution "Radiant": *The dark floors fear it now.*
- Evolution "Solar": *Some say a piece of the sky got lost down there.*

**Compass Crow** (Epic, DeadEndPing)
> It has flown every corridor the Maze has ever built. It remembers all of them — especially the ones that go nowhere.

- Evolution "Wayfinder": *It no longer follows the Maze. The Maze follows it.*

### Planned pets (matching the utility set from the pet spec)

**Gilded Mole** (Rare, CoinMagnet)
> For a hundred years it has collected what fallen climbers dropped. It shares now, but only with a climber it trusts.

**Echo Snail** (Rare, Checkpoint)
> Its trail never fades, even when the walls move. Follow it back and you'll find where you were.

**Marrow Bat** (Legendary, reveal-map-fragment or similar)
> It sleeps inside the walls while they rebuild. It has seen the Maze's blueprints from the inside.

### Egg lore

One line per egg, shown when the egg is acquired and while incubating:

- **Summit Egg**: *Warm to the touch. Something inside is waiting for still ground.*
- **Royal Summit Egg**: *The Maze rearranged three floors trying to stop this one from being found.*

---

## 3. Enemy Lore — "The Wardens"

Enemies are collectively called **Wardens**: the Maze's immune system. Design rule: **every Warden counters a pet ability, and a pet (or its evolution) counters the Warden.** This makes the collection strategically meaningful and feeds the multi-equip gamepass.

**Smother** (fog-type)
> A cloud of the Maze's oldest darkness. It hates light because light remembers the way out.
- Mechanic: dims player vision / shrinks light radius in its zone.
- Countered by: Firefly (Radiant+ pierces the fog).

**Filch** (thief-type)
> It doesn't want your coins. It wants you to go back for them.
- Mechanic: steals a few coins on contact and drops them deeper in the maze.
- Countered by: Gilded Mole (recovers stolen coins automatically / immunity aura).

**The Mason** (wall-shifter)
> The Maze's own hands. Where you walked, it rebuilds.
- Mechanic: closes a corridor behind the player mid-run, forcing a reroute.
- Countered by: Echo Snail (trail persists through rebuilt walls) / Marrow Bat (reveals the new route).

**Hollow Warden** (rare mini-boss, upper floors)
> A climber who reached the top floor the night the Maze finished building it. The Maze kept them.
- Mechanic: patrols near-summit floors; slow, telegraphed, high-stakes chase.
- Lore hook: Hollow Wardens were once climbers — this is the game's one piece of "dark" lore and lands well with the Roblox audience. Defeating/escaping one can drop relic accessories (Section 4).

First-encounter presentation: a one-time name card with the Warden's name and its single lore line, then never again. No cutscenes.

---

## 4. Accessory Lore — Relics

Every accessory is a **relic of a previous climber**. Format per item, shown in an inspect panel:

- One inscription line
- Where it was recovered (floor number or Warden drop)

Examples:

- **Cracked Lantern** — *"Recovered from Floor 12. Still lit."*
- **Cartographer's Satchel** — *"Its owner mapped forty floors. The Maze built a forty-first."*
- **Hollow Mask** — *"Dropped by a Hollow Warden. Do not wear it near the walls."* (Warden drop, rare)

**Named sets** create collection targets and future set-bonus monetization:

- The Cartographer's Set (satchel, compass, ink-stained gloves)
- The Lamplighter's Set (lantern, oil flask, singed cloak)
- The Hollow Set (mask, gauntlets, tattered banner) — Warden drops only

Floor numbers in inscriptions double as soft worldbuilding: players infer the Maze's history from where things were lost.

---

## 5. Integration Systems

Ordered roughly by retention value per unit of effort.

### 5.1 Hatch flavor lines (near-zero effort)
The pet's lore line appears in the hatch moment. For Epic+ hatches, the summit broadcast includes it: *"[Player] hatched Compass Crow — it remembers every dead end."* This piggybacks on the rarity broadcast already stubbed in Clutch 2.

### 5.2 The Codex (the big one)
A book/monument at the Nest. Entries unlock on:
- First hatch of each pet
- First encounter (not defeat) of each Warden — encounter unlocks the silhouette + name, defeat/escape unlocks the lore line
- First recovery of each relic

Completion rewards per chapter (Pets / Wardens / Relics) and a 100% reward (exclusive egg or pet). The Codex converts lore into a visible collection meter, which is the actual retention mechanic — the lore is the paint on it.

### 5.3 Wall writings (environmental, free content)
Short scratched messages from past climbers placed on maze walls: *"Day 9. The walls moved again."* / *"Don't trust the quiet floors."* / *"If you find my lantern, keep climbing."* A pool of ~20 lines, randomly placed per maze generation. Some reference relics players can actually find — the Cracked Lantern message pays off when a player later recovers it.

### 5.4 Seasonal lore drops
Each seasonal egg ships with one new "chapter" question: a new Warden, a new relic set, one new wall-writing batch. Lore becomes the framing for content updates instead of separate work.

---

## 6. LoreConfig Data Pattern

Flavor text lives in config keyed by the same ids as `Pets.luau` / `Eggs.luau` / future `Wardens.luau`, so lore never has to be migrated and Claude Code can extend it without touching gameplay code.

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
	wardens = {
		smother = {
			introLine = "A cloud of the Maze's oldest darkness. It hates light because light remembers the way out.",
		},
	},
	relics = {
		cracked_lantern = {
			inscription = "Recovered from Floor 12. Still lit.",
			set = "Lamplighter",
		},
	},
	wallWritings = {
		"Day 9. The walls moved again.",
		"Don't trust the quiet floors.",
		"If you find my lantern, keep climbing.",
	},
}

return Lore
```

Codex unlock state goes in player data as id sets, consistent with the existing spec:

```luau
codex = {
	pets = {},
	wardens = {},
	relics = {},
}
```

---

## 7. Writing Rules

1. One or two sentences per entry. If it needs a paragraph, cut it.
2. Lore must explain a mechanic or point at a collectible. No freestanding backstory.
3. The Maze is never explained. Its origin stays an open question forever — that's the franchise hook.
4. Tone: mysterious, a little eerie, never gory. Hollow Wardens are as dark as it gets.
5. Every named thing (pet, Warden, relic, floor number) should be able to appear in a future update without contradiction. When in doubt, be vague about history and specific about objects.