class_name AssayActions
extends RefCounted
## EVERY COMMAND THIS CLIENT CAN SEND, IN ONE PLACE, AND NOTHING ELSE.
##
## A `PlayerCommand` is the only way a client changes a world (repo `CLAUDE.md` principle 1), so the
## shape of one is the whole surface between this client and the rules. Before ASSA-37 that surface
## was spread across `main.gd`'s map click and twenty dictionary literals inside
## `tools/lockstep_probe.gd`, which was tolerable only while the probe was the sole thing that could
## act. Now a person at the window presses buttons, and TWO SPELLINGS OF ONE COMMAND IS THE ONE
## DISAGREEMENT NOBODY WOULD NOTICE: the probe would keep passing and the button would be dropped by
## the relay in silence.
##
## So the probe and the buttons call the same builders. "No client-only command path" (ASSA-37's
## fifth box) is then true by construction rather than by a test that has to remember to check.
##
## WHAT THIS FILE MAY NOT DO:
##  - DECIDE ANYTHING. It does not ask whether a command is legal, affordable, in reach, or whether a
##    design is over budget. `sim::step` validates every command on every peer, which is what makes
##    cheating self-defeating (`sim-game/CLAUDE.md`), and a client that refused first would be a
##    second opinion. Maren's ruling on ASSA-5/7 says the same thing from the design side: never
##    disable Place, never refuse an over-budget design.
##  - INVENT AN ITEM. Every item that goes out came back out of `inventory_of`, `starter_pair` or the
##    sim's own catalogue (`AssaySim.part_kinds`, `AssaySim.recipes`). `item_of_stack` rearranges
##    three fields the sim named; it never works out what we are carrying.
##
## THE SHAPES ARE SERDE'S, AND THEY ARE NOT GUESSED AT. `sim`'s enums are externally tagged, so a
## variant with fields is a one-key object (`{"Equip": {"assembly": 0}}`) and A UNIT VARIANT IS THE
## BARE NAME (`"Mine"`, not `{"Mine": {}}`). I shipped that second one wrong: `{"Stop": {}}` was
## refused by serde, which left a demo world mining itself to death while the probe reported success.
## `AssaySim.command_echo` now runs each of these through the deserialiser that will actually read
## it, and `tests/test_actions.gd` holds every builder below against it.
##
## AND THE NUMBERS STAY INTEGERS. GDScript builds these dictionaries and `JSON.stringify` writes
## them, which keeps `3` as `3`; parsing a command back would turn it into `3.0`, and serde will not
## take a float for a `u8`. That is why no builder here round-trips its own text.

## The slots a player can put things INTO (`sim::building::Slot`). `Output` is deliberately absent:
## taking from it is `take()`, and offering an insert into an output slot would be a button whose only
## possible outcome is a rejection. Held against serde by `tests/test_actions.gd`.
const SLOT_FUEL := "Fuel"
const SLOT_INPUT := "Input"


## Start mining the deposit under you. REPEATS until something stops it -- there is no "mine once",
## and a demo world I left running wore a pick to nothing because of it.
static func mine() -> Variant:
	return "Mine"


## Stop walking, mining, crafting and assaying. A BARE STRING: see this file's header.
static func stop() -> Variant:
	return "Stop"


## Study the deposit under you until its species reads exact instead of in 25-wide bands.
static func assay() -> Variant:
	return "Assay"


## Put the tool in hand back on the built list.
static func unequip() -> Variant:
	return "Unequip"


## Walk toward a tile, one tile per tick. NOTHING MOVES WHEN THIS IS SENT: the player moves when a
## bundle carrying it comes back around and the sim steps.
static func move_to(tile: Vector2i) -> Variant:
	return {"MoveTo": {"target": _tile(tile)}}


## Hand-craft `count` batches of a recipe from a stack we hold. `recipe` is the sim's own wire tag
## (`AssaySim.recipes()[i].tag`), never a name this client capitalised.
static func craft(recipe: Variant, item: Dictionary, count: int) -> Variant:
	return {"Craft": {"recipe": recipe, "item": item, "count": count}}


## Put a building item on the map with its TOP-LEFT tile at `tile`.
static func place(item: Dictionary, tile: Vector2i) -> Variant:
	return {"Place": {"item": item, "pos": _tile(tile)}}


## Move items from the pack into one of a building's slots. `slot` is `SLOT_FUEL` or `SLOT_INPUT`.
static func insert(building: int, slot: String, item: Dictionary, count: int) -> Variant:
	return {"Insert": {"building": building, "slot": slot, "item": item, "count": count}}


## Empty a building's output slot into the pack.
static func take(building: int) -> Variant:
	return {"Take": {"building": building}}


## Pick a building back up, with whatever is inside it.
static func pickup(building: int) -> Variant:
	return {"Pickup": {"building": building}}


## Make `count` parts of one kind out of refined material. `kind` is the sim's own wire tag
## (`AssaySim.part_kinds()[i].tag`) -- a bare `"Head"` or a nested `{"Frame": "Held"}`, and the
## difference is why this client must not spell it itself.
static func make_part(kind: Variant, material: Dictionary, count: int) -> Variant:
	return {"MakePart": {"kind": kind, "material": material, "count": count}}


