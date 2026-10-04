class_name AssaySimHost
extends RefCounted
## THE CLIENT'S COPY OF THE WORLD, RUN BY THE REAL RULES.
##
## A `TickBundle` carries INPUTS, not state, so the world at tick N exists only once something runs
## `sim::step`. That something is the Rust `sim` crate, reached through the `sim-godot` GDExtension --
## never GDScript. A second implementation of the rules would be a second set of rules, and the first
## time the two disagreed this client would be quietly wrong rather than loudly desynced.
##
## THIS FILE IS THE ONLY PLACE IN THE CLIENT THAT TOUCHES `AssaySim`. Everything above it asks here;
## nothing above it may step, mutate, or recompute. What this class adds over the binding is host
## work the binding must not do: deciding when to speak to the relay, and keeping a count a person
## can read.
##
## REACHED THROUGH `ClassDB` ON PURPOSE. Naming `AssaySim` as an identifier when the extension failed
## to load is a PARSE error, which kills this script and every script that preloads it, and Godot
## exits 0 on that. This way a missing library is a sentence in `fail_reason` instead.

## Why there is no world, if there is no world. Empty once `start()` has succeeded.
var fail_reason := ""
## Bundles this host has applied. Not the same as bundles seen on the wire: a bundle for the wrong
## tick is refused, and that difference is the thing worth seeing.
var applied := 0
## Hash reports this host has PRODUCED. Whether they reached the relay is the caller's business and
## the caller's count: a report that was never sent is a report nobody checked.
var hashes_reported := 0

var _sim: Object = null


## Build the world from the relay's `Welcome`, given THE MESSAGE'S OWN TEXT.
##
## Not the parsed Dictionary: Godot's JSON has already turned every number into a double by then, so
## a `u64` seed in it is wrong and would be handed to the sim as if the host had sent it. Returns
## false with `fail_reason` set.
func start(welcome_text: String) -> bool:
	fail_reason = ""
	applied = 0
	hashes_reported = 0
	_sim = null
	if welcome_text == "":
		fail_reason = ("no raw Welcome text, so there is nothing to build a world from. The parsed "
				+ "dictionary is not a substitute: its numbers have been through a double.")
		return false
	if not ClassDB.class_exists("AssaySim"):
		fail_reason = ("the sim binding did not load, so this client cannot know the world at any "
				+ "tick but the one it joined. Build it with `make client-lib`.")
		return false
	var made: Variant = ClassDB.class_call_static("AssaySim", "from_welcome_json", welcome_text)
	if made == null:
		fail_reason = "the sim refused the Welcome snapshot; see the error above this line"
		return false
	_sim = made
	return true


func running() -> bool:
	return _sim != null


## Apply one `Tick` message, from its own text, and say whether a hash is now owed.
##
## Returns "" when nothing should be sent, or the JSON of a `ClientMsg::Hash` for the caller to put
## on the wire. THE MESSAGE IS WRITTEN IN RUST: its `hash` is a `u64` and GDScript's integers are
## signed, so half of all hashes cannot be spelled here at all.
func apply(tick_text: String) -> String:
	if _sim == null or tick_text == "":
		return ""
	if not _sim.apply_bundle_json(tick_text):
		# The binding has already said why. Not fatal here: the relay is the clock, and a refused
		# bundle means we are not where it thinks we are -- which the hash check is what catches.
		return ""
	applied += 1
	if not _sim.hash_due():
		return ""
	hashes_reported += 1
	return String(_sim.hash_message_json())


## The tick this client has actually simulated to. -1 before there is a world, so a caller cannot
## mistake "not started" for tick 0.
func tick() -> int:
	return int(_sim.tick()) if _sim != null else -1


## Our world's state hash, as 16 HEX DIGITS. Text, not a number, because a `u64` hash cannot be
## spelled in GDScript -- this is for showing a person and for comparing two peers by eye.
func hash_hex() -> String:
	return String(_sim.hash_hex()) if _sim != null else ""


## The world's seed, as hex, for the same reason.
func seed_hex() -> String:
	return String(_sim.seed_hex()) if _sim != null else ""


