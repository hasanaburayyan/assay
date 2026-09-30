# Properties

Status: **Open**. A prototype list of the properties the world is built
from, for the thin slice. Nothing here is built. Sections use the same
markers as `GAME.md`.

## The method

Rules are written between **properties**, never between objects. Objects
(ore, parts, machines) are bundles of property values, and their behaviour
falls out of the rules. The test for any object: can every behaviour be
explained by the rules in §7? If not, either a general rule is missing or
the property list is.

Each material property corresponds to **one way a part can fail**. Players
can ask "how would this break?" and know which number to look at.

## Every material is generated

There is **no fixed list of materials**. Every mineral in the world is
generated from the seed, with its own name and its own property values, and
no two are the same kind. There is no "iron" that every player finds; there
is whatever this world's minerals turned out to be. Finding out what a new
mineral is good for is part of the game.

What follows from this:

- **Nothing in the game may refer to a specific material.** Recipes,
  blueprints, research and progression gates ask for **properties**, never
  names: "a drill head needs hardness ≥ 30", not "a drill head needs iron".
  Any rule that names a material is a bug in the design.
- **Families are ingredients, not kinds.** The families in §2 are how
  generation mixes property values. Players never collect "a metallic"; they
  find a specific mineral that happens to lean metallic.
- **Items are identified by their mineral.** Ore, processed material and
  parts carry the ID of the mineral they came from. They stack by mineral
  (and later by grade), so two different minerals never share a stack.
- **Visuals come from properties too.** `GAME.md` asks for ore kinds to be
  told apart by shape as well as colour. With unlimited minerals, shape and
  colour have to be generated from the property values (for example, family
  mix sets the crystal shape, purity sets the glow) rather than drawn per
  kind.
- **Guarantees come from generation, not hand-placed materials.** When a
  world must contain something (like the ladder in `starting-zone.md`), the
  generator creates a mineral with the needed properties. It never falls back
  to a fixed, known material.

**Relationship to what's built (Open):** today's sim has four fixed ore
kinds (Iron, Copper, Coal, Stone) and recipes that name them. This proposal
replaces those with generated minerals. How and when to migrate is not
decided.

## Simplifications for the slice

- **Material sets the ceiling; size sets the amount.** Properties that don't
  grow with size (hardness, heat tolerance) come from the material. Ones that
  do (load capacity, throughput, weight) are material × units.
- **Check at design time wherever possible.** A design's shape doesn't change
  while it runs, so structural and heat checks happen once, when the design
  is saved. Only four rules run per tick.
- **Energy comes only from fuel.** Furnaces burn fuel (see Reactivity);
  drills and arms need no energy. There is no power grid.
- **Carried items weigh nothing.**
- **Fixed machines only.** No vehicles.
- **Load doesn't pass between machines.** A machine's weight is checked
  against its own structure only.
- **Material properties are whole numbers from 1 to 100.**

## 1. World constants

| Constant | Starting guess | Used for |
|---|---|---|
| Tile | One grid cell | Footprint, reach, distance |
| Tile capacity | 8 units | The miniaturization budget per tile. Never upgrades; parts shrink instead |
| Step factor | 0.8 | How far each upgrade reaches (see §6) |
| Hand spark temperature | Low, e.g. 15 | The hottest fire a player can start by hand. Any fuel that ignites below it can be lit with no machine |

## 2. Material properties (generated per mineral)

| Property | Scales with size? | Failure it prevents | Used by |
|---|---|---|---|
| **Density** | No | Too heavy | Everything, through weight |
| **Strength** | No; load capacity = strength × units | Bending, snapping | Bases, arms |
| **Hardness** | No | Can't cut, wears down | Drill heads, claws; also how hard the ore is to mine |
| **Heat tolerance** | No | Softening, melting | Burners, chambers, anything near heat; also how hot the ore must get to process |
| **Reactivity** | No; burn time = reactivity × fuel consumed | Reactive parts ignite near heat | Fuel for burners |
| *Toughness* (Open) | No | Shattering | Arrives with wear and durability |
| *Conductivity* (Open) | No | Power loss; heat leaking | Arrives with power. One number for heat and electricity |

Stiffness is folded into strength; players won't feel the difference on a
tile grid.

**Reactivity** is how much energy a mineral releases when it's consumed as
fuel. It replaces a named fuel like coal: whichever mineral burns well is
the fuel. In the slice it means combustion only; the broader chemical sense
(corroding or reacting with neighbours) is Open. From it:

- **Burn temperature** = reactivity. A bigger pile doesn't burn hotter.
- **Burn time** = reactivity × fuel consumed.
- **Ignition temperature** = step factor × heat tolerance (calculated, not a
  new property). Easily melted, reactive minerals light easily. A
  high-energy mineral that's also heat tolerant needs a hot furnace just to
  start, so better fuels need a hotter fire to light: the same climb as
  processing (§6).
- **Burn it or build with it?** A mineral that is both reactive and strong
  is a real choice.

Other names for the same ideas: the design note
`docs/design-notes/2026-09-30-generated-minerals.md` (on the `initial-loop`
branch) calls heat tolerance "melt point" and reactivity "energy value".

**Generation (proposal):** each mineral is a blend of families, and purity
(from `GAME.md`) scales the whole blend. Families are only the ingredients
of generation (see "Every material is generated"); each blend is a new,
unique mineral.

| Family | Profile | Good for |
|---|---|---|
| Metallic | Strong, dense, middling hardness | Bases, arms |
| Ceramic | Hard, heat tolerant, light-ish, weak under load | Drill heads, furnace parts |
| Light | Low density, weak, low heat tolerance | Arm tips, anything far from support |