## Build a machine: a frame item, plus the parts mounted on it. REJECTED ONLY FOR PARTS THAT DO NOT
## FIT -- never for being overweight, which is tested at placement instead (sim decision 11).
static func assemble(frame: Dictionary, mounted: Array) -> Variant:
	return {"Assemble": {"frame": frame, "mounted": mounted}}


## Take a built held design into your hands. `assembly` indexes the player's built list, which is the
## `index` `designs_of` reports -- not the row's position on screen, because the tool in hand is a row
## with no index of its own.
static func equip(assembly: int) -> Variant:
	return {"Equip": {"assembly": assembly}}


## Plant a built design on the map. WHERE MASS IS TESTED (sim decision 11): an over-budget design
## breaks here instead of being refused, which is the whole reason the Place button is never
## disabled.
static func place_assembly(assembly: int, tile: Vector2i) -> Variant:
	return {"PlaceAssembly": {"assembly": assembly, "pos": _tile(tile)}}


## A `TilePos`, which is a plain struct of two integers.
static func _tile(tile: Vector2i) -> Dictionary:
	return {"x": tile.x, "y": tile.y}


## An item descriptor in the shape serde reads an `Item` from. The keys are in the order the Rust
## struct declares them, which costs nothing and makes the two texts comparable by eye.
static func item(kind: String, species: int, grade: String) -> Dictionary:
	return {"kind": _kind_tag(kind), "species": species, "grade": grade.to_upper()}


## The item a stack from `inventory_of` IS, ready to be sent back. THE SIM NAMED ALL THREE FIELDS;
## this only rearranges them.
static func item_of_stack(stack: Dictionary) -> Dictionary:
	return item(String(stack.get("kind", "")), int(stack.get("species", -1)),
			String(stack.get("grade", "C")))


## HOW MANY OF ONE ITEM A PLAYER IS CARRYING, summed over the stacks `inventory_of` handed back.
##
## It lives here rather than in `hud.gd` because the number is a COMMAND ARGUMENT -- `insert`, `craft`
## and `make_part` all take a count, and the stack it is counted from is the same stack
## `item_of_stack` is reading one function above. `hud.gd`'s charter is words and colours, and a bare
## integer is neither.
##
## It decides nothing, which is this file's rule: it sums a column the sim gave us. Grade is part of
## the question on purpose -- two grades of one ore are two stacks and two rows on screen, so counting
## without it would send the other row's number.
##
## IT USED TO LIVE IN `tools/demo_plan.gd`, AND THAT IS WHAT BROKE MAIN. `main.gd` called
## `AssayDemoPlan.held`, the export preset excludes `tools/*`, so the shipped `main.gd` referenced a
## class that was not in the pack: it failed to PARSE, `_ready` never ran, the self-check never fired,
## nothing ever called `quit()`, and the exported client sat in the platform event loop until CI's
## timeout. `tools/demo_plan.gd` now calls this, so there is still one definition.
static func held_count(stacks: Array, kind: String, species: int, grade: String = "") -> int:
	var total := 0
	for entry in stacks:
		var stack: Dictionary = entry
		if String(stack.get("kind", "")) != kind:
			continue
		if int(stack.get("species", -1)) != species:
			continue
		if grade != "" and String(stack.get("grade", "")).to_upper() != grade.to_upper():
			continue
		total += int(stack.get("count", 0))
	return total


## `ItemKind` as serde tags it: a bare string for the plain kinds, and a nest for a part, because
## `ItemKind::Part(PartKind)` and `PartKind::Frame(Mount)` are each an enum carrying an enum.
##
## An unknown kind is returned UNCHANGED rather than guessed at. It will not parse on the sim's side,
## so the command is refused by name instead of being quietly turned into some other item.
static func _kind_tag(kind: String) -> Variant:
	match kind.to_lower():
		"ore":
			return "Ore"
		"refined":
			return "Refined"
		"gear":
			return "Gear"
		"smelter":
			return "Smelter"
		"head", "hopper", "handle", "frame":
			# ONE SOURCE for the part tag, so an item and a `MakePart` can never disagree about what
			# a handle is.
			return {"Part": part_kind_tag(kind)}
		_:
			return kind


## `PartKind` as serde tags it, BY NAME, for the one caller that has a name and not the sim's tag:
## `item()` above, which is handed a stack's `kind` string.
##
## THE SIM IS STILL THE AUTHORITY. `AssaySim.part_kinds()` hands over serde's own tag as a Variant
## and that is what a `MakePart` button carries; this table exists because an ITEM's kind arrives as
## a word out of `inventory_of`. `tests/test_actions.gd` holds the two against each other, so a
## catalogue change in Rust fails here rather than on the wire.
static func part_kind_tag(kind: String) -> Variant:
	match kind.to_lower():
		"head":
			return "Head"
		"hopper":
			return "Hopper"
		"handle":
			return {"Frame": "Held"}
		"frame":
			return {"Frame": "Planted"}
		_:
			return kind