## The seed in decimal, still text. What goes on screen: players and the relay's own command line
## both speak of "world 42", and text is what keeps a full-width seed exact.
func seed_text() -> String:
	return String(_sim.seed_text()) if _sim != null else ""


func size_tiles() -> Vector2i:
	if _sim == null:
		return Vector2i.ZERO
	return Vector2i(int(_sim.width_tiles()), int(_sim.height_tiles()))


func spawn_tile() -> Vector2i:
	return _sim.spawn_tile() if _sim != null else Vector2i.ZERO


## **WHAT THE CLIENT CANNOT DRAW A PLAYER WITHOUT** (ASSA-196, found by Marlow in my file).
##
## The dict below is a BINDING fact read with a default at five places in `main.gd`, and that is the
## `lit` defect of ASSA-141 one level up: a binding that stopped sending `pos` would put every player
## on tile (0, 0) -- one tile off the world's corner, confidently -- and one that stopped sending `id`
## would make every player -1, so `id == player_id` is false and the camera follows nobody.
## `AssayScene.missing_sim_facts` cannot see either, because by the time it looks `main.gd` has
## composed `at`/`facing`/`moving` and all three are present.
##
## **TWO TESTS HANG ON THIS LIST AND THEY PULL IN OPPOSITE DIRECTIONS**, which is the only reason it
## is worth anything (CO-6, and Marlow's ASSA-141 hole: a test that walks a list cannot see a fact
## removed from it). `test_sim_binding.gd` asks a REAL world's `players()` whether every key here is
## present -- that catches the binding dropping one -- and scans `main.gd` for every `player.get("x")`
## read, failing if a key read there is missing from here -- that catches this list going stale. The
## list cannot be both the subject and the oracle.
##
## `name` IS IN THE DICT AND IS DELIBERATELY NOT HERE: nothing in the client reads it, so requiring it
## would be a test about this file's own docstring rather than about anything a player sees.
const PLAYER_FACTS := ["id", "pos", "target"]

## Every player, as the sim has them: `id`, `name`, `pos`, `target` (or null -- the key is always
## there, measured, not assumed). READ, NEVER INTERPOLATED -- `target` is where the sim is walking
## them, not permission to draw them part of the way there.
func players() -> Array:
	return _sim.players() if _sim != null else []


## Every building: `id`, `kind`, `pos` (the TOP-LEFT tile of its footprint), `footprint`, `status`,
## `parts`, `grade`, `species`, `lit`. The list a renderer needs; `tile_at` answers one tile and is
## blind to the half of a 2x2 smelter that falls outside the window.
func buildings() -> Array:
	return _sim.buildings() if _sim != null else []


## Every deposit: `id`, `species`, `center`, `radius`, `amount`, `purity`. Depleted ones are included
## with `amount` 0, because the sim keeps them so ids stay stable.
func deposits() -> Array:
	return _sim.deposits() if _sim != null else []


## Species names in id order, so a deposit's `species` index can be labelled.
func species_names() -> PackedStringArray:
	return _sim.species_names() if _sim != null else PackedStringArray()


## EVERYTHING THE FACTORY OWNS THAT HAS STOPPED AND NEEDS A PERSON (ASSA-94), one worded line per
## building, in the sim's own placement order.
##
## RENDER THESE VERBATIM AND NEVER SORT THEM. The sentence is `sim::debug::halt_lines`, the same one
## `halted` prints in the terminal; re-wording it here would be a second vocabulary for one condition
## (ASSA-43/52). The order is the sim's because which stopped machine matters most depends on what
## the player is doing next, which this side cannot know.
##
## THE COUNT IS `size()`. There is deliberately no second field carrying it: the Game Director ruled
## the total must never truncate while the reasons are bounded by the column's height, and two copies
## of one quantity are free to disagree.
##
## EMPTY IS THE HEALTHY STATE AND DRAWS NOTHING. A surface that said "0 stopped" would cry wolf the
## way `idle: nothing to refine` would.
func halt_lines() -> PackedStringArray:
	return _sim.halt_lines() if _sim != null else PackedStringArray()