This builds in the real-world trade-offs: hard materials tend to be brittle,
and **strong-and-light is the rare, valuable find.**

## 3. Part properties (per component in a blueprint)

**The player chooses:** the part type, its material, its size in units, and
its shape (the tiles it occupies).

**Calculated:**

| Property | Formula |
|---|---|
| Weight | Density × units |
| Load capacity | Strength × units (base and arm only) |
| Build cost | Units of processed material |

**Part catalogue for the slice:**

| Part | Limit set by (size doesn't help) | Amount set by (× units) | Notes |
|---|---|---|---|
| Base | Strength | Load capacity | Its tiles are the supported tiles |
| Arm segment | Strength | Load capacity | Each segment adds 1 tile of reach |
| Claw | Hardness (can it grip this) | – | Items per swing = number of claws |
| Drill head | Hardness (what it can mine) | Mining speed | |
| Burner | Heat tolerance (max temperature) | Heat output, which sets furnace speed | A hot part |
| Chamber | Heat tolerance | How many items it holds at once | A hot part |
| *Controller* (Open) | – | Fixed at 1 unit | A volume consumer that can be cooked; logic is a separate system |

## 4. Machine properties (the whole blueprint, all calculated)

| Property | Formula | Checked |
|---|---|---|
| Footprint | Tiles occupied | Design |
| Weight | Sum of part weights | Design |
| Leverage | Each tile's weight × its distance to the nearest base tile, summed. Must be ≤ total load capacity | Design |
| Reach | Distance from the base to the furthest tile | Design |
| Tile fill | Units in each tile must be ≤ tile capacity | Design |
| Max temperature | Lowest heat tolerance among its hot parts. The furnace can never run hotter than its own walls survive | Design |
| Running temperature | The lower of max temperature and its current fuel's burn temperature | Run |
| Heat safety | Every component sharing a tile with a hot part must tolerate the max temperature | Design |
| Throughput | Drill: head units. Furnace: burner units. Arm: claws per swing | Run |
| Build cost | Units of each material, totalled | Build |

Distances are in tiles, found by a flood fill (BFS) over the footprint.
When a design fails, the designer highlights the tiles at fault rather than
only rejecting it.

## 5. Manufacturing

1. **Extract:** a drill mines ore if its head is hard enough (§6). Speed
   comes from the head's units.
2. **Process:** a furnace refines ore if it's hot enough (§6). The output is
   processed material.
3. **Shape:** processed material becomes a part at the size the player
   chooses. Cost = units.
4. *Grade* (Open): round processed material into grade bands, using the
   purity tiers in `GAME.md`, so items stack.

## 6. Ore is weaker than refined material

Without this rule hardness can't progress: a hardness-40 drill head could
only mine ore up to 40, and the best head you could make from it would also
be 40.

Ore in the ground is cracked and impure, so:

- **Mining:** a drill head can mine ore up to its hardness ÷ step factor.
  At 0.8, a head of 40 mines ore up to 50.
- **Processing:** working temperature = step factor × the ore's heat
  tolerance. A furnace running at 50 processes ore up to heat tolerance 62.
  Running that hot takes both walls that survive 50 and a fuel that burns
  at 50, so processing is gated twice by one rule.

Every upgrade opens a band about 25% above where you are. The step factor is
the single number that sets how fast the ladder climbs.

It also creates a deliberate chicken-and-egg loop: the best furnace
materials are the hardest to process, so reaching a better furnace always
means building a slightly better furnace first.

## 7. All the rules

| # | When | If | Then | Reach | Checked |
|---|---|---|---|---|---|
| 1 | Drill head on a deposit | Head hardness ≥ step × ore hardness | Mines at head units per cycle | Contact | Run |
| 2 | Ore in a furnace | Running temperature ≥ step × ore heat tolerance | Becomes processed material | Same tile | Run |
| 3 | Claw moves an item | Claw hardness ≥ the item's hardness tier | Moves one item per claw | Contact | Run |
| 4 | Load on the structure | Leverage > load capacity | Design invalid; overloaded tiles highlighted | Machine | Design |
| 5 | Components in a tile | More units than tile capacity | Design invalid | Same tile | Design |
| 6 | Hot part shares a tile | A component there has heat tolerance < max temperature | Design invalid | Same tile | Design |
| 7 | Fuel in a burner | The burner is at or above the fuel's ignition temperature (or the hand spark is, for a cold start) | Fuel is consumed; the furnace runs at its running temperature for reactivity × fuel consumed ticks | Same tile | Run |
| 8 | Reactive component in a hot tile | Max temperature ≥ its ignition temperature | Design invalid | Same tile | Design |

Reach levels: **same tile** (components sharing a tile), **contact**
(touching), **area** (within a radius; unused in the slice), **network**
(connected; simplified to "within one machine").

Rule 3 is the least certain: it gives claws a reason to care about
material, but may be one rule too many for the slice.

## Sanity check against the ladder

With five numbers per mineral, the ladder in `starting-zone.md` can still be
gated by a different one each rung: hardness for mining, heat tolerance and
reactivity for processing (walls and fuel), and strength and density through
which designs you can build.

## Left out of the slice (Open)

- Toughness and wear
- Conductivity and power
- Reactivity in the broader chemical sense (corrosion, reacting with
  neighbours or storage)
- Heat spreading beyond a single tile
- Ground bearing (whether heavy machines need firm ground)
- Vehicles, and weight slowing them down
- Machines sagging or breaking at runtime when overloaded
- Controllers and logic (sensors, signals)
- The weight of carried items
