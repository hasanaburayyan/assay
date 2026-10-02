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


## Every player, as the sim has them: `id`, `name`, `pos`, `target` (or null). READ, NEVER
## INTERPOLATED -- `target` is where the sim is walking them, not permission to draw them part of the
## way there.
func players() -> Array:
	return _sim.players() if _sim != null else []


## Every deposit: `id`, `species`, `center`, `radius`, `amount`, `purity`. Depleted ones are included
## with `amount` 0, because the sim keeps them so ids stay stable.
func deposits() -> Array:
	return _sim.deposits() if _sim != null else []


## Species names in id order, so a deposit's `species` index can be labelled.
func species_names() -> PackedStringArray:
	return _sim.species_names() if _sim != null else PackedStringArray()


## What the last applied bundle caused, as the sim's own `Debug` text. For a log, not a player.
func last_events() -> PackedStringArray:
	return _sim.last_events() if _sim != null else PackedStringArray()


## The same events as sentences, with `me` written as "you". -1 before the relay has stamped us a
## player, which is what `AssayNetClient.player_id` holds until the Welcome.
func event_lines(me: int) -> PackedStringArray:
	return _sim.event_lines(me) if _sim != null else PackedStringArray()


## One player's stacks: `kind`, `species`, `species_name`, `grade` (a LETTER), `count`, and `name`,
## which is the sim's own wording for the item. Empty for a player the world does not have.
func inventory_of(player: int) -> Array:
	return _sim.inventory_of(player) if _sim != null else []


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


## EVERY DESIGN ONE PLAYER HOLDS, for the part menu: the tool in hand first (`index` -1), then the
## built list in the order `Equip` and `PlaceAssembly` index.
##
## `verdict` is the sim's own word and the client may not derive it from the numbers beside it; see
## `designs_of` in the binding for why two renderers forming that opinion is the one disagreement
## lockstep cannot absorb.
func designs_of(player: int) -> Array:
	return _sim.designs_of(player) if _sim != null else []