## EVERY ACTIVITY ONE PLAYER HAS RUNNING (ASSA-95), one worded line each, in `step`'s own system
## order: hand mining, assaying, hand crafting. Empty when nothing is running, which is most ticks.
##
## RENDER THESE VERBATIM, NEVER SORT THEM AND NEVER CAP THEM — the same three rules `halt_lines`
## above is under, for the same reason. The list is PLURAL by construction: `step` never clears
## `mining` when an assay starts, so a player stands on a deposit and mines through their own assay,
## and a surface showing only one of them would say the other had stopped.
##
## A COUNTDOWN ONLY WHERE THERE IS AN END. The assay counts down and the craft says its own words;
## mining carries no number, because its cycle restarts until you stop or the deposit runs dry. The
## absence is the fact, and this side must not supply one.
func activity_lines(player: int) -> PackedStringArray:
	return _sim.activity_lines(player) if _sim != null else PackedStringArray()


## What the last applied bundle caused, as the sim's own `Debug` text. For a log, not a player.
func last_events() -> PackedStringArray:
	return _sim.last_events() if _sim != null else PackedStringArray()


## The same events as sentences, with `me` written as "you". -1 before the relay has stamped us a
## player, which is what `AssayNetClient.player_id` holds until the Welcome.
func event_lines(me: int) -> PackedStringArray:
	return _sim.event_lines(me) if _sim != null else PackedStringArray()


## The ones this player must see with the log hidden (ASSA-89): the same sentences, word for word,
## filtered by `sim::debug::event_needs_attention`. A subset of `event_lines`, never a rewording --
## which is why the client never decides for itself how loud a line is.
func attention_lines(me: int) -> PackedStringArray:
	return _sim.attention_lines(me) if _sim != null else PackedStringArray()


## One player's stacks: `kind`, `species`, `species_name`, `grade` (a LETTER), `count`, and `name`,
## which is the sim's own wording for the item. Empty for a player the world does not have.
func inventory_of(player: int) -> Array:
	return _sim.inventory_of(player) if _sim != null else []


## THE CRAFTING MENU'S ROWS (ASSA-88): `line` (the sim's sentence), `dead_end`, `verb` (which
## command, `craft` or `make`), `tag` (that catalogue's own wire tag) and the input stack's `kind`,
## `species`, `grade`, `count` -- spelled exactly as `inventory_of` spells them, so one
## `item_of_stack` serves both.
##
## ONE OFFER PER CATALOGUE ROW PER MATERIAL, IN THE SIM'S ORDER, AND THE CLIENT NEITHER FILTERS NOR
## SORTS. The sentence names the OUTPUT item and its grade is a rule, not an echo of the input: `sort`
## makes one grade better and makes nothing at all out of grade A.
func make_offers(player: int) -> Array:
	return _sim.make_offers(player) if _sim != null else []


## Everything on one tile: `in_bounds`, `pos`, `chunk`, `chunks_from_spawn`, `is_spawn`, `deposit`
## (null or a dictionary), `building` (null or a dictionary), `players_here`.
##
## THE SIM DECIDES ALL OF IT, including which deposit covers the tile and what grade a purity is.
func tile_at(at: Vector2i) -> Dictionary:
	return _sim.tile_at(at) if _sim != null else {}


## Every species as the players know it: `id`, `name`, `assayed`, `readings` (property name to the
## exact value or the sim's band, as TEXT), `hand_minable`, `hand_lit_fuel`.
func species_sheets() -> Array:
	return _sim.species_sheets() if _sim != null else []


## `[material, fuel]` species ids: the pair this world GUARANTEES can be mined and smelted, from
## `sim::ladder::starter_species`. Empty if the roster has none, which worldgen rerolls to prevent.
##
## A SCRIPTED SESSION MAY NOT CHOOSE ITS OWN FUEL. Whether a fuel gets hot enough to melt an ore is a
## rule in reactivity and heat tolerance, and before an assay the only sheet a client has is a
## 25-wide band -- so choosing would be guessing and calling it a plan. THE TWO MAY BE THE SAME
## SPECIES; nothing in the sim stops one species being both.
func starter_pair() -> PackedInt32Array:
	return _sim.starter_pair() if _sim != null else PackedInt32Array()


## ONE ITEM AS THE JSON A COMMAND CARRIES, spelled by serde. `kind` is the sim's own item name
## (`ore`, `refined`, `smelter`, `head`, `handle`, `frame`, `hopper`); `grade` a letter. Empty string
## if either will not parse.
##
## Static on the Rust side, so this does not need a world -- and this file stays the only one that
## names `AssaySim`. Used by a TEST, to hold the dictionaries `AssayDemoPlan` builds against what
## serde would have written; the probe sends the dictionaries, because parsing this text in GDScript
## would turn every number into a double and serde will not take `3.0` for a `u8`.
static func item_json(kind: String, species: int, grade: String) -> String:
	if not ClassDB.class_exists("AssaySim"):
		return ""
	return String(ClassDB.class_call_static("AssaySim", "item_json", kind, species, grade))


## SERDE'S VERDICT ON JSON A CLIENT WROTE FOR AN ITEM: its own spelling of what it read, or "" if it
## refuses. For the test above -- comparing the two as PARSED values is not enough, because Godot
## parses `3` and `3.0` back to the same double and serde refuses the second.
static func item_echo(text: String) -> String:
	if not ClassDB.class_exists("AssaySim"):
		return ""
	return String(ClassDB.class_call_static("AssaySim", "item_echo", text))


## THE SAME VERDICT FOR A WHOLE `PlayerCommand`, which is what a BUTTON sends (ASSA-37).
##
## Every command this client can send is built in GDScript by `AssayActions`, and the only thing that
## can tell a correct shape from a plausible one is the deserialiser that will actually read it.
## `tests/test_actions.gd` puts every builder through here. Two of my own mistakes are why: a unit
## variant written as `{"Stop": {}}`, which a relay drops without a word, and `species: 3.0`, which
## Godot and serde disagree about.
static func command_echo(command: Variant) -> String:
	if not ClassDB.class_exists("AssaySim"):
		return ""
	return String(ClassDB.class_call_static("AssaySim", "command_echo", JSON.stringify(command)))


## THE SIM'S OWN PART CATALOGUE: `name`, `size` and `tag`, in `PartKind::ALL` order.
##
## So the client's "make a part" buttons are the sim's list and not four strings typed in here. ADR
## 0003's consequence is that a new part kind needs no recipe, and a client with its own copy of the
## catalogue would be the one place that still had to be edited.
static func part_kinds() -> Array:
	if not ClassDB.class_exists("AssaySim"):
		return []
	return ClassDB.class_call_static("AssaySim", "part_kinds")


## THE SIM'S OWN RECIPE TABLE: `name`, `tag`, `input`, `input_count`, `hand`. A Craft button only
## belongs on a stack whose kind is some recipe's `input`, and only for a recipe a player's own hands
## can make -- `Refine` and `Resmelt` happen inside a smelter and are nobody's button.
static func recipes() -> Array:
	if not ClassDB.class_exists("AssaySim"):
		return []
	return ClassDB.class_call_static("AssaySim", "recipes")


## **WOULD THE SIM REFUSE THIS PRESS, IN THE SIM'S OWN SENTENCE** -- or `""` when it would not
## (ASSA-102's `AssemblyError::is_unfinished` lives behind this, so a design that is merely half
## built answers `""` and the player is not told off for being part-way).
##
## `chosen` is the kinds already picked IN PRESS ORDER, the first being the frame; `candidate` is the
## kind of the row being pressed. Kind names, which is what `inventory_of` already hands over -- no
## material crosses, because whether a press is legal is a question about the catalogue and not about
## the rock.
##
## `""` WITH NO BINDING AT ALL, which is the same answer as "no refusal". That is the right way round
## here: without `AssaySim` there is no world, no pack and nothing to press, so a sentence invented
## in this file would be a refusal nobody could have earned.
static func part_press_refusal(chosen: PackedStringArray, candidate: String) -> String:
	if not ClassDB.class_exists("AssaySim"):
		return ""
	return String(ClassDB.class_call_static("AssaySim", "part_press_refusal", chosen, candidate))


## The wire tag for one part kind by name, as serde spells it: `"Head"`, or `{"Frame": "Held"}` for a
## handle. THE NAME ITSELF when the catalogue has no such kind, so the command is refused by name
## rather than quietly becoming another part.
static func part_tag(name: String) -> Variant:
	return _tag_in(part_kinds(), name)


## The wire tag for one recipe by name (`"smelter"` -> `"Smelter"`). The case differs, which is
## exactly the kind of thing a client should not be guessing at.
static func recipe_tag(name: String) -> Variant:
	return _tag_in(recipes(), name)


static func _tag_in(catalogue: Array, name: String) -> Variant:
	for entry in catalogue:
		var row: Dictionary = entry
		if String(row.get("name", "")) == name:
			return row.get("tag", name)
	return name


## HOW MANY TILES A PLACED ITEM WOULD COVER, or (0, 0) for an item that is not placeable. For saying
## which tiles a click just chose; it decides nothing -- `sim::step` owns whether a placement is legal
## and this client never asks first (Maren's ruling: never refuse).
static func footprint_of_item(kind: String, species: int, grade: String) -> Vector2i:
	if not ClassDB.class_exists("AssaySim"):
		return Vector2i.ZERO
	return ClassDB.class_call_static("AssaySim", "footprint_of_item", kind, species, grade)


## A RELAY-SHAPED `Welcome` FOR A FRESH WORLD, for tests and offline tools only.
##
## Not a second way to play and not a single-player mode: there is no clock behind it, so a caller
## has to write its own tick bundles, which is exactly what `tools/button_session.gd` does. It exists
## because the client's headless suite had no world at all -- every HUD test ran against dictionaries
## I had typed out myself, which is the failure I keep repeating in new costumes: my test agrees with
## my bug because I wrote both from the same assumption.
static func fresh_welcome_json(world_seed: String, player_name: String) -> String:
	if not ClassDB.class_exists("AssaySim"):
		return ""
	return String(ClassDB.class_call_static("AssaySim", "fresh_welcome_json", world_seed,
			player_name))


## EVERY DESIGN ONE PLAYER HOLDS, for the part menu: the tool in hand first (`index` -1), then the
## built list in the order `Equip` and `PlaceAssembly` index.
##
## `verdict` is the sim's own word and the client may not derive it from the numbers beside it; see
## `designs_of` in the binding for why two renderers forming that opinion is the one disagreement
## lockstep cannot absorb.
func designs_of(player: int) -> Array:
	return _sim.designs_of(player) if _sim != null else []


## **A COUNT AND ITS NOUN, AGREEING** (ASSA-145). `sim::debug::counted`, so the window and `sim-cli`
## cannot drift on a sentence a player reads: "1 player" and "2 players" from one rule.
##
## STATIC AND WORLDLESS, unlike everything else here, because the counts that needed it are the
## HOST's -- players, bundles applied, hashes reported -- and a client must be able to say them
## before it has a world.
static func counted(n: int, one: String, many: String) -> String:
	return AssaySim.counted(n, one, many)


## **WHAT THE SIM WOULD SAY ABOUT A DESIGN NOBODY HAS BUILT YET**: `verdict` (its own word),
## `fault` (its own phrase when the rules refuse the design, "" otherwise) and the four numbers
## `designs_of` returns. `frame` and `mounted` are `PartKind` names -- "frame", "handle", "head",
## "hopper" -- and every part is made of one species at one grade.
##
## The verdict is still the sim's and still may not be derived here; see `designs_of` above. This
## asks about a design that does not exist, which is the one question that list cannot answer, and
## the caller is `tools/button_play.gd`: the scripted run has to know which drill THIS world carries
## before it spends 500 ticks mining for one (ASSA-140).
func design_if_built(frame: String, mounted: PackedStringArray, species: int, grade: String) -> Dictionary:
	return _sim.design_if_built(frame, mounted, species, grade) if _sim != null else {}


## WHAT THIS PLAYER IS CRAFTING, in the sim's own sentence, or "" when nothing is (ASSA-49).
##
## The wording is `sim::debug::crafting_readout`, shared with `sim-cli` for the same reason
## `durability_readout` is: two hosts wording one number is the disagreement nobody notices. This
## client may put a label in front of the sentence and may not rewrite it, and it certainly may not
## work the ticks out for itself -- `Crafting` holds `progress`, and turning that into "ticks left"
## needs the recipe's cost, which is a rule.
func crafting_line(player: int) -> String:
	return String(_sim.crafting_line(player)) if _sim != null else ""
