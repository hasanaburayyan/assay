//! The Godot client's host for the real simulation.
//!
//! WHY THIS CRATE EXISTS. A `TickBundle` carries *inputs*, not state, so the
//! world at tick N only exists if something runs `sim::step`. GDScript must
//! not be that something: a second implementation of the rules would be a
//! second set of rules, and the first time the two disagreed the client would
//! be quietly wrong rather than loudly desynced. So the Godot client runs the
//! same Rust `sim` every other peer runs, through this binding.
//!
//! WHAT THIS CRATE IS. A host, exactly like `sim-cli` and `sim-relay`: it
//! owns no rules. It deserialises a world, hands inputs to `sim::step`, and
//! reads values back out. `sim/Cargo.toml` has no `godot` dependency and must
//! never grow one — the arrow points this way and only this way.
//!
//! THE NUMBER TRAP, measured and not theoretical. Godot's JSON parses every
//! number as a double. A world seed of 777001 came back as `777001.0`, which
//! is harmless, but a full-width `u64` seed rounds and **a `u64` state hash
//! cannot be spelled in GDScript at all** (its ints are signed 64-bit). So
//! every hash and seed crosses this boundary as HEX TEXT and is compared as
//! text. There is deliberately no method here that returns a hash as a number.

use godot::prelude::*;
use sim::assembly::{Assembly, Built, Mount, PartKind};
use sim::building::BuildingId;
use sim::command::{Event, Input};
use sim::hash::fnv64;
use sim::item::{Item, ItemKind};
use sim::mineral::{Property, SpeciesId};
use sim::types::{PlayerId, TilePos};
use sim::world::{CHUNK_SIZE, World, WorldConfig};
use sim_net::{ClientMsg, HASH_EVERY, PROTOCOL_VERSION, TickBundle};

struct SimGodot;

#[gdextension]
unsafe impl ExtensionLibrary for SimGodot {}

/// One world, stepped by the real rules.
///
/// GDScript may submit commands and read values; it may not reach in and
/// change the world, because every method that mutates goes through
/// `sim::step`.
#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct AssaySim {
    world: World,
    /// What the last `apply_bundle_json` reported, so a client can show it.
    /// Kept as `Event`s rather than strings because the same event has to be
    /// readable two ways — `{event:?}` for a log and a sentence for a player.
    last_events: Vec<Event>,
}

#[godot_api]
impl AssaySim {
    /// Build a world from the relay's `Welcome` snapshot.
    ///
    /// Takes the whole `ServerMsg` as text, so GDScript never has to know how
    /// `serde` tags an enum. Returns null on anything it cannot read, having
    /// pushed a Godot error: a client that silently accepted a half-world
    /// would desync later and blame the network.
    #[func]
    pub fn from_welcome_json(text: GString) -> Option<Gd<Self>> {
        match Self::world_from_welcome(&text.to_string()) {
            Ok(world) => Some(Gd::from_object(Self {
                world,
                last_events: Vec::new(),
            })),
            Err(why) => {
                godot_error!("sim-godot: could not read the Welcome snapshot: {why}");
                None
            }
        }
    }

    /// Apply one `Tick` message: its inputs, then one `step`.
    ///
    /// Takes the WHOLE `ServerMsg` text, exactly as it came off the socket, for
    /// the same two reasons as `from_welcome_json`: GDScript never has to know
    /// how serde tags an enum, and a re-serialised Godot Dictionary would have
    /// been through a double already.
    ///
    /// Returns false and changes nothing unless the bundle is numbered with the
    /// tick we are AT. Applying bundles out of order is precisely how a peer
    /// desyncs, so this refuses rather than guesses.
    #[func]
    pub fn apply_bundle_json(&mut self, text: GString) -> bool {
        match Self::bundle_from_tick(&text.to_string()) {
            Ok(bundle) => self.apply_bundle(&bundle),
            Err(why) => {
                godot_error!("sim-godot: could not read a Tick message: {why}");
                false
            }
        }
    }

    /// The world's tick. Safe as a number: ticks stay far inside 2^53.
    #[func]
    pub fn tick(&self) -> i64 {
        self.world.tick as i64
    }

    /// The state hash, as 16 hex digits.
    ///
    /// TEXT, NOT A NUMBER, and the reason is in this file's header. This is
    /// what a `Hash` message reports and what proves two peers agree.
    #[func]
    pub fn hash_hex(&self) -> GString {
        gstring(&self.hash_hex_string())
    }

    /// The seed as hex text, for the same reason as the hash: a `u64` seed
    /// above 2^53 does not survive a GDScript number.
    #[func]
    pub fn seed_hex(&self) -> GString {
        gstring(&self.seed_hex_string())
    }

    /// The seed in DECIMAL, still text. Players and the relay's command line
    /// both speak of "world 42", so hex would be a worse thing to put on
    /// screen; text is what keeps it exact.
    #[func]
    pub fn seed_text(&self) -> GString {
        gstring(&self.seed_decimal_string())
    }

    #[func]
    pub fn width_tiles(&self) -> i64 {
        self.world.width_chunks as i64 * CHUNK_SIZE as i64
    }

    #[func]
    pub fn height_tiles(&self) -> i64 {
        self.world.height_chunks as i64 * CHUNK_SIZE as i64
    }

    #[func]
    pub fn player_count(&self) -> i64 {
        self.world.players.len() as i64
    }

    /// The tile players spawn on, which is the centre of the spawn chunk. The
    /// sim works this out; a client that multiplied chunk by 16 itself would be
    /// a second opinion about where spawn is.
    #[func]
    pub fn spawn_tile(&self) -> Vector2i {
        let at = self.world.spawn_tile();
        Vector2i::new(at.x, at.y)
    }

    /// What the last applied bundle caused, as the sim's own `Debug` text. A
    /// log line for an engineer; `event_lines` is the one for a player.
    #[func]
    pub fn last_events(&self) -> PackedStringArray {
        self.world_events()
    }

    /// The same events as sentences, with `me` written as "you".
    ///
    /// -1 means "no player yet", which is what a client has before its
    /// `Welcome`.
    ///
    /// **THE WORDING DOES NOT LIVE HERE AND THIS COMMENT SAID IT DID.** It
    /// read "wording lives here, in a host, because presentation is a host's
    /// job … if the two ever have to agree word for word, the fix is one
    /// describer in `sim::debug`". That consolidation has already happened:
    /// `describe` is a one-line delegation to `sim::debug::event_line`, and
    /// the test module below says so outright — "this crate no longer matches
    /// on `Event`". So the sentence described a shape that had been replaced,
    /// which is ASSA-174's lesson with no constant to catch it.
    ///
    /// WHAT IS TRUE NOW: `sim::debug::event_line` is the one describer, and
    /// `sim-cli`'s `describe_event` wraps it to add typed-command hints this
    /// client has no use for. **One consequence is a live defect** — that
    /// describer serves a typed client, where a `BuildingId` is the handle you
    /// pass to `take`/`pickup`, and this window, where "building 0" is an
    /// index a player can do nothing with (ASSA-222).
    #[func]
    pub fn event_lines(&self, me: i64) -> PackedStringArray {
        self.last_events
            .iter()
            .map(|event| gstring(&self.describe(player_id_of(me), event)))
            .collect()
    }

    /// THE LINES THIS PLAYER MUST SEE WITH THE LOG HIDDEN (ASSA-89): the
    /// subset of `event_lines` that reports something which did not happen,
    /// stopped happening, or was lost.
    ///
    /// A SUBSET BY CONSTRUCTION, NOT BY AGREEMENT. Both functions map the same
    /// `self.last_events` through the same `self.describe`, so a line here is
    /// the same string, word for word, as the one in the log — there is no
    /// second wording to drift. The only thing added is the filter, and
    /// `sim::debug::event_needs_attention` owns that, for the reason the
    /// wording itself lives in the sim: the alternative is the client deciding
    /// how loud a sentence is by matching its text, which goes quiet the next
    /// time anybody rewords one.
    ///
    /// WHY THE CLIENT NEEDS THIS AT ALL: the board's complaint was "logs are
    /// hard on the eyes", so the log is hidden by default now, and a hidden
    /// log may not swallow the only sentence that explains why the button you
    /// pressed did nothing.
    #[func]
    pub fn attention_lines(&self, me: i64) -> PackedStringArray {
        self.attention_pairs(player_id_of(me))
            .iter()
            .map(|(line, _)| gstring(line))
            .collect()
    }

    /// **WHAT EACH ATTENTION LINE IS ABOUT** — the building of a CONDITION, or
    /// `-1` for an ACT (ASSA-300, the Game Director's §300 ruling: *"a sentence
    /// about a condition comes down when the condition does; a sentence about
    /// an act does not"*).
    ///
    /// Element `i` belongs to element `i` of [`AssaySim::attention_lines`], and
    /// **the pairing is by construction**: both are one `attention_pairs` call,
    /// so there is no second filter to drift and no way for a line and its kind
    /// to come from different events. A host still asks for them separately
    /// because a `Dictionary` field is invisible to Rust (ASSA-105), and the
    /// kind is exactly the field whose silence would reinstate this bug.
    ///
    /// **`-1` IS THE SAFE ANSWER AND THAT IS WHY IT IS THE ACT.** A host that
    /// reads past the end of this array gets `0` out of GDScript, and `0` must
    /// not mean "a condition about building 0" — that would let a *refusal*
    /// fade, which ASSA-239 calls the one class of sentence a player cannot
    /// recover. The out-of-range answer has to be "never take it down".
    ///
    /// The id is a handle and not an address: the only thing a host may do with
    /// it is ask [`AssaySim::is_halted`] whether the condition still holds. It
    /// is deliberately not the tile, the kind or the state — `halt_lines` was
    /// made a list of sentences rather than rows precisely so nothing in
    /// `hud.gd` could compose a sentence out of parts, and the Game Director
    /// restated it on this item: *"the toast's sentence stays the sim's"*.
    #[func]
    pub fn attention_conditions(&self, me: i64) -> PackedInt64Array {
        self.attention_pairs(player_id_of(me))
            .iter()
            .map(|(_, about)| about.map_or(-1, |id| i64::from(id.0)))
            .collect()
    }

    /// **IS THIS BUILDING STILL STOPPED?** `World::halted`, asked about one
    /// building instead of listed (ASSA-300).
    ///
    /// The question a host has to be able to ask on any later tick, because the
    /// stall EVENT is an edge — `announce_new_stalls` fires once on the way in
    /// and says nothing while the stall sits — so a sentence said from that
    /// event has no way of knowing it has stopped being true. Before this, the
    /// Godot client had none: `the Tonore smelter (A) stopped: no fuel` stayed
    /// over the world after the smelter was refuelled, while the pinned count
    /// beside it had already dropped to zero.
    ///
    /// **THE SAME PREDICATE THE PINNED BLOCK IS BUILT FROM**, which is what
    /// makes the toast and the count unable to disagree about whether anything
    /// is stopped (ASSA-300 box 6): `halt_lines` is `World::halted` worded, and
    /// this is `World::halted` asked. A finer question — *is it still in the
    /// stall it reported* — would let the toast go down while that building was
    /// still in the block, so this is the coarser one on purpose.
    ///
    /// An unknown id answers `false`: a building that no longer exists is not
    /// stopped, and a picked-up machine's sentence should go.
    #[func]
    pub fn is_halted(&self, building: i64) -> bool {
        self.world.halted().any(|b| i64::from(b.id.0) == building)
    }

    /// **EVERYTHING THAT HAS STOPPED AND NEEDS A PERSON**, one worded line per
    /// building, in the sim's own placement order (ASSA-94).
    ///
    /// `sim::debug::halt_lines` verbatim — the same sentences `halted` prints
    /// in `sim-cli`, which is the point: the window and the terminal report a
    /// stall in one vocabulary or they are two vocabularies (ASSA-43/52).
    ///
    /// **LINES AND NOT ROWS, AND THE SYSTEMS ENGINEER'S REASON IS THE RIGHT
    /// ONE.** I had written this as an array of building dictionaries — id,
    /// kind, pos, state, halted — so that a map marker could have the tile. He
    /// asked for lines instead: the moment a host is handed an address and a
    /// condition separately, something in `hud.gd` starts composing a sentence
    /// out of them, which is exactly how `design_lines` grew the defect ASSA-90
    /// had to fix. A future panel that wants to put the camera on a halted
    /// building can ask for the tile then, as a field somebody actually reads.
    ///
    /// The rows version was also unguardable from here. A Variant field is
    /// invisible to Rust — inverting `is_frame` in `part_kinds()` left all 40
    /// tests in this crate green (ASSA-105) — so `pos` and `halted` would have
    /// shipped unchecked until a `.gd` test read them, and a host that rendered
    /// only `state` would never have read them at all.
    ///
    /// **THE COUNT IS `size()` AND THERE IS NO SECOND COPY OF IT.** The Game
    /// Director ruled that the total never truncates while the reasons are
    /// bounded by the column's height; a `halted_count()` beside this would be
    /// the same quantity twice, free to disagree the moment one was filtered.
    ///
    /// **EMPTY IS THE NORMAL STATE OF A WORKING FACTORY.** Nothing here says
    /// "0 stopped" — that is the cry-wolf failure one step removed — and a
    /// smelter's `idle: nothing to refine` is absent by the same rule, because
    /// it follows every finished batch and asks nobody for anything.
    ///
    /// **ORDER IS THE SIM'S AND MUST NOT BE SORTED.** Which stopped machine
    /// matters most depends on what the player is doing next, which no host
    /// knows; placement order is stable, so a line does not reshuffle itself as
    /// states change underneath it.
    #[func]
    pub fn halt_lines(&self) -> PackedStringArray {
        packed(&self.halt_line_texts())
    }

    /// **HOW MANY OF THEM THERE ARE, IN THE SIM'S WORDS** — `"3 of 5 buildings
    /// stopped"`, or `""` when nothing has (ASSA-94).
    ///
    /// `sim::debug::halt_summary` verbatim, which is also `halted`'s first line
    /// in `sim-cli`. The Game Director's ruling is that the count is the floor
    /// of this surface and the reasons are the extra: space bounds how many
    /// reasons fit, and nothing bounds the number. A player who reads "3 stopped"
    /// and can see one reason knows there are two more to find.
    ///
    /// **THIS EXISTS BECAUSE THE WINDOW WAS RIGHT TO REFUSE TO COUNT.** `main.gd`
    /// declined a count in a comment — *"a count would be a second claim about
    /// the world and the sim already makes it"* — and the objection is correct;
    /// the conclusion was not. A client counting `halt_lines().size()` would be
    /// a second claim, and would have to be kept true. Reading the sentence the
    /// sim already composes is not.
    ///
    /// **EMPTY IS THE INSTRUCTION, NOT A MISSING VALUE.** "0 of 2 buildings
    /// stopped" is the cry-wolf failure one step removed, so there is no number
    /// here to render in the healthy case.
    #[func]
    pub fn halt_summary(&self) -> GString {
        gstring(&sim::debug::halt_summary(&self.world))
    }

    /// EVERY ACTIVITY THIS PLAYER HAS RUNNING, one sentence each, in `step`'s
    /// own system order (ASSA-95, Maren's ruling; the sim half shipped in
    /// #173). Empty when nothing is running, which is the common case.
    ///
    /// **PLURAL, AND A HOST MAY NOT THIN IT.** A player standing on a deposit
    /// mines THROUGH their own assay — `step` never clears one for the other —
    /// so a surface that showed "the" activity would say the mining had
    /// stopped. The list arrives ranked by nothing, and this crate neither
    /// sorts nor caps it: a cap would hide a running activity, which is the
    /// defect the list exists to fix.
    ///
    /// The same shape as `halt_lines` above, and for the same reason: a
    /// `PackedStringArray` the client lays out and never rewords.
    #[func]
    pub fn activity_lines(&self, player: i64) -> PackedStringArray {
        let Some(id) = player_id_of(player) else {
            return PackedStringArray::new();
        };
        packed(&sim::debug::activity_lines(&self.world, id))
    }

    /// WHAT THIS PLAYER IS CRAFTING RIGHT NOW, in the sim's own sentence, or ""
    /// when nothing is being made (ASSA-49).
    ///
    /// The wording is `sim::debug::crafting_readout` rather than anything built
    /// here, for the reason `durability_readout` is shared: `sim-cli` and this
    /// client both have to say it, and two wordings for one fact is the
    /// disagreement nobody notices. A host may put its own label in front of the
    /// sentence; it may not word the number.
    ///
    /// EMPTY STRING AND NOT A NULL, because the caller's question is "is there a
    /// line to show", and `""` answers it without a type change. `designs_of`
    /// leaves a key ABSENT for the same kind of question and that was right
    /// there, where the key's presence IS the fact; here the fact is a sentence.
    #[func]
    pub fn crafting_line(&self, player: i64) -> GString {
        let Some(id) = player_id_of(player) else {
            return GString::new();
        };
        match sim::debug::crafting_readout(&self.world, id) {
            Some(line) => gstring(&line),
            None => GString::new(),
        }
    }

    /// ONE PLAYER'S INVENTORY: kind, species, grade, count, and the name the
    /// sim gives the item. Empty for a player id the world does not have, which
    /// is also what a client has before its `Welcome`.
    ///
    /// `grade` is a LETTER, not a number, because C/B/A is what the sim calls
    /// it; a client that mapped 0/1/2 to letters itself would be a second
    /// opinion about an item's grade.
    #[func]
    pub fn inventory_of(&self, player: i64) -> Array<VarDictionary> {
        self.inventory_facts(player_id_of(player))
            .iter()
            .map(stack_dict)
            .collect()
    }

    /// EVERYTHING ON ONE TILE, for a readout under the cursor: where it is,
    /// what is on it, and who is standing there.
    ///
    /// Every judgement in here is the sim's: whether the tile is in bounds,
    /// which deposit covers it (radius is a circle, not a square), the grade a
    /// purity rounds to, and how far its chunk is from spawn. A client that
    /// worked any of those out from the numbers would eventually disagree with
    /// the world it is drawing.
    #[func]
    pub fn tile_at(&self, at: Vector2i) -> VarDictionary {
        let facts = self.tile_facts(at.x, at.y);
        vdict! {
            "in_bounds" => facts.in_bounds,
            "pos" => Vector2i::new(facts.pos.0, facts.pos.1),
            "chunk" => Vector2i::new(facts.chunk.0, facts.chunk.1),
            "chunks_from_spawn" => facts.chunks_from_spawn,
            "is_spawn" => facts.is_spawn,
            "ground_note" => &gstring(&facts.ground_note).to_variant(),
            "deposit" => &match &facts.deposit {
                Some(deposit) => deposit_dict(deposit).to_variant(),
                None => Variant::nil(),
            },
            "building" => &match &facts.building {
                Some(building) => building_dict(building).to_variant(),
                None => Variant::nil(),
            },
            "players_here" => &packed(&facts.players_here).to_variant(),
        }
    }

    /// EVERY SPECIES AS THE PLAYERS KNOW IT. `assayed` says whether the sheet
    /// is exact; until then each reading is the sim's own 25-wide band as TEXT
    /// ("26-50"), never a number this client narrowed down itself.
    ///
    /// **`reading_ranges` IS THE SAME ANSWER FOR A SURFACE THAT DRAWS IT** — a
    /// `Vector2i` of the band's two ends per property, `(v, v)` once assayed
    /// (ASSA-256). It exists so a bar is not drawn by parsing `readings`, which
    /// is a renderer taking a fact out of our wording. The two dictionaries
    /// have the same keys and come from one sim function, so the bar and the
    /// text beside it cannot drift apart.
    ///
    /// **WHAT STILL DOES NOT CROSS, AND MUST NOT: the exact value of an
    /// unassayed sheet.** A rough range is the sim's band, so `reading_ranges`
    /// carries no more than `readings` always did. The number an assay buys
    /// stays out of this process until someone buys it.
    ///
    /// **THE SCALE THESE SIT ON IS [`Self::reading_scale`]** (ASSA-279), which
    /// is the denominator a bar needs. It is not a key on these rows because
    /// it is a constant of the rules and not a fact about a species: one pair,
    /// every property, every grade. Read it once; never type `100`.
    #[func]
    pub fn species_sheets(&self) -> Array<VarDictionary> {
        self.species_facts()
            .iter()
            .map(|species| {
                let readings = species.readings.iter().fold(
                    VarDictionary::new(),
                    |mut acc: VarDictionary, (property, reading)| {
                        acc.set(&gstring(property), &gstring(reading));
                        acc
                    },
                );
                let reading_ranges = species.reading_ranges.iter().fold(
                    VarDictionary::new(),
                    |mut acc: VarDictionary, (property, (lo, hi))| {
                        acc.set(
                            &gstring(property),
                            Vector2i::new(i32::from(*lo), i32::from(*hi)),
                        );
                        acc
                    },
                );
                let mut row = vdict! {
                    "id" => species.id,
                    "name" => &gstring(&species.name).to_variant(),
                    "symbol" => &gstring(&species.symbol).to_variant(),
                    "assayed" => species.assayed,
                    "readings" => &readings.to_variant(),
                    "reading_ranges" => &reading_ranges.to_variant(),
                    "hand_minable" => species.hand_minable,
                    "hand_lit_fuel" => species.hand_lit_fuel,
                    // ALWAYS PRESENT AND NEVER EMPTY, which is why it is here
                    // rather than under the `if let` below: every rock is in
                    // one of three mining states, so a row has no honest
                    // reason to leave this out and "the key is missing" must
                    // not become a fourth meaning.
                    "mining" => &gstring(&species.mining).to_variant(),
                };
                // ABSENT, not empty, when the sim does not call this rock fuel
                // (ASSA-93) -- the same shape `durability` and the design note
                // use, so a panel cannot print a blank tag for a rock that
                // simply is not fuel. `fuel` leads `lighting` for the reason
                // the table's prose puts it first: at which grade it burns is
                // the question, and how it lights only matters once that is
                // answered (ASSA-143).
                if let Some(fuel) = &species.fuel {
                    row.set("fuel", &gstring(fuel).to_variant());
                }
                if let Some(lighting) = &species.lighting {
                    row.set("lighting", &gstring(lighting).to_variant());
                }
                row
            })
            .collect()
    }

    /// **THE AXIS A READING SITS ON, as a `Vector2i` of its two inclusive
    /// ends: the denominator a bar needs** (ASSA-279, `debug::reading_scale`).
    ///
    /// [`Self::species_sheets`] hands over `reading_ranges`, which is a
    /// numerator with nothing under it, and a surface that wanted to draw it
    /// had to type `100` — a renderer holding an opinion about worldgen, which
    /// would go on looking right for as long as the opinion happened to match.
    ///
    /// **ONE PAIR FOR EVERY PROPERTY AND EVERY GRADE**, because what crosses
    /// as a reading is the raw sheet value or its band and no grade
    /// multiplier is in it. A `Vector2i` rather than two ints or a dict for
    /// the same reason `reading_ranges` is one: it is the shape a surface
    /// already lerps with, and a pair cannot be half-read.
    ///
    /// It takes `&self` because every `#[func]` does, not because it depends
    /// on this world: the scale is a constant of the rules, so the answer is
    /// the same before a world is loaded, which is what lets a title screen
    /// lay out an axis.
    #[func]
    pub fn reading_scale(&self) -> Vector2i {
        let (lo, hi) = sim::debug::reading_scale();
        Vector2i::new(i32::from(lo), i32::from(hi))
    }

    /// WHAT NEAR THIS PLAYER ANSWERS EACH QUESTION, as the sim's own sentence
    /// plus the tile that sentence is about (ASSA-254, the client leg of
    /// ASSA-241).
    ///
    /// **THE SENTENCE IS `debug::proximity_headline`, VERBATIM, AND THAT IS THE
    /// WHOLE POINT.** The Game Director's ruling is that the tab opens on one
    /// line answering the question and shows the table as evidence under it, so
    /// what crosses here is the line itself. It already carries the question it
    /// answers, the species, the grade, the distance and the heading — and both
    /// empty states, which are different news: `nothing_answers` for a world
    /// where no patch can ever answer, `too_poor_answer` for one where a
    /// species would answer from a richer patch. A client that composed any of
    /// that from parts would eventually disagree with the CLI printing the same
    /// line.
    ///
    /// **`tile` IS THE ONE THING THE SENTENCE CANNOT CARRY.** A distance and a
    /// compass word do not get you there: a walk across a gap that is neither
    /// straight nor diagonal changes heading partway, so "15 tiles south-east"
    /// is true of the first step and false of the destination. `go here`
    /// submits `MoveTo { target: tile }` with this value and does no
    /// arithmetic, which is how ASSA-241's no-client-arithmetic box is met.
    ///
    /// **AND `underfoot` IS THE SECOND THING IT CANNOT CARRY, which I learned
    /// by shipping the first version without it** (ASSA-263). `tile` is `Some`
    /// when the answer is the player's own tile, so a button gated on `tile`
    /// alone is live in the one case the sentence reads "right where you are
    /// standing". The walk exists when `tile` is set AND `underfoot` is false.
    ///
    /// **AND `distance` AND `heading` ARE DELIBERATELY NOT HERE.** They are in
    /// the sentence. Sending them a second time would invite a panel to render
    /// its own "15 tiles south-east" beside the sim's, and two vocabularies for
    /// one fact are free to disagree — the defect the Game Director's own
    /// direction doc names elsewhere. If a surface ever needs the number apart
    /// from the words, it should arrive with the reason written here.
    ///
    /// ONE ENTRY PER ANSWER, in the sim's order — **not one per question**
    /// (ASSA-272). `Burns` and `HardEnough` normally give two entries; when one
    /// patch is the nearest answer to both there is ONE, labelled "what near me
    /// burns and is hard enough", carrying each question's reading beside the
    /// verdict that reading earns (ASSA-272 box 7) — nothing dropped. The
    /// count is the sim's to decide and a renderer must not assume it: a body
    /// that drew `Question::ALL.len()` blocks would draw an empty one here, and
    /// a body that merged two entries itself would be inventing wording.
    /// `asked` is the sim's label; it is also the prefix of `headline`, so a
    /// body that renders both would say it twice.
    /// **A THIN WRAPPER OVER `proximity_facts`, AND THAT SPLIT IS NOT STYLE.**
    /// Godot types cannot be built in a `cargo test` -- `GString::from` aborts
    /// with "Godot engine not available" -- so a `#[func]` that held the logic
    /// would be untestable in this crate, which is the one place the sim's
    /// sentence and what the binding sends can be compared. I wrote it the
    /// other way round first and two tests died proving it. The facts method
    /// carries the answer; this carries it across.
    #[func]
    pub fn proximity_answers(&self, player: i64) -> Array<VarDictionary> {
        self.proximity_facts(player_id_of(player))
            .iter()
            .map(|facts| {
                vdict! {
                    "asked" => &gstring(&facts.asked).to_variant(),
                    "headline" => &gstring(&facts.headline).to_variant(),
                    // NIL, NOT (0,0), WHEN NOTHING ANSWERS. A tile of zero is a
                    // real corner of every world, so a sentinel there would be
                    // a walkable destination the sim never offered.
                    "tile" => &match facts.tile {
                        Some((x, y)) => Vector2i::new(x, y).to_variant(),
                        None => Variant::nil(),
                    },
                    // A BOOL, NOT A NIL TILE. `underfoot` answers a different
                    // question from `tile` and answers it in every state, so a
                    // host reads two facts and never infers one from the other.
                    "underfoot" => &facts.underfoot.to_variant(),
                }
            })
            .collect()
    }

    /// EVERYTHING THIS PLAYER COULD MAKE BY HAND, as the crafting menu's rows:
    /// `line`, `dead_end`, `walls`, `verb`, `tag`, and the input stack's own
    /// `kind` / `species` / `grade` / `count`.
    ///
    /// `walls` is the smelter row's figure and empty everywhere else
    /// (`sim::debug::walls_clause`, Maren's ruling on ASSA-88). It is a
    /// SENTENCE and not a number on purpose: what the player may know of a
    /// species' heat tolerance is a 25-wide band until they assay it, and a
    /// host handed the number would have to decide how to say so.
    ///
    /// `sim::debug::make_offers` is the whole answer, including the ORDER
    /// (`RecipeId::ALL`, then `PartKind::ALL`, then the pack's own order) and
    /// the SENTENCE. The client composes neither, for a reason worth keeping
    /// written down: the sentence names the OUTPUT item, and its grade is a
    /// rule — `sort` makes one grade better and makes nothing at all out of
    /// grade A. GDScript spelling that would be guessing at
    /// `Recipe::output_for`, and wrong on the one recipe that moves a grade.
    ///
    /// `verb` IS WHICH COMMAND, NOT A LABEL. `Craft` and `MakePart` are
    /// different commands with differently shaped payloads, so `MakeWhat`
    /// crosses as the word that chooses between them; a host that read a
    /// label's first token instead would break the day a row is reworded.
    ///
    /// The three item fields are spelled exactly as `inventory_of` spells
    /// them, so `AssayActions.item_of_stack` builds the input item out of an
    /// offer with no second rearranging function.
    ///
    /// `count` is the pack's count AT THIS TICK and is in the row's sentence
    /// too. It is a thing to SHOW and must be re-read every refresh; nothing a
    /// button sends is derived from it (ASSA-55: one batch, always).
    ///
    /// **`cost` IS WHAT ONE BATCH SPENDS, and it is here because the row is a
    /// CHOICE** (ASSA-256, Systems & UI). It was the one number in `MakeOffer`
    /// that did not cross, so a surface wanting "spend 2, get 1" as data rather
    /// than prose had to read it out of `line` — parsing our own sentence, the
    /// exact failure the paragraph above warns about for `verb`. Like `count`
    /// it is a thing to SHOW: a batch is always one batch, so nothing a button
    /// sends is derived from it either.
    ///
    /// **`makes` IS THE OUTPUT ITEM, AND IT IS HERE BECAUSE THE MENU DRAWS IT**
    /// (Maren's ruling on ASSA-117 box 4). Without it a client that wants to
    /// show what a row produces has only `offer.input`, so every row in a menu
    /// whose one job is choosing between five things drew the same picture —
    /// the thing you SPEND, which is identical on every row and already named
    /// in the sentence.
    ///
    /// **AND IT IS THE SIM'S, NOT THE CLIENT'S, FOR THE REASON ALREADY WRITTEN
    /// ABOVE:** `sort` moves a grade and grade A makes nothing at all, so
    /// GDScript deriving "the output of this row" from `tag` plus `input` would
    /// be guessing at `Recipe::output_for` and wrong on the one recipe that
    /// moves a grade.
    ///
    /// **ABSENT, NOT EMPTY, WHEN THE ROW MAKES NOTHING** (`sort` on grade A) —
    /// the shape `lighting` and `durability` already use, so a surface cannot
    /// draw a blank plate for a row that has no output. Spelled `kind` /
    /// `species` / `grade` exactly as `inventory_of` spells them, so the same
    /// function draws a pack stack and this.
    #[func]
    pub fn make_offers(&self, player: i64) -> Array<VarDictionary> {
        let Some(id) = player_id_of(player) else {
            return Array::new();
        };
        sim::debug::make_offers(&self.world, id)
            .iter()
            .filter_map(|offer| {
                let (verb, tag) = match offer.what {
                    sim::debug::MakeWhat::Recipe(recipe) => {
                        ("craft", tag_variant(&serde_json::to_value(recipe).ok()?)?)
                    }
                    sim::debug::MakeWhat::Part(kind) => {
                        ("make", tag_variant(&serde_json::to_value(kind).ok()?)?)
                    }
                };
                let mut row = vdict! {
                    "line" => &gstring(&offer.line).to_variant(),
                    "dead_end" => &gstring(&offer.dead_end).to_variant(),
                    "walls" => &gstring(&offer.walls).to_variant(),
                    "verb" => &gstring(verb).to_variant(),
                    "tag" => &tag,
                    "kind" => &gstring(offer.input.kind.name()).to_variant(),
                    "species" => offer.input.species.0 as i64,
                    "grade" => &gstring(&offer.input.grade.letter().to_string()).to_variant(),
                    "count" => offer.have as i64,
                    "cost" => offer.cost as i64,
                };
                if let Some(makes) = offer.makes {
                    row.set(
                        &gstring("makes"),
                        &vdict! {
                            "kind" => &gstring(makes.kind.name()).to_variant(),
                            "species" => makes.species.0 as i64,
                            "grade" => &gstring(&makes.grade.letter().to_string()).to_variant(),
                        }
                        .to_variant(),
                    );
                }
                Some(row)
            })
            .collect()
    }

    /// EVERY DESIGN ONE PLAYER HOLDS, for the part menu. The tool in hand
    /// first, then the built list in the order `Equip` and `PlaceAssembly`
    /// index.
    ///
    /// THE VERDICT IS THE SIM'S WORD AND THE CLIENT MAY NOT DERIVE IT. A
    /// renderer holding `mass_low..mass_high` and `budget_low..budget_high`
    /// could compare them itself; two renderers doing that will eventually
    /// disagree, and this one is specifically forbidden from trying (repo
    /// `CLAUDE.md` principle 1, ADR 0003 A8). The numbers are here to be
    /// SHOWN under the verdict, not to produce it.
    ///
    /// `durability` is MISSING on a planted design rather than empty, and
    /// `unassayed` names the species a design is still guessing about so that
    /// "UNCERTAIN" can say what resolves it.
    #[func]
    pub fn designs_of(&self, player: i64) -> Array<VarDictionary> {
        self.design_facts(player_id_of(player))
            .iter()
            .map(design_dict)
            .collect()
    }

    /// **WHAT A MACHINE MENU MAY OFFER, PER SLOT, AND WHY NOT** (ASSA-351).
    /// One dictionary per insertable slot, each carrying every stack the
    /// player is holding with `refusal` absent when the press would move
    /// something and the sim's own sentence when it would not.
    ///
    /// `hud.gd::insert_slots` is what this replaces, and the replacement is
    /// not a supplement: that function decided from the item's KIND which
    /// slots to offer, so a pack of grade-A refined got four full-width
    /// controls and `sim::step` refused all four. See [`SlotOffersFacts`].
    ///
    /// A caller draws a refused offer **present and unpressable with its
    /// sentence beside it**, never hidden: a player carrying only refused
    /// stacks would otherwise open a smelter to an empty box, which teaches
    /// less than a named dead end (ASSA-301). The Game Director's rule this
    /// serves: *a control may offer an act that goes badly; it may not offer
    /// an act that does nothing.*
    #[func]
    pub fn insert_offers(&self, player: i64, building: i64) -> Array<VarDictionary> {
        self.insert_offer_facts(player_id_of(player), building)
            .iter()
            .map(slot_offers_dict)
            .collect()
    }

    /// **WHAT THE SIM WOULD SAY ABOUT A DESIGN NOBODY HAS BUILT YET** — the
    /// one question `designs_of` cannot answer, because that list is what a
    /// player already holds.
    ///
    /// A scripted run needs this and the reason is ASSA-140. `button_play.gd`
    /// planted a frame, a head and four hoppers on every world, and the sim had
    /// *already* said WILL BREAK before the press on the pinned showcase seed:
    /// 1078 mass against a 705 budget. The demo's last beat is a machine
    /// standing and mining, so the run has to be able to ask "which part count
    /// does this world carry?" BEFORE it spends 500 ticks mining for one.
    ///
    /// IT IS STILL THE SIM'S VERDICT AND NOT THE CALLER'S. `designs_of`'s own
    /// warning stands — a renderer holding the four numbers could compare them
    /// itself and is forbidden from trying. This is the same
    /// [`Assembly::stat_range`] call on a hypothetical assembly rather than a
    /// built one, so there is still exactly one place that decides SAFE.
    /// Choosing *among* the sim's answers is a caller's business; deriving one
    /// is not.
    ///
    /// `frame` and `mounted` are `PartKind` NAMES — the strings
    /// `PartKind::parse` already takes, which is what players type. An illegal
    /// design answers with `verdict` empty and `fault` carrying the sim's own
    /// phrase, so a caller that asks for five hoppers is told why by the rules
    /// rather than by this function's opinion of them.
    #[func]
    pub fn design_if_built(
        &self,
        frame: GString,
        mounted: PackedStringArray,
        species: i64,
        grade: GString,
    ) -> VarDictionary {
        let mounted: Vec<String> = mounted.as_slice().iter().map(ToString::to_string).collect();
        let facts = design_if_built_facts(
            &self.world,
            &frame.to_string(),
            &mounted,
            species,
            &grade.to_string(),
        );
        vdict! {
            "verdict" => &gstring(&facts.verdict).to_variant(),
            "fault" => &gstring(&facts.fault).to_variant(),
            "mass_low" => facts.mass_low,
            "mass_high" => facts.mass_high,
            "budget_low" => facts.budget_low,
            "budget_high" => facts.budget_high,
        }
    }

    /// EVERY NUMBER THE BUILD SCREEN'S READOUT DRAWS, for a design built out of
    /// the parts a pack actually holds — one item per slot, each with its own
    /// species and grade (ASSA-325).
    ///
    /// `design_if_built` above stays the question for a uniform design and its
    /// caller is untouched; see [`DesignReadout`] for why this is not three more
    /// fields on that one, and why durability crosses as SWINGS.
    #[func]
    pub fn design_readout(&self, frame: GString, mounted: PackedStringArray) -> VarDictionary {
        let mounted: Vec<String> = mounted.as_slice().iter().map(ToString::to_string).collect();
        let facts = design_readout_facts(&self.world, &frame.to_string(), &mounted);
        vdict! {
            "verdict" => &gstring(&facts.verdict).to_variant(),
            "fault" => &gstring(&facts.fault).to_variant(),
            "mass_low" => facts.mass_low,
            "mass_high" => facts.mass_high,
            "budget_low" => facts.budget_low,
            "budget_high" => facts.budget_high,
            "speed_low" => facts.speed_low,
            "speed_high" => facts.speed_high,
            "hand_speed" => facts.hand_speed,
            "swings_low" => facts.swings_low,
            "swings_high" => facts.swings_high,
            "capacity_low" => facts.capacity_low,
            "capacity_high" => facts.capacity_high,
            "held" => facts.held,
            // ASSA-329: the third state. `verdict` non-empty is a machine,
            // this is a design still being placed (numbers real, `fault`
            // naming the empty slot), and neither is a refusal.
            "unfinished" => facts.unfinished,
        }
    }

    /// **WHAT THIS DESIGN WOULD COST THIS PLAYER** — block 6 of the build
    /// screen on the assembly path (ASSA-347, the Game Director's (A) on
    /// ASSA-317).
    ///
    /// `entries` is one row per TALLIED stack (frame first, then the mounted
    /// parts) carrying `need`, `have`, and `blocks` for the one stack the sim
    /// says is in the way. `refusal` is the sim's sentence for a pack too thin,
    /// or `""`. See [`DesignCost`] and [`CostEntry`]: every judgement in here is
    /// `sim::assembly::plan`'s, which is the function `PlayerCommand::Assemble`
    /// asks, so a bill and the press it predicts cannot drift.
    ///
    /// **A SECOND CALL AND NOT A PLAYER ARGUMENT ON `design_readout`.** Those
    /// five bars have no pack in them — a design reads the same whoever is
    /// looking at it — and that signature is shipped and called. The two
    /// questions are "what is this machine" and "can I pay for it".
    ///
    /// **NO PACK IS NOT AN ERROR HERE.** A design you cannot afford still bills
    /// in full, with `blocks` on the stack you are short of: pricing a design
    /// before you can build it is what the Game Director paid for this for
    /// (§5.3), and `plan` was written for it.
    #[func]
    pub fn design_cost(
        &self,
        player: i64,
        frame: GString,
        mounted: PackedStringArray,
    ) -> VarDictionary {
        let mounted: Vec<String> = mounted.as_slice().iter().map(ToString::to_string).collect();
        let facts = design_cost_facts(
            &self.world,
            player_id_of(player),
            &frame.to_string(),
            &mounted,
        );
        vdict! {
            "entries" => &facts
                .entries
                .iter()
                .map(cost_entry_dict)
                .collect::<Array<VarDictionary>>()
                .to_variant(),
            "refusal" => &gstring(&facts.refusal).to_variant(),
        }
    }

    /// **A COUNT AND ITS NOUN, AGREEING**, from the sim (ASSA-145).
    ///
    /// `sim::debug::counted` and not a GDScript twin, so the window and
    /// `sim-cli` cannot drift on a sentence a player reads. The window needs it
    /// for three counts the sim knows nothing about -- players, bundles
    /// applied, hashes reported -- which is why it crosses as a helper rather
    /// than as a finished line: those are the HOST's facts, not the world's,
    /// and a sim that composed that sentence would be reading the network.
    ///
    /// NO `World` IS TOUCHED, so this is `static` on the class: a client can
    /// say "0 players" before it has a world at all.
    #[func]
    pub fn counted(n: i64, one: GString, many: GString) -> GString {
        // A NEGATIVE COUNT IS A CALLER BUG AND READS AS ONE. Clamping it to 0
        // would print "0 players" for a count that came back as -1 from a
        // binding that failed, which is the plausible lie ASSA-141 is about.
        if n < 0 {
            return gstring(&format!("{n} {many}"));
        }
        gstring(&sim::debug::counted(
            n as u64,
            &one.to_string(),
            &many.to_string(),
        ))
    }

    /// EVERY PLAYER, FOR DRAWING: id, name, where they are, where they are
    /// walking. Read out of the stepped world, never predicted — `target` is
    /// here so a client can draw an intention, not so it can interpolate a
    /// position the sim has not reached.
    #[func]
    pub fn players(&self) -> Array<VarDictionary> {
        self.world
            .players
            .iter()
            .map(|player| {
                vdict! {
                    "id" => player.id.0 as i64,
                    "name" => &gstring(&player.name).to_variant(),
                    "pos" => Vector2i::new(player.pos.x, player.pos.y),
                    "target" => &match player.target {
                        Some(at) => Vector2i::new(at.x, at.y).to_variant(),
                        None => Variant::nil(),
                    },
                }
            })
            .collect()
    }

    /// EVERY BUILDING, FOR DRAWING: where it stands, how many tiles it covers,
    /// and what it is made of. The thin half of `building_facts`, which holds
    /// the reasoning and the test.
    ///
    /// `pos` IS THE TOP-LEFT TILE OF THE FOOTPRINT — `Building::pos`'s own
    /// documented meaning, and the convention `art/mock_scene.py` blits at. A
    /// machine is (1, 1) and its sprite is two tiles wide, so the picture
    /// OVERHANGS east; occupancy is sim state and this is where a renderer
    /// reads it rather than guessing it from the drawing (ASSA-30/38).
    #[func]
    pub fn buildings(&self) -> Array<VarDictionary> {
        self.building_facts().iter().map(building_dict).collect()
    }

    /// EVERY DEPOSIT, FOR DRAWING. Depleted ones are included with `amount` 0,
    /// because the sim keeps them so `DepositId`s stay stable; what to do with
    /// an empty patch on screen is the view's business.
    ///
    /// `purity` is the number the game is named after and it is reported raw,
    /// 1-100. The sim's own grade bands are C below 40, B to 69, A from 70 —
    /// a client that invents its own bands is lying about the item it will get.
    ///
    /// `symbol` is the species' map letter, from `sim::debug::species_symbol`,
    /// so colour is not the only thing distinguishing two deposits (Decision
    /// #36). It comes from there rather than from the first character of
    /// `species_names()`: that name is the discoverer's once a species is
    /// claimed, and only the GENERATED name is distinct per world.
    ///
    /// `starter` is `sim::World::is_starter_deposit`: this is one of the two
    /// patches the ladder's guarantee actually points at, floored to a grade
    /// the pair was cleared at. **A caller that wants the guaranteed fuel must
    /// read this and not "the nearest deposit of the right species"**, which
    /// is a different patch at a rolled purity in 1.5% of worlds and the
    /// second half of ASSA-139. The sim answers it for the same reason
    /// [`AssaySim::starter_pair`] does: grade scales reactivity, so choosing
    /// the patch is choosing whether the smelter runs.
    #[func]
    pub fn deposits(&self) -> Array<VarDictionary> {
        // Resolved once: `is_starter_deposit` walks the roster and the deposit
        // list, and doing that per deposit would make drawing quadratic.
        let starter = self.world.starter_deposits();
        self.world
            .deposits
            .iter()
            .map(|deposit| {
                // Resolved once per deposit: both keys below come out of it and
                // `deposit_dead_end_note` walks the roster.
                let (minable, dead_end) = map_disc_facts(&self.world, deposit);
                vdict! {
                    "id" => deposit.id.0 as i64,
                    "species" => deposit.species.0 as i64,
                    "center" => Vector2i::new(deposit.center.x, deposit.center.y),
                    "radius" => deposit.radius as i64,
                    "amount" => deposit.amount as i64,
                    "purity" => deposit.purity as i64,
                    "starter" => starter
                        .is_some_and(|(m, f)| deposit.id == m || deposit.id == f),
                    "symbol" => &gstring(
                        &sim::debug::species_symbol(self.world.species(deposit.species))
                            .to_string(),
                    ).to_variant(),
                    // WHETHER ANYTHING THIS WORLD CAN BUILD GETS THE ORE OUT,
                    // from `sim::ladder::hand_minable` — the same function
                    // `step`, `mine_by_machine` and `DepositFacts` ask, so the
                    // schematic and the cursor readout cannot tell a player two
                    // different stories about one rock (ASSA-187).
                    //
                    // **THE SCHEMATIC HAD NO CHANNEL FOR IT AND THIS PAYLOAD
                    // HAD NO FIELD.** Colour is the species slot, brightness is
                    // purity, radius is radius; whether the walk is worth taking
                    // was drawn nowhere, and 25.4% of deposits over 16 seeds are
                    // rock nothing can mine. The fact was already in the sim and
                    // already on `deposit_dict`; it was missing here, which is
                    // the one payload the map draws from.
                    //
                    // Same name as `deposit_dict`'s field ON PURPOSE, including
                    // its mild lie: "hand" is where the gate started and the
                    // gate is now one function every miner asks. A second name
                    // for one rule is how two surfaces drift.
                    "hand_minable" => minable,
                    // **THE SENTENCE, AND IT IS A WIDER GATE THAN `hand_minable`**
                    // (ASSA-199, Maren's ruling; ASSA-187 was mine and it marked
                    // the wrong set). `hand_minable` is one of TWO kinds of dead
                    // end. The other is quieter: a rock you CAN break and cannot
                    // smelt. On 777042 that is the difference between 6 of 13 and
                    // 8 of 13, and the two Naersernium patches it misses were
                    // drawn exactly like good ore -- this item's own defect
                    // surviving its own fix.
                    //
                    // THE SIM'S OWN WORDING, EMPTY WHEN THE ROCK YIELDS, which is
                    // the same contract `deposit_dict::reach_note` carries and the
                    // same name on purpose: one rule, one key, so the schematic
                    // and the cursor readout cannot tell a player two stories
                    // about one rock. The client reads "is it empty"; it does not
                    // work the gate out.
                    "reach_note" => &gstring(&dead_end).to_variant(),
                }
            })
            .collect()
    }

    /// THE STARTER PAIR THIS WORLD GUARANTEES: the material at rung zero and a
    /// hand-lit fuel, as `[material, fuel]` species ids. Empty if the roster has
    /// no such pair, which worldgen rerolls to prevent.
    ///
    /// A SCRIPTED SESSION MAY NOT WORK THIS OUT FOR ITSELF. "Does this fuel get
    /// hot enough to melt that ore" is a rule — effective reactivity against
    /// heat tolerance, both scaled by grade — and a client that answered it
    /// would be holding an opinion about whether a smelter will run. Worse, it
    /// would be answering from the ROUGH sheet before anything is assayed, so it
    /// would be guessing with a 25-wide band and calling it a plan. `ladder.rs`
    /// already decides it, and the ladder is what worldgen rerolls the roster
    /// to guarantee, so this is the one pair a demo can count on in any seed.
    #[func]
    pub fn starter_pair(&self) -> PackedInt32Array {
        PackedInt32Array::from(self.starter_pair_ids().as_slice())
    }

    /// ONE ITEM, SPELLED BY SERDE RATHER THAN BY GDSCRIPT, as the JSON a command
    /// carries. `kind` is the sim's own item name (`ore`, `refined`, `smelter`,
    /// `head`, `handle`, `frame`, `hopper`, or `part:head`), `grade` a letter.
    /// Empty string if either will not parse.
    ///
    /// SAME ARGUMENT AS `hash_message_json`, one step weaker. An `Item` is three
    /// nested enums and a newtype — `{"kind":{"Part":{"Frame":"Held"}},...}` —
    /// and nothing on the GDScript side would notice getting that shape wrong
    /// until a relay silently dropped the command. GDScript still BUILDS the
    /// commands it sends (the numbers stay integers that way, which matters:
    /// Godot's JSON parses every number as a double, and serde will not take
    /// `3.0` for a `u8`). This exists so a test can hold what GDScript built
    /// against what serde would have written, which is the only check that
    /// cannot agree with my own misreading.
    #[func]
    pub fn item_json(kind: GString, species: i64, grade: GString) -> GString {
        gstring(&item_text(&kind.to_string(), species, &grade.to_string()))
    }

    /// DOES SERDE ACCEPT WHAT THE CLIENT BUILT? Takes the JSON text a client
    /// wrote for an `Item` and gives back serde's own spelling of whatever it
    /// read, or "" if serde refuses it.
    ///
    /// `item_json` alone was not enough, and a planted mutation proved it:
    /// sending `species` as `3.0` instead of `3` passed a test that compared the
    /// two sides as PARSED values, because Godot parses both back to the same
    /// double. Serde does not — a `u8` will not come from a float — so the
    /// command would have been dropped before `step` saw it, and the probe would
    /// have failed as "the parts never arrived". This runs the client's own text
    /// through the deserialiser that will actually read it.
    #[func]
    pub fn item_echo(text: GString) -> GString {
        gstring(&item_echo_text(&text.to_string()))
    }

    /// DOES SERDE ACCEPT THIS AS A `PlayerCommand`? Serde's own spelling of
    /// whatever it read back, or "" if it refuses.
    ///
    /// `item_echo` for whole commands, and it exists because the client now has
    /// BUTTONS (ASSA-37). Every button builds a command in GDScript, and the
    /// only thing that can tell a correct shape from a plausible one is the
    /// deserialiser that will actually read it on the other side. Two mistakes
    /// of mine are the reason this is not paranoia: `{"Stop": {}}` for a unit
    /// variant, which a relay drops in silence while the probe reports success,
    /// and `species: 3.0`, which parses fine in Godot and not at all in serde.
    ///
    /// THIS IS THE SAME TYPE `sim-cli` CONSTRUCTS. There is one
    /// `PlayerCommand` in the repo; the reference client builds it with Rust
    /// constructors and this client builds JSON that becomes it. "The same
    /// command" means serde lands on the same variant with the same fields,
    /// which is exactly what the echo shows.
    #[func]
    pub fn command_echo(text: GString) -> GString {
        gstring(&command_echo_text(&text.to_string()))
    }

    /// A WORLD TO TEST AGAINST, SHAPED LIKE THE RELAY'S: the whole
    /// `ServerMsg::Welcome` text for a fresh world with one player in it.
    ///
    /// Not a convenience and not a second way to play. Before this, nothing in
    /// the client's headless suite had a world at all — every HUD test ran
    /// against dictionaries I had typed out myself, which is the failure I keep
    /// repeating: my test agrees with my bug because I wrote both. A real world
    /// means the button tests press buttons against the sim's own inventory,
    /// designs and tiles.
    ///
    /// IT MIRRORS `sim-relay/src/main.rs` DELIBERATELY: the same 6x4 chunks,
    /// `SystemCommand::AddPlayer` applied through `step` (never by reaching into
    /// `World`), and the player's slot in the `Welcome` beside the world. A
    /// client fed this is in exactly the state a welcomed client is in, so the
    /// suite cannot pass on a world no relay would ever send.
    ///
    /// The seed is TEXT for the usual reason: a full-width `u64` does not
    /// survive a GDScript number. "" on a seed that will not parse.
    #[func]
    pub fn fresh_welcome_json(seed: GString, name: GString) -> GString {
        gstring(&fresh_welcome_text(&seed.to_string(), &name.to_string()))
    }

    /// WHAT A PART IS MADE OF: the one item kind `MakePart` accepts as material.
    ///
    /// `step.rs` says it in one line -- "a part is made of refined material and
    /// nothing else, so say so rather than quietly coercing whatever the client
    /// sent" -- and the client needs it to decide which pack row gets a `Make`
    /// button. Naming it here rather than in GDScript puts it in the crate that
    /// can be tested against `step` itself, and
    /// `a_part_is_made_of_the_material_this_catalogue_names` does exactly that:
    /// it submits a `MakePart` with the wrong kind and checks the sim refuses.
    pub const PART_MATERIAL: sim::ItemKind = sim::ItemKind::Refined;

    /// EVERY PART THE CATALOGUE HOLDS: `name`, `size`, `material`, `tag`,
    /// `is_frame` and `slots`.
    ///
    /// So the client's "make a part" buttons are the sim's list rather than four
    /// strings typed into GDScript. ADR 0003's consequence is that a new part
    /// kind needs no recipe — add a `PartSpec` and it is makeable — and a client
    /// with its own copy of the catalogue would be the one place that still had
    /// to be edited. It asks instead.
    ///
    /// `tag` IS SERDE'S OWN SPELLING, handed over as the Variant a `MakePart`
    /// carries: a bare `"Head"`, or `{"Frame": "Held"}` for a handle, because
    /// `PartKind::Frame(Mount)` is an enum inside an enum. GDScript neither
    /// builds that nor parses it — parsing would be the double trap again — it
    /// passes this value straight into the command.
    ///
    /// **`slots` IS WHAT A FRAME ACCEPTS, AS THREE NUMBERS AND A NAME PER SLOT
    /// AND NEVER AS A SENTENCE** (ASSA-340, for `assay-build-screen` §3's take
    /// from Satisfactory: *"slots drawn as a shape, not listed as rows … a list
    /// hides a limit that a drawn shape states"*). One entry per `SlotLimit` in
    /// the catalogue's order, each `{name, min, max}`; empty for every kind
    /// that is not a frame, which is `PartSpec::slots`' own rule (*"Only a
    /// frame offers any"*). The build screen draws `max` boxes and marks the
    /// first `min` of them required, so the limit is stated by the shape — the
    /// alternative was four numbers typed into GDScript, which ASSA-317 forbids
    /// by name. `sim::debug::slots_phrase` is where the WORDS live if a surface
    /// ever needs them; `part_table`'s `accepts` column is the headless one.
    ///
    /// **`name` IS THE SLOT KIND'S OWN ITEM NAME, WHICH IS WHAT `inventory_of`
    /// ALREADY CALLS A PART IN THE PACK** (`ItemKind::Part(k).name()` is
    /// `k.name()`), so a client matches a pack row to a slot by comparing two
    /// strings the sim wrote and parses nothing.
    ///
    /// **AND THERE IS NO `tag` ON A SLOT, DELIBERATELY.** Nothing ever sends a
    /// slot to the sim: `Assemble` carries an ordered list of items, not slot
    /// indices, and whether a part may join a design is `part_press_refusal`'s
    /// answer rather than a comparison the client makes. A crossed field with
    /// no reader is ASSA-173's defect, so it is absent until something asks.
    #[func]
    pub fn part_kinds() -> Array<VarDictionary> {
        PartKind::ALL
            .iter()
            .filter_map(|kind| {
                let tag = tag_variant(&serde_json::to_value(kind).ok()?)?;
                let slots: Array<VarDictionary> = sim::assembly::spec(*kind)
                    .slots
                    .iter()
                    .map(|slot| {
                        vdict! {
                            "name" => &gstring(slot.kind.name()).to_variant(),
                            "min" => &(i64::from(slot.min)).to_variant(),
                            "max" => &(i64::from(slot.max)).to_variant(),
                        }
                    })
                    .collect();
                Some(vdict! {
                    "name" => &gstring(kind.name()).to_variant(),
                    "size" => &(sim::assembly::spec(*kind).size as i64).to_variant(),
                    "material" => &gstring(Self::PART_MATERIAL.name()).to_variant(),
                    "tag" => &tag,
                    "slots" => &slots.to_variant(),
                    // **THE WORD ON A PART ROW'S BUTTON IS A PROPERTY OF THE
                    // KIND** (Game Director, ASSA-86 ruling 1): a frame kind
                    // says `Frame` forever and every other kind says `Mount`
                    // forever, so a fifth part kind labels itself. The client
                    // used to pick that word from its own buffer state, which
                    // made two of four rows wrong in each state. It is handed
                    // the answer here rather than deriving it — the ASSA-90
                    // shape — because which kinds are frames is a static
                    // catalogue fact and not a sheet reading.
                    "is_frame" => &kind.is_frame().to_variant(),
                })
            })
            .collect()
    }

    /// WHETHER CHOOSING THIS PART NEXT CAN EVER LEAD TO A MACHINE, and the
    /// sim's own sentence when it cannot. `""` means the press is safe.
    ///
    /// **A CLIENT MUST NOT CONFIRM A PRESS THE SIM WOULD REFUSE** (Game
    /// Director, ASSA-86 ruling 2; how a client learns it was left to me).
    /// Pressing `Frame` on a head row is `FrameIsNotAFrame`, which **no later
    /// press can rescue** — so the window used to answer a confirmed dead end
    /// in the positive colour, and the refusal arrived at `Assemble` once the
    /// player had built the rest of the design on it.
    ///
    /// `chosen` and `candidate` are the `kind` strings this class already
    /// handed over in `inventory_of`, in the order the parts were pressed; the
    /// first is the frame, which is `sim-cli`'s rule. **The client hands back
    /// what it was given and parses nothing**, which is `part_kinds`' own
    /// doctrine — and it costs nothing to honour, because legality is a
    /// question about kinds and never about the material.
    ///
    /// A design that is merely half-built answers `""`: being unfinished is
    /// the normal state of an assembly chosen one row at a time, and
    /// `AssemblyError::is_unfinished` is where the sim draws that line.
    #[func]
    pub fn part_press_refusal(chosen: PackedStringArray, candidate: GString) -> GString {
        let chosen: Vec<String> = chosen.as_slice().iter().map(ToString::to_string).collect();
        gstring(&press_refusal_text(&chosen, &candidate.to_string()))
    }

    /// EVERY RECIPE THE SIM HAS: `name`, `tag`, `input`, `input_count`, `hand`.
    ///
    /// Same argument as `part_kinds`, and the client needs two of these fields
    /// to put a Craft button on the right row: `input` is the item kind a batch
    /// consumes, so a button only appears on a stack that could feed it, and
    /// `hand` says whether a player can make it at all — `Refine` and `Resmelt`
    /// happen inside a smelter and are nobody's button.
    ///
    /// `name` is what a player types in `sim-cli`; `tag` is what the wire
    /// carries. They differ in case, which is exactly the kind of thing a client
    /// should not be guessing at.
    #[func]
    pub fn recipes() -> Array<VarDictionary> {
        sim::RecipeId::ALL
            .iter()
            .filter_map(|id| {
                let tag = tag_variant(&serde_json::to_value(id).ok()?)?;
                let recipe = id.recipe();
                Some(vdict! {
                    "name" => &gstring(recipe.name).to_variant(),
                    "tag" => &tag,
                    "input" => &gstring(recipe.input.0.name()).to_variant(),
                    "input_count" => &(recipe.input.1 as i64).to_variant(),
                    "hand" => &id.is_hand_craftable().to_variant(),
                    // THE CLAUSE THE TERMINAL'S RECIPE TABLE ALREADY PRINTS,
                    // from `sim::debug::recipe_dead_end` -- the same call, not
                    // a second sentence (ASSA-84, Maren's ruling 2). Empty when
                    // something consumes the output, so a client that renders
                    // it when non-empty needs no edit the day a recipe stops
                    // being a dead end.
                    "dead_end" => &gstring(&sim::debug::recipe_dead_end(recipe)).to_variant(),
                })
            })
            .collect()
    }

    /// HOW MANY TILES A BUILDING OF THIS ITEM WOULD STAND ON, or 0 for an item
    /// that is not placeable.
    ///
    /// The client needs this for one honest sentence and nothing else: a
    /// placement target is a TOP-LEFT tile, so a player clicking a tile for a
    /// 2x2 smelter should be told which four tiles they just chose. It does not
    /// decide whether the placement is legal — `step` does, and the client never
    /// asks first (Maren's ruling: never refuse).
    #[func]
    pub fn footprint_of_item(kind: GString, species: i64, grade: GString) -> Vector2i {
        let text = item_text(&kind.to_string(), species, &grade.to_string());
        let Ok(item) = serde_json::from_str::<Item>(&text) else {
            return Vector2i::ZERO;
        };
        match sim::building::BuildingKind::for_item(item.kind) {
            Some(kind) => {
                let (w, h) = kind.footprint();
                Vector2i::new(w, h)
            }
            None => Vector2i::ZERO,
        }
    }

    /// HOW MANY SPECIES A WORLD ROLLS (`sim::tuning::SPECIES_PER_WORLD`).
    ///
    /// Here so the client's per-species colour table can be checked against the
    /// sim's own count instead of against the number six written down a second
    /// time. A table shorter than the roster would alias two species onto one
    /// colour, and the player it misleads is the one who cannot use colour
    /// anyway.
    ///
    /// STATIC on purpose: it is a tuning constant, not a fact about one world,
    /// and the test that uses it should not need a `Welcome` to ask.
    #[func]
    pub fn species_per_world() -> i64 {
        sim::tuning::SPECIES_PER_WORLD as i64
    }

    /// THE LONGEST NAME A SPECIES CAN CARRY (`sim::tuning::SPECIES_NAME_MAX`),
    /// in characters — `mineral::validate_name` counts `chars`, not bytes, and
    /// allows only ASCII letters, digits and hyphens, which is what makes
    /// `"W"` repeated to this length a real worst case rather than a guess.
    ///
    /// **HERE BECAUSE A WORST CASE THAT STOPS BEING THE WORST CASE FAILS
    /// SILENTLY.** The window sizes the machine menu against the widest line
    /// the sim can hand it, and the widest line is a full-length species name
    /// (`test_buttons.gd`'s menu-width bound, ASSA-334). That test wrote `20`
    /// of its own: raise the cap in `tuning.rs` and the test's "worst case"
    /// gets SHORTER than the real one, the check stays green, and the row
    /// overflows in a real window with nothing going red. A constant the test
    /// and the rule both read cannot drift that way.
    ///
    /// STATIC, like [`AssaySim::species_per_world`]: it is a tuning constant,
    /// not a fact about one world, so a test should not need a `Welcome` to
    /// ask for it. It is NOT on `building_facts` for the same reason.
    #[func]
    pub fn species_name_max() -> i64 {
        sim::tuning::SPECIES_NAME_MAX as i64
    }

    /// The word the sim puts in front of a dead end, so the window labels one
    /// the way the terminal already does (ASSA-158).
    ///
    /// **IT IS EXPOSED RATHER THAN RETYPED BECAUSE THE DEFECT IS A CLIENT
    /// COMPOSING A VOICE.** The window drew the dead end as `— nothing uses a
    /// gear`, in the same em dash and the same ink as the cost clause above it,
    /// so *"what this costs"* and *"this is useless"* arrived in one voice —
    /// and one of them can become true by playing while the other never can.
    /// `sim-cli`'s catalogue has had the labelled line since ASSA-122
    /// (`debug.rs` prints `{DEAD_END_LABEL}{dead_end}`); the window is the
    /// surface that never got it.
    ///
    /// **STATIC, like `species_per_world`:** it is a wording constant, not a
    /// fact about one world, and a test should not need a `Welcome` to ask for
    /// it. A client that hard-coded "dead end: " would be a second copy of a
    /// decision that is the Game Director's, which is the whole shape of
    /// ASSA-43 and ASSA-52.
    #[func]
    pub fn dead_end_label() -> GString {
        gstring(Self::dead_end_label_text())
    }

    /// Engine-free half of [`AssaySim::dead_end_label`], so the rule it carries
    /// can be tested without an engine.
    ///
    /// **A `#[test]` CANNOT CALL THE `#[func]`**: `gstring` touches the Godot
    /// API and godot-ffi panics with "Godot binding accessed before
    /// initialization". That is the same split `halt_line_texts` exists for,
    /// and I rediscovered it the hard way by writing the other test first.
    pub fn dead_end_label_text() -> &'static str {
        sim::debug::DEAD_END_LABEL
    }

    /// Species names in `SpeciesId` order, so a `species` index above can be
    /// labelled. The sim decides whether that is the generated name or the one
    /// its discoverer chose.
    #[func]
    pub fn species_names(&self) -> PackedStringArray {
        self.world
            .species
            .iter()
            .map(|species| GString::from(species.name()))
            .collect()
    }

    /// IS A HASH DUE THIS TICK? `sim-net::HASH_EVERY`, asked of the world we are
    /// actually on, so GDScript never has to count ticks itself. The reference
    /// client tests the same thing in the same place: after stepping.
    #[func]
    pub fn hash_due(&self) -> bool {
        self.world.tick.is_multiple_of(HASH_EVERY)
    }

    /// A WHOLE `ClientMsg::Hash`, SERIALISED HERE, ready to be framed and sent.
    ///
    /// This exists because the hash is a `u64` and GDScript's integers are
    /// signed: half of all hashes cannot be spelled there, so GDScript cannot
    /// build this message correctly even with the value in front of it. Writing
    /// the JSON on this side is not a convenience, it is the only correct route
    /// — and it is still only the wire shape, with the socket left to the host.
    #[func]
    pub fn hash_message_json(&self) -> GString {
        match self.hash_message_text() {
            Ok(text) => gstring(&text),
            Err(why) => {
                godot_error!("sim-godot: could not write a Hash message: {why}");
                GString::new()
            }
        }
    }

    /// THE PROTOCOL NUMBER RUST DECLARES, so GDScript never keeps a copy.
    ///
    /// `sim-net` bumps this whenever a message or `World` changes shape and the
    /// relay refuses any client on another number. The client used to hold its
    /// own `const PROTOCOL_VERSION`, kept honest by a test that grepped the Rust
    /// source — which worked (it caught ASSA-5 part 2's bump to 5) but only
    /// after someone had already shipped the mismatch into a branch. Read at
    /// runtime there is nothing to keep in step: one declaration, in the crate
    /// that owns the wire.
    #[func]
    pub fn protocol_version() -> i64 {
        PROTOCOL_VERSION as i64
    }

    /// WHICH RULES THIS BUILD RUNS, for the same reason and by the same route
    /// as [`Self::protocol_version`]: one declaration, in Rust, read at
    /// runtime (ASSA-40).
    ///
    /// **HEX TEXT, NEVER A NUMBER.** Sixteen hex digits do not survive a
    /// GDScript double any better than a `u64` hash does, and this one is
    /// compared for equality by the relay — a value mangled on the way out
    /// would be refused every time, which is the most confusing possible
    /// failure. Same rule as hashes and seeds.
    #[func]
    pub fn rules_id() -> GString {
        gstring(Self::rules_id_string())
    }

    /// `rules_id` without Godot in the way, so a test can read it: a
    /// `GString` cannot be built outside the engine's load window.
    pub fn rules_id_string() -> &'static str {
        sim::RULES_ID
    }

    /// Proof, from inside a shipped build, that this library loaded AND runs
    /// the sim — not merely that Godot registered a class name.
    ///
    /// `scripts/selfcheck.gd` calls this and CI fails the job if it is wrong,
    /// because a `.gdextension` that does not load produces a client that
    /// looks fine until the moment it has to simulate anything.
    ///
    /// The expected value is computed here from the same `sim`, never pinned:
    /// the golden hash moved twice on 2026-10-01 and moves again on ASSA-5.
    #[func]
    pub fn binding_self_check() -> GString {
        gstring(&Self::self_check_value())
    }

    /// The same number, computed without touching this class, so the check
    /// above compares two routes to it rather than a value to itself.
    #[func]
    pub fn binding_self_check_expected() -> GString {
        gstring(&Self::self_check_expected_value())
    }
}

/// Godot's string type has no `From<String>`, only `From<&str>`, and leaning
/// on `.into()` for it is how this file failed to compile the first time.
fn gstring(text: &str) -> GString {
    GString::from(text)
}

/// The whole of `part_press_refusal` except the Variant marshalling, so the
/// answer can be tested without an engine — the same split `inventory_facts`
/// and `inventory_of` already use. `""` means the press is safe to confirm.
fn press_refusal_text(chosen: &[String], candidate: &str) -> String {
    let mut kinds = Vec::with_capacity(chosen.len() + 1);
    for name in chosen {
        match ItemKind::from_name(name).and_then(ItemKind::part) {
            Some(kind) => kinds.push(kind),
            // Not a part at all: the sim names what the parts are rather than
            // this host inventing a sentence for it.
            None => return sim::debug::not_a_part_phrase(name),
        }
    }
    let Some(kind) = ItemKind::from_name(candidate).and_then(ItemKind::part) else {
        return sim::debug::not_a_part_phrase(candidate);
    };
    match sim::assembly::fault_adding(&kinds, kind) {
        Some(e) => sim::debug::assembly_error_phrase(e),
        None => String::new(),
    }
}

fn packed(lines: &[String]) -> PackedStringArray {
    lines.iter().map(GString::from).collect()
}

/// A client has no player id until the relay welcomes it, and it spells that
/// -1 rather than guessing at player 0 — whose inventory would be somebody
/// else's.
fn player_id_of(id: i64) -> Option<PlayerId> {
    u32::try_from(id).ok().map(PlayerId)
}

/// **THE TWO FACTS THE SCHEMATIC DECIDES A DISC FROM, ENGINE-FREE** (ASSA-199).
///
/// `AssaySim::deposits` is the one payload the map draws from and it builds its
/// dictionary inline, so until now nothing in `cargo test` could see what that
/// payload says — `building_facts` has had the same split since ASSA-94 and for
/// the same reason: a `VarDictionary` cannot be built in a Rust unit test at all.
/// This is the half a sweep over seeds can read.
///
/// **THEY ARE NOT OPPOSITES AND THAT IS THE POINT.** `hand_minable` is whether
/// anything this world can build gets the ore OUT; the note is the sim's sentence
/// for why the rock is a dead end, which also covers the ore you can break and
/// cannot smelt. A rock can be perfectly minable and still carry a sentence, so a
/// mark keyed on `hand_minable` misses the quieter half — 6 of 13 against 8 of 13
/// on seed 777042, and 38.8% against 55.1% over the Game Director's 30 seeds.
pub fn map_disc_facts(world: &World, deposit: &sim::ore::OreDeposit) -> (bool, String) {
    (
        sim::ladder::hand_minable(world.species(deposit.species)),
        sim::debug::deposit_dead_end_note(world, deposit).unwrap_or_default(),
    )
}

fn deposit_dict(deposit: &DepositFacts) -> VarDictionary {
    vdict! {
        "id" => deposit.id,
        "species" => deposit.species,
        "species_name" => &gstring(&deposit.species_name).to_variant(),
        "center" => Vector2i::new(deposit.center.0, deposit.center.1),
        "radius" => deposit.radius,
        "amount" => deposit.amount,
        "purity" => deposit.purity,
        "grade" => &gstring(&deposit.grade).to_variant(),
        "depleted" => deposit.depleted,
        "assayed" => deposit.assayed,
        "hand_minable" => deposit.hand_minable,
        "reach_note" => &gstring(&deposit.reach_note).to_variant(),
    }
}

/// ONE PART AS FACTS, AND THE ONLY PLACE THAT SPELLS THEM.
///
/// `design_facts` (the bench menu) and `building_fact` (a machine standing on
/// the map) both need this, and the same argument the header of `building_fact`
/// makes applies one level down: two copies drift, and the drift here would be
/// a drill that looks like one material in your bench and another on the
/// ground. Which sheet, which row and which tint are all read from this.
fn part_fact(world: &World, part: &sim::assembly::Part) -> PartFacts {
    let species = world.species(part.material.species);
    let (low, high) = Assembly::part_mass_range(part, species);
    PartFacts {
        kind: part.kind.name().to_string(),
        species: part.material.species.0 as i64,
        species_name: species.name().to_string(),
        symbol: sim::debug::species_symbol(species).to_string(),
        grade: part.material.grade.letter().to_string(),
        mass_low: low as i64,
        mass_high: high as i64,
    }
}

fn part_dict(part: &PartFacts) -> VarDictionary {
    vdict! {
        "kind" => &gstring(&part.kind).to_variant(),
        "species" => part.species,
        "species_name" => &gstring(&part.species_name).to_variant(),
        "symbol" => &gstring(&part.symbol).to_variant(),
        "grade" => &gstring(&part.grade).to_variant(),
        "mass_low" => part.mass_low,
        "mass_high" => part.mass_high,
    }
}

fn design_dict(design: &DesignFacts) -> VarDictionary {
    let mut out = vdict! {
        "index" => design.index,
        "in_hand" => design.in_hand,
        "verdict" => &gstring(&design.verdict).to_variant(),
        "mass_low" => design.mass_low,
        "mass_high" => design.mass_high,
        "budget_low" => design.budget_low,
        "budget_high" => design.budget_high,
        "mount" => &gstring(&design.mount).to_variant(),
        "unassayed" => &design.unassayed.iter().map(|n| gstring(n))
            .collect::<PackedStringArray>().to_variant(),
        "parts" => &design.parts.iter().map(part_dict)
            .collect::<Array<VarDictionary>>().to_variant(),
    };
    // ABSENT, not null, on a planted design. A key that is there but empty
    // invites a panel to print "durability: " and a blank, which is the
    // mechanic-that-does-not-exist shown anyway.
    if let Some(durability) = &design.durability {
        out.set("durability", &gstring(durability).to_variant());
    }
    // ABSENT on a SAFE design, for the same reason (ASSA-90): a settled design
    // has no small print, and a key present-but-empty is how a panel ends up
    // printing a blank line under a verdict that had nothing to say.
    if let Some(note) = &design.note {
        out.set("note", &gstring(note).to_variant());
    }
    out
}

/// ONE BUILDING AS FACTS, AND THE ONLY PLACE THAT SPELLS THEM.
///
/// `tile_facts` (a cursor over one tile) and `building_facts` (the list a
/// renderer draws) both need this. Two copies is exactly the drift this repo
/// keeps paying for: the tile under the mouse would go on saying one thing
/// while the list it is drawn from said another, and both would look right.
/// The exact string `PlayerCommand::Insert` round-trips for this slot, asked of
/// serde rather than spelt.
///
/// **A LITERAL HERE WOULD OUTLIVE A RENAME.** The client submits commands as
/// JSON (`{"Insert":{"building":1,"slot":"Fuel",…}}`), so the tag has to be the
/// wire format's and not this crate's opinion of it; a hand-typed "Fuel" would
/// keep compiling after the variant moved and the relay would drop every
/// insert. `the_insert_tag_a_menu_is_handed_is_the_one_the_sim_parses` holds it
/// against a real `PlayerCommand`.
fn insert_tag(slot: sim::Slot) -> Option<String> {
    match serde_json::to_value(slot) {
        Ok(serde_json::Value::String(tag)) => Some(tag),
        // Unreachable while `Slot` is a plain enum, and reported rather than
        // papered over if it ever stops being one: a menu with no tag offers no
        // put control, which is wrong but visible. Silently returning "Fuel"
        // would be wrong and invisible.
        _ => None,
    }
}

fn slot_facts(world: &World, building: &sim::building::Building) -> Vec<SlotFacts> {
    world
        .building_slots(building)
        .into_iter()
        .map(|(role, held, cap)| SlotFacts {
            role: role.name().to_string(),
            insert_tag: role.insertable().and_then(insert_tag),
            held: held.map(|stack| StackFacts {
                kind: stack.item.kind.name().to_string(),
                species: stack.item.species.0 as i64,
                species_name: world.species(stack.item.species).name().to_string(),
                grade: stack.item.grade.letter().to_string(),
                count: stack.count as i64,
                name: world.item_name(stack.item),
            }),
            count: held.map_or(0, |s| s.count) as i64,
            cap: cap as i64,
        })
        .collect()
}

fn building_fact(world: &World, building: &sim::building::Building) -> BuildingFacts {
    let (burn_left, burn_temperature) = match &building.kind {
        sim::building::BuildingKind::Smelter(s) => (s.burn_left as i64, s.burn_temperature as i64),
        sim::building::BuildingKind::Machine(_) => (0, 0),
    };
    BuildingFacts {
        id: building.id.0 as i64,
        kind: building.kind.name().to_string(),
        name: sim::debug::building_name(world, building),
        pos: (building.pos.x, building.pos.y),
        status: sim::debug::building_status(world, building),
        footprint: building.kind.footprint(),
        parts: match &building.kind {
            sim::building::BuildingKind::Machine(machine) => machine
                .assembly
                .parts()
                .map(|part| part_fact(world, part))
                .collect(),
            sim::building::BuildingKind::Smelter(_) => Vec::new(),
        },
        species: building.material.species.0 as i64,
        lit: matches!(
            world.smelter_state(building),
            sim::SmelterState::Working { .. }
        ),
        stopped: world.building_state(building).halted(),
        slots: slot_facts(world, building),
        state: match world.building_state(building) {
            sim::BuildingState::Smelter(sim::SmelterState::Working { .. })
            | sim::BuildingState::Machine(sim::MachineState::Working { .. }) => "working",
            sim::BuildingState::Smelter(sim::SmelterState::Idle)
            | sim::BuildingState::Machine(sim::MachineState::Idle(_)) => "idle",
            sim::BuildingState::Smelter(sim::SmelterState::Stalled(_))
            | sim::BuildingState::Machine(sim::MachineState::Stalled(_)) => "stalled",
        }
        .to_string(),
        state_line: sim::debug::building_state_line(world, building),
        work: world
            .building_work(building)
            .map(|w| (i64::from(w.done), i64::from(w.total))),
        work_clause: sim::debug::work_clause(world, building),
        burn_left,
        burn_temperature,
    }
}

fn building_dict(building: &BuildingFacts) -> VarDictionary {
    vdict! {
        "id" => building.id,
        "kind" => &gstring(&building.kind).to_variant(),
        "name" => &gstring(&building.name).to_variant(),
        "pos" => Vector2i::new(building.pos.0, building.pos.1),
        "status" => &gstring(&building.status).to_variant(),
        "footprint" => Vector2i::new(building.footprint.0, building.footprint.1),
        // A PACKED ARRAY AND NOT A LIST OF DICTS. ASSA-94 cost me an unguarded
        // field for exactly this: a `Variant` is invisible from Rust, so a
        // packed array of strings is the one shape BOTH `cargo test` and a
        // GDScript guard can read.
        "parts" => &building.parts.iter().map(part_dict)
            .collect::<Array<VarDictionary>>().to_variant(),
        "species" => building.species,
        "lit" => building.lit,
        "stopped" => building.stopped,
        "slots" => &building.slots.iter().map(slot_dict)
            .collect::<Array<VarDictionary>>().to_variant(),
        "state" => &gstring(&building.state).to_variant(),
        "state_line" => &gstring(&building.state_line).to_variant(),
        // ABSENT AS `nil`, NOT AS A ZEROED PAIR, which is `designs_of`'s
        // treatment of `durability` for the same reason: `0 of 100` on a drill
        // standing on bare ground is a number that reads as a promise.
        "work" => &match building.work {
            Some((done, total)) => Vector2i::new(done as i32, total as i32).to_variant(),
            None => Variant::nil(),
        },
        // `nil` AND NOT `""`, for `work`'s own reason one line up: an empty
        // string is a label a row would draw as a blank, and the absence of a
        // batch is a fact the menu has to branch on rather than render.
        "work_clause" => &match &building.work_clause {
            Some(clause) => gstring(clause).to_variant(),
            None => Variant::nil(),
        },
        "burn_left" => building.burn_left,
        "burn_temperature" => building.burn_temperature,
    }
}

/// ONE STACK, SPELLED ONCE.
///
/// `inventory_of` inlined these six keys and a comment two hundred lines away
/// said why they matter: "the three item fields are spelled exactly as
/// `inventory_of` spells them, so `AssayActions.item_of_stack` builds the input
/// item out of an offer with no second rearranging function". A slot's contents
/// is a stack in exactly that sense — the thing a menu's put button sends back
/// — so it goes through the same function rather than a second copy that agrees
/// today. ASSA-146 is what a second copy of one spelling costs.
fn stack_dict(stack: &StackFacts) -> VarDictionary {
    vdict! {
        "kind" => &gstring(&stack.kind).to_variant(),
        "species" => stack.species,
        "species_name" => &gstring(&stack.species_name).to_variant(),
        "grade" => &gstring(&stack.grade).to_variant(),
        "count" => stack.count,
        "name" => &gstring(&stack.name).to_variant(),
    }
}

/// One row of block 6. The item's five keys are `stack_dict`'s, so a pack row
/// and a cost row are read by one function in GDScript; see [`CostEntry`] for
/// why `count` is not among them and `need` / `have` are.
fn cost_entry_dict(entry: &CostEntry) -> VarDictionary {
    vdict! {
        "kind" => &gstring(&entry.kind).to_variant(),
        "species" => entry.species,
        "species_name" => &gstring(&entry.species_name).to_variant(),
        "grade" => &gstring(&entry.grade).to_variant(),
        "name" => &gstring(&entry.name).to_variant(),
        "need" => entry.need,
        "have" => entry.have,
        "blocks" => entry.blocks,
    }
}

fn slot_dict(slot: &SlotFacts) -> VarDictionary {
    let mut out = vdict! {
        "role" => &gstring(&slot.role).to_variant(),
        "count" => slot.count,
        "cap" => slot.cap,
    };
    // SET ONLY WHEN THERE IS ONE, both of these: `held` absent means empty and
    // `insert_tag` absent means nothing can be put here. A key carrying "" for
    // either is a value a caller can accidentally use (`Insert` with an empty
    // slot name is a command the relay drops), where a missing key is a
    // mistake GDScript reports on the line that made it.
    if let Some(tag) = &slot.insert_tag {
        out.set("insert_tag", &gstring(tag).to_variant());
    }
    if let Some(held) = &slot.held {
        out.set("held", &stack_dict(held).to_variant());
    }
    out
}

fn slot_offers_dict(slot: &SlotOffersFacts) -> VarDictionary {
    vdict! {
        "slot" => &gstring(&slot.slot).to_variant(),
        "role" => &gstring(&slot.role).to_variant(),
        "offers" => &slot.offers.iter().map(insert_offer_dict)
            .collect::<Array<VarDictionary>>().to_variant(),
    }
}

fn insert_offer_dict(offer: &InsertOfferFacts) -> VarDictionary {
    let mut out = stack_dict(&offer.stack);
    // **ABSENT MEANS PRESSABLE**, the same treatment `insert_tag` and `held`
    // get one function up and for the same reason: a key carrying "" is a
    // value a caller can accidentally draw — an unpressable control with an
    // empty reason beside it — where a missing key is a mistake GDScript
    // reports on the line that made it. `has("refusal")` is the whole test.
    if let Some(why) = &offer.refusal {
        out.set("refusal", &gstring(why).to_variant());
    }
    out
}

/// The sim's reading of a design that does not exist: [`AssaySim::design_if_built`]'s
/// engine-free half, so `cargo test` can run it over thousands of worlds
/// without a Godot in the room. Same keys, same order.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DesignIfBuilt {
    /// "SAFE" / "UNCERTAIN" / "WILL BREAK", or EMPTY when the design is not one
    /// the rules allow — in which case nothing was weighed and the four numbers
    /// below are zero.
    pub verdict: String,
    /// The sim's own phrase for why not, from `sim::debug::assembly_error_phrase`,
    /// or empty when the design is legal. Never this crate's wording.
    pub fault: String,
    pub mass_low: i64,
    pub mass_high: i64,
    pub budget_low: i64,
    pub budget_high: i64,
}

impl DesignIfBuilt {
    fn refused(fault: String) -> Self {
        Self {
            verdict: String::new(),
            fault,
            mass_low: 0,
            mass_high: 0,
            budget_low: 0,
            budget_high: 0,
        }
    }
}

/// EVERY NUMBER THE BUILD SCREEN'S READOUT DRAWS, for a design that is not
/// built and whose parts came out of a pack one click at a time (ASSA-325, for
/// ASSA-317 / `assay-build-screen` §5.2).
///
/// **WHY THIS IS NOT THREE MORE FIELDS ON [`DesignIfBuilt`]**, which is where I
/// started. That question takes ONE species and ONE grade for the whole design,
/// and `only_the_frames_grade_moves_a_single_species_drill` says in its own
/// docstring why that is sound: *"IT IS THE FOUR NUMBERS AND NOT THE WHOLE
/// `StatRange`… the head contributes SPEED from hardness and DURABILITY from
/// strength, both of which DO scale"*. Mass and budget do not move with a
/// mounted part's grade; speed, durability and capacity do. Three fields on
/// that signature would be exact only for a uniform-grade design, and
/// `button_play.gd` asks it with one stack's grade. It is also the wrong shape
/// for the screen: §4's model is clicking parts **out of your pack**, and pack
/// rows carry their own species and grade.
///
/// **DURABILITY CROSSES AS SWINGS, NEVER AS THE POOL** — `debug::swings_afforded`
/// and no arithmetic here. See that function: an exact pool is the head's
/// effective strength, so a bar drawn off the pool would make a pick a free
/// assay (ADR 0003 amendment A10).
///
/// **`held` AND `hand_speed` ARE HERE SO THE CLIENT DECIDES NOTHING.** Which of
/// durability and capacity a design even has is the Game Director's display
/// ruling on ASSA-5 (drill wear is parked, so a planted design showing a pool
/// teaches a mechanic that does not exist), and the bare-hands baseline is her
/// ruling 5 on ASSA-6 — without it, `speed 23` looks like a tool and is in fact
/// slower than the hands that built it, which is a measured defect and not a
/// nicety. Both are the sim's facts and neither may be a GDScript constant.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DesignReadout {
    /// "SAFE" / "UNCERTAIN" / "WILL BREAK", or EMPTY when the rules refuse the
    /// design — in which case `fault` says why and EVERY number below is zero.
    pub verdict: String,
    /// The sim's own phrase for why not. Never this crate's wording.
    pub fault: String,
    pub mass_low: i64,
    pub mass_high: i64,
    pub budget_low: i64,
    pub budget_high: i64,
    pub speed_low: i64,
    pub speed_high: i64,
    /// What bare hands do, from `tuning::HAND_WORK_PER_TICK`. The baseline
    /// `speed` is only legible against. Zero on a refusal like everything else.
    pub hand_speed: i64,
    /// Swings, not the pool. Meaningless unless `held`.
    pub swings_low: i64,
    pub swings_high: i64,
    /// What a planted design buffers. Meaningless when `held`.
    pub capacity_low: i64,
    pub capacity_high: i64,
    /// True for a tool, false for a machine you plant. `Assembly::mount()`.
    pub held: bool,
    /// **THE THIRD STATE: a design with a slot still empty** (ASSA-329).
    ///
    /// `verdict` is empty and `fault` carries the sim's phrase for what is
    /// still missing, exactly as on a refusal — **and every number is REAL**,
    /// which is the whole difference. A build screen draws the bars moving as
    /// parts go in and puts `fault` where the verdict word goes; it decides
    /// nothing, which is why this is a flag from the sim and not a test on
    /// `fault`'s text in GDScript.
    ///
    /// Three states, so a host needs all three: `verdict` non-empty is a
    /// machine, this flag is a design being placed, and neither is a selection
    /// the rules throw out.
    pub unfinished: bool,
}

impl DesignReadout {
    /// A design the rules throw out: the fault and **nothing else**.
    ///
    /// Every number zero and `held` false, deliberately exhaustive rather than
    /// `..Default::default()`: a new field that forgot to be zeroed here is a
    /// client drawing a bar for a design that cannot exist, and the test
    /// `a_refused_design_crosses_no_numbers_at_all` reads the struct field by
    /// field so adding one without thinking about it goes red.
    fn refused(fault: String) -> Self {
        Self {
            verdict: String::new(),
            fault,
            mass_low: 0,
            mass_high: 0,
            budget_low: 0,
            budget_high: 0,
            speed_low: 0,
            speed_high: 0,
            hand_speed: 0,
            swings_low: 0,
            swings_high: 0,
            capacity_low: 0,
            capacity_high: 0,
            held: false,
            unfinished: false,
        }
    }
}

/// [`DesignReadout`] for the parts a pack row names, each with its own
/// material. `frame` and every entry of `mounted` is an item as
/// [`item_text`] spells one.
///
/// Engine-free so `cargo test` pins the numbers against `Assembly::stat_range`
/// — see `AssaySim::design_readout`.
pub fn design_readout_facts(world: &World, frame: &str, mounted: &[String]) -> DesignReadout {
    let read = |text: &str| serde_json::from_str::<Item>(text).ok();
    let Some(frame_item) = read(frame) else {
        return DesignReadout::refused(format!("{frame} is not an item"));
    };
    let mut items = Vec::with_capacity(mounted.len());
    for text in mounted {
        let Some(item) = read(text) else {
            return DesignReadout::refused(format!("{text} is not an item"));
        };
        items.push(item);
    }
    // STEP'S REFUSALS IN STEP'S ORDER, AND STEP'S OWN FUNCTION (ASSA-324):
    // `sim::assembly::plan` is what `PlayerCommand::Assemble` asks, so a
    // readout and the Build button cannot drift apart about which design is
    // legal. A readout that answered only the arithmetic would hand back
    // numbers for a design `Assemble` throws out.
    //
    // **THE EMPTY PACK IS THE POINT, not a shortcut.** This entry point has no
    // player and prices nothing — §5.2 is five bars, and have/need is block 6's
    // job (`debug::design_preview`). `plan` weighs an unaffordable design
    // anyway (the Game Director's ASSA-324 ruling), so the bars are the same
    // whatever the pack holds, and `MissingItems` is dropped on the floor by
    // reading `built` rather than `refusal`.
    //
    // It also closes a hole: this walked the chain itself with no species gate,
    // and `stat_range` indexes the roster raw, so `design_readout` on a
    // made-up index **panicked** — measured on main `e27ef54`, `index out of
    // bounds: the len is 6 but the index is 200`. Nothing in `client/` calls it
    // yet, and `item_json` will spell species 200 for anyone who asks.
    let empty = sim::inventory::Inventory::new();
    let planned = sim::assembly::plan(frame_item, &items, &world.species, &empty);
    // THREE STATES, AND THE SIM PICKS WHICH (ASSA-329). `design` gives the
    // arithmetic whether or not these parts are a machine yet; `built` says no
    // for a design still being placed, so the verdict word cannot leak onto
    // one. A build screen reads `unfinished` rather than testing `fault`'s
    // text, because deciding what a sentence means is the sim's job.
    let Some(design) = planned.design() else {
        let reason = planned.refusal().expect("a plan with no design refuses");
        return DesignReadout::refused(
            sim::debug::plan_refusal_phrase(world, None, reason)
                .expect("`plan` refuses only in its own four words"),
        );
    };
    let unfinished = planned.unfinished();
    let assembly = &design.assembly;
    let range = assembly.stat_range(&world.species);
    DesignReadout {
        // A HALF-BUILT DESIGN GETS NO VERDICT WORD AND NEVER A FOURTH ONE: the
        // sim's phrase for the empty slot goes in `fault`, where the refusal's
        // does, and the screen puts it where the verdict would have been.
        verdict: match unfinished {
            Some(_) => String::new(),
            None => range.verdict().label().to_string(),
        },
        fault: match unfinished {
            Some(e) => sim::debug::assembly_error_phrase(e),
            None => String::new(),
        },
        mass_low: range.low.mass as i64,
        mass_high: range.high.mass as i64,
        budget_low: range.low.budget as i64,
        budget_high: range.high.budget as i64,
        speed_low: range.low.speed as i64,
        speed_high: range.high.speed as i64,
        hand_speed: i64::from(sim::tuning::HAND_WORK_PER_TICK),
        swings_low: i64::from(sim::debug::swings_afforded(range.low.durability)),
        swings_high: i64::from(sim::debug::swings_afforded(range.high.durability)),
        capacity_low: range.low.capacity as i64,
        capacity_high: range.high.capacity as i64,
        held: assembly.mount() == Some(Mount::Held),
        unfinished: unfinished.is_some(),
    }
}

/// ONE TALLIED STACK OF A DESIGN'S BILL, with the pack's answer beside it
/// (ASSA-347, for block 6 of the build screen).
///
/// **TALLIED AND NOT PER SLOT**: two hoppers of one material are one entry
/// needing two, because `Assemble` spends all-or-nothing and a screen that
/// listed them twice would show two rows a player can half-afford.
///
/// The five item fields are spelled exactly as [`stack_dict`] spells a pack
/// stack — `item_of_stack` builds a command's item out of either with no second
/// rearranging function (ASSA-146) — and
/// `an_entry_spells_its_item_the_way_the_pack_row_does` holds that against
/// `inventory_facts` rather than against my memory of it.
///
/// **`count` IS NOT ONE OF THEM, ON PURPOSE.** A stack has one count; a cost
/// entry has two numbers about one item, so they are named for the question
/// they answer and in the Game Director's own words: `need 1 · have 2`
/// (§5.5), which is also what `AssayHud.cost_counts_line(need, have)` already
/// calls them.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CostEntry {
    pub kind: String,
    pub species: i64,
    pub species_name: String,
    pub grade: String,
    pub name: String,
    /// How many of this item the press would spend.
    pub need: i64,
    /// How many are in the pack now (`Inventory::count`).
    pub have: i64,
    /// **THE SIM'S BLOCKER, PROJECTED ONTO THE ROW THAT IS AT FAULT.**
    ///
    /// `plan` picks it with `cost.iter().find(…)` — the FIRST entry the pack
    /// cannot cover — and `AssemblyPlan`'s own docstring says centralising that
    /// exists to stop a preview "disagreeing about WHICH item is missing". So
    /// this crosses as a flag rather than leaving GDScript to compare items:
    /// the client marks where it is true and never works out where that is.
    ///
    /// **At most one entry carries it**, which is the shape of
    /// `missing: Option<Item>` and the reason it is a flag and not a count of
    /// shortfalls. The obvious wrong client (loop the bill, red every row whose
    /// `have` is short) looks identical until two rows are short, and
    /// `only_the_sims_own_blocker_is_marked_even_when_two_rows_are_short` is
    /// the test that tells them apart.
    pub blocks: bool,
}

/// WHAT A DESIGN WOULD COST ONE PLAYER, and the sentence the pack earns if it
/// cannot pay (ASSA-347).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DesignCost {
    /// One entry per tallied stack, in `Assembly::part_items` order: the frame
    /// first, then the mounted parts. **Empty means there is no design to
    /// price** — not a free one. A legal design always costs its frame.
    pub entries: Vec<CostEntry>,
    /// [`sim::debug::pack_refusal_phrase`], or `""` when the pack covers it.
    ///
    /// **THE SIM'S SENTENCE AND ONLY THIS ONE.** A design the rules throw out
    /// (not a part, no such slot, five hoppers on a four-hopper frame) is worded
    /// by `design_readout`'s `fault` and gets no entries and no refusal here:
    /// one sentence, one home. A caller that printed a slot fault in a
    /// have/need block would be telling a player their pack is the problem.
    pub refusal: String,
}

/// **WHAT A DESIGN WOULD COST THE PLAYER WHO IS HOLDING THE PARTS**, tallied by
/// `assembly::plan` and priced against their own inventory (ASSA-347).
///
/// `design_readout_facts` deliberately passes an EMPTY pack — the five bars are
/// the same whatever you hold — so nothing in the binding could price an
/// assembly at all, and `make_offers.cost` is the recipe's cost on the make
/// path. This is the other half, and it is a view of something already paid
/// for: both arms of [`sim::assembly::plan`] have carried `cost` and `missing`
/// since ASSA-324.
///
/// **A DESIGN STILL BEING PLACED IS PRICED TOO** (`plan`'s `Unfinished`): it
/// bills what is selected so far, so block 6's numbers move with every click
/// instead of appearing on the last one. That is ASSA-329's rule applied to the
/// bill rather than to the bars.
///
/// Engine-free so `cargo test` pins it against `plan` and `Inventory::count`,
/// the same split `design_readout_facts` and `inventory_facts` use.
pub fn design_cost_facts(
    world: &World,
    player: Option<PlayerId>,
    frame: &str,
    mounted: &[String],
) -> DesignCost {
    // An unknown player is an empty answer and not a panic, exactly as
    // `inventory_facts` has it: a client asks this every frame and may ask it
    // one frame before its `Welcome`.
    let Some(p) = player.and_then(|id| world.player(id)) else {
        return DesignCost::default();
    };
    let read = |text: &str| serde_json::from_str::<Item>(text).ok();
    let Some(frame_item) = read(frame) else {
        return DesignCost::default();
    };
    let mut items = Vec::with_capacity(mounted.len());
    for text in mounted {
        let Some(item) = read(text) else {
            return DesignCost::default();
        };
        items.push(item);
    }
    // STEP'S OWN FUNCTION, so the bill and the press cannot disagree about what
    // a design costs or about which stack blocks it. The species gate lives in
    // here too (`design_readout` panicked on a made-up index before ASSA-324
    // moved this call), and `item_json` will spell species 200 for anyone who
    // asks.
    let planned = sim::assembly::plan(frame_item, &items, &world.species, &p.inventory);
    let (cost, missing) = match &planned {
        sim::assembly::AssemblyPlan::Weighed { cost, missing, .. } => (cost, *missing),
        sim::assembly::AssemblyPlan::Unfinished { cost, missing, .. } => (cost, *missing),
        sim::assembly::AssemblyPlan::Refused(_) => return DesignCost::default(),
    };
    DesignCost {
        entries: cost
            .iter()
            .map(|stack| CostEntry {
                kind: stack.item.kind.name().to_string(),
                species: stack.item.species.0 as i64,
                species_name: world.species(stack.item.species).name().to_string(),
                grade: stack.item.grade.letter().to_string(),
                name: world.item_name(stack.item),
                need: stack.count as i64,
                have: p.inventory.count(stack.item) as i64,
                // The sim's choice, matched rather than recomputed: `plan`
                // tallies, so one item is one entry and this marks one row.
                blocks: missing == Some(stack.item),
            })
            .collect(),
        refusal: missing.map_or_else(String::new, |item| {
            sim::debug::pack_refusal_phrase(world, item)
        }),
    }
}

/// Weigh a design made entirely of one refined species at one grade.
///
/// ONE SPECIES AND ONE GRADE IS A LIMIT OF THE QUESTION, NOT OF THE MODEL:
/// `stat_range` bands each part from its own sheet, so a mixed design needs no
/// special case. The caller that exists is a scripted run that smelts one
/// deposit (ASSA-140), and taking an item per part would make the common ask
/// four arguments wide for a case nothing has yet.
pub fn design_if_built_facts(
    world: &World,
    frame: &str,
    mounted: &[String],
    species: i64,
    grade: &str,
) -> DesignIfBuilt {
    let Some(frame_kind) = PartKind::parse(frame) else {
        return DesignIfBuilt::refused(sim::debug::not_a_part_phrase(frame));
    };
    let Some(grade) = sim::Grade::parse(grade) else {
        return DesignIfBuilt::refused(format!("{grade} is not a grade"));
    };
    let Ok(id) = u8::try_from(species) else {
        return DesignIfBuilt::refused(format!("there is no species {species}"));
    };
    let species = SpeciesId(id);
    if world.species.get(usize::from(id)).is_none() {
        return DesignIfBuilt::refused(format!("there is no species {id} in this world"));
    }
    let material = Item::new(ItemKind::Refined, species, grade);
    let mut parts = Vec::with_capacity(mounted.len());
    for name in mounted {
        let Some(kind) = PartKind::parse(name) else {
            return DesignIfBuilt::refused(sim::debug::not_a_part_phrase(name));
        };
        parts.push(sim::assembly::Part::of(kind, material));
    }
    let assembly = Assembly::new(sim::assembly::Part::of(frame_kind, material), parts);
    if let Err(e) = assembly.validate() {
        return DesignIfBuilt::refused(sim::debug::assembly_error_phrase(e));
    }
    let range = assembly.stat_range(&world.species);
    DesignIfBuilt {
        verdict: range.verdict().label().to_string(),
        fault: String::new(),
        mass_low: range.low.mass as i64,
        mass_high: range.high.mass as i64,
        budget_low: range.low.budget as i64,
        budget_high: range.high.budget as i64,
    }
}

/// AN ITEM AS THE JSON A COMMAND CARRIES, spelled by serde. Empty string if the
/// kind or the grade will not parse, or if the species cannot be a `SpeciesId`:
/// a command naming species 300 is a bug, not a request.
///
/// Engine-free so `cargo test` can pin the shapes, which is the whole point of
/// it existing — see `AssaySim::item_json`.
pub fn item_text(kind: &str, species: i64, grade: &str) -> String {
    let Some(kind) = sim::item::ItemKind::parse(kind) else {
        return String::new();
    };
    let Some(grade) = sim::Grade::parse(grade) else {
        return String::new();
    };
    let Ok(species) = u8::try_from(species) else {
        return String::new();
    };
    serde_json::to_string(&Item::new(kind, SpeciesId(species), grade)).unwrap_or_default()
}

/// SERDE'S VERDICT ON A CLIENT'S OWN ITEM TEXT, re-spelled. Empty if it refuses.
/// Engine-free so `cargo test` can pin what it refuses — see `AssaySim::item_echo`.
pub fn item_echo_text(text: &str) -> String {
    match serde_json::from_str::<Item>(text) {
        Ok(item) => serde_json::to_string(&item).unwrap_or_default(),
        Err(_) => String::new(),
    }
}

/// THE SAME VERDICT FOR A WHOLE `PlayerCommand`. Empty if serde refuses it.
/// Engine-free so `cargo test` pins what it accepts — see `AssaySim::command_echo`.
pub fn command_echo_text(text: &str) -> String {
    match serde_json::from_str::<sim::PlayerCommand>(text) {
        Ok(command) => serde_json::to_string(&command).unwrap_or_default(),
        Err(_) => String::new(),
    }
}

/// A `ServerMsg::Welcome` for a fresh world with one player in it, exactly as
/// the relay writes one. Empty string if the seed will not parse.
///
/// Engine-free, and the relay's own shape: 6x4 chunks, and the player added by
/// `step` through `SystemCommand::AddPlayer` rather than pushed onto
/// `World::players`. See `AssaySim::fresh_welcome_json`.
pub fn fresh_welcome_text(seed: &str, name: &str) -> String {
    let Ok(seed) = seed.trim().parse::<u64>() else {
        return String::new();
    };
    // THE RELAY'S OWN CONSTRUCTOR, NOT A COPY OF ITS NUMBERS (ASSA-53). The
    // chunk counts were written out here as well as in `sim-relay`, so a change
    // to one would have left every client test passing against a world no relay
    // would send — and nothing would have gone red.
    let mut world = sim_net::fresh_world(seed);
    let joining = [Input::System(sim::SystemCommand::AddPlayer {
        name: name.to_string(),
    })];
    let mut events = Vec::new();
    sim::step::step(&mut world, &joining, &mut events);
    let welcomed = world
        .players
        .first()
        .map(|player| player.id)
        .unwrap_or(PlayerId(0));
    serde_json::to_string(&sim_net::ServerMsg::Welcome {
        player: welcomed,
        world,
    })
    .unwrap_or_default()
}

/// A `serde_json::Value` as the Variant GDScript can hand straight back to a
/// command — or `None` if it holds a NUMBER anywhere.
///
/// REFUSING NUMBERS IS THE WHOLE SAFETY OF THIS FUNCTION, and it is why there
/// is no general json-to-Variant helper in this crate. Godot parses every JSON
/// number as a double and serde will not take `3.0` for a `u8`, so a number
/// that crossed here would come back as a command the sim drops in silence.
/// The only callers are enum TAGS (`PartKind`, `RecipeId`), which hold no
/// numbers at all — so the refusal costs nothing here and makes the trap
/// unreachable for whoever reaches for this next.
fn tag_variant(value: &serde_json::Value) -> Option<Variant> {
    match value {
        serde_json::Value::Null => Some(Variant::nil()),
        serde_json::Value::Bool(flag) => Some(flag.to_variant()),
        serde_json::Value::Number(_) => None,
        serde_json::Value::String(text) => Some(gstring(text).to_variant()),
        serde_json::Value::Array(items) => {
            let mut out = Array::<Variant>::new();
            for item in items {
                out.push(&tag_variant(item)?);
            }
            Some(out.to_variant())
        }
        serde_json::Value::Object(fields) => {
            let mut out = VarDictionary::new();
            for (key, item) in fields {
                out.set(&gstring(key).to_variant(), &tag_variant(item)?);
            }
            Some(out.to_variant())
        }
    }
}

/// PLAIN DATA, NO ENGINE TYPES, on purpose: a `Dictionary` cannot be built
/// without the engine loaded, so anything shaped as one is untestable by
/// `cargo test`. Everything below is worked out here and wrapped above.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DepositFacts {
    pub id: i64,
    pub species: i64,
    pub species_name: String,
    pub center: (i32, i32),
    pub radius: i64,
    pub amount: i64,
    pub purity: i64,
    /// The sim's own band for that purity, as a letter.
    pub grade: String,
    pub depleted: bool,
    /// Whether this species' sheet is exact yet. The cue a player needs before
    /// spending ore on a machine whose mass is still a guess.
    pub assayed: bool,
    /// Whether anything in the game can mine this at all, straight from
    /// `sim::ladder::hand_minable` — the function `step` itself asks.
    ///
    /// **THE CLIENT MUST NOT WORK THIS OUT** (ASSA-43). A `hud.gd` that
    /// compared a hardness against 40 would be a second opinion about a rule,
    /// and the rule is not even "40": it is one function that `step`,
    /// `mine_by_machine`, the deposit line and this field all ask. It is a
    /// field and not a lookup through `species_facts` so that the one line
    /// that must not invite an assay has the fact in its own hand.
    pub hand_minable: bool,
    /// The sim's sentence for why this rock is a dead end, EMPTY when it is not.
    ///
    /// Same shape as [`BuildingFacts::status`]: wording the sim owns and a
    /// host only renders, so a planted drill and the rock under it can never
    /// tell a player two different stories about the same gate.
    ///
    /// **IT NOW CARRIES TWO KINDS OF DEAD END** (ASSA-52): too hard to break,
    /// and — the quieter one — minable but impossible to smelt. The name says
    /// "reach" because reach was the first, and the field is deliberately NOT
    /// renamed: `hud.gd` coded to the contract "the sim's sentence, empty when
    /// the rock yields", which is still exactly true, and renaming would churn
    /// a client file to no player's benefit. `sim::debug::deposit_dead_end_note`
    /// decides which sentence, hardness first.
    ///
    /// **`hand_minable` AND THIS ARE NO LONGER OPPOSITES.** A rock can be
    /// perfectly minable and still carry a sentence. Anything that treated an
    /// empty note as "minable" was reading a coincidence.
    pub reach_note: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BuildingFacts {
    pub id: i64,
    pub kind: String,
    /// What it IS, in the sim's words: `Tonore smelter (A)`. The same
    /// `debug::building_name` every other surface uses, so the window and the
    /// terminal cannot drift (ASSA-136). `kind` stays the bare noun for
    /// anything that needs to BRANCH on it; this is the one to show a player.
    pub name: String,
    pub pos: (i32, i32),
    pub status: String,
    /// **HAS IT STOPPED** — `World::building_state(b).halted()`, the same
    /// predicate `World::halted` filters on and so the same answer the
    /// `stopped` block renders. A bool and not a word, for `lit`'s reason:
    /// `status` is one prose sentence for a person, and a caller that branched
    /// on its shape would be deriving a rule from a rendering. ASSA-140 is the
    /// bill for exactly that — `button_play` asked `status.begins_with("mining")`
    /// and a machine reading `holding 0 of 210 · mining Minyte · …` was
    /// reported as stopped, so the demo's own proof mislabelled its payoff.
    pub stopped: bool,
    /// How many tiles it occupies, from `pos` as the TOP-LEFT of the footprint.
    /// A smelter is (2, 2) and a machine (1, 1) — `BuildingKind::footprint`, so
    /// a renderer never has to know which kinds are big.
    pub footprint: (i32, i32),
    /// The parts a machine is made of, frame first, in `Assembly::parts()`
    /// order. Empty for a smelter, which is not an assembly. This is here
    /// because a machine has NO single drawing: `art/rig.py` rule 2 is that one
    /// is drawn by overlaying whole part sprites at one frame position, so a
    /// renderer needs the list and the order.
    ///
    /// **THE SAME `PartFacts` THE BENCH MENU GETS** (`DesignFacts::parts`), and
    /// that is the point of the shape rather than a convenience: the drill in
    /// your bench and the drill standing on the map are ONE object, so they must
    /// be drawn from one set of facts or they will eventually disagree about
    /// what the thing you placed looks like (Maren's ruling 2 on ASSA-131).
    ///
    /// It was `Vec<String>` — kind names only — with ONE `grade` beside it taken
    /// off the frame. That could not draw a machine honestly: a `Part` carries
    /// its OWN `material` (species and grade), the sim lets you mount a grade-A
    /// head on a grade-C frame, and the sheets have a row per grade and a tint
    /// per species. A renderer given one grade and one species would have drawn
    /// every part of a mixed machine as the frame's material — a picture of a
    /// machine the player did not build.
    pub parts: Vec<PartFacts>,
    /// The species of the material it is built from, for anything that tints.
    pub species: i64,
    /// Whether there is a fire burning in it THIS TICK, which is the one thing
    /// the shipped sheet draws two ways (`smelter.png` rows `cold` and `lit`).
    ///
    /// A BOOLEAN AND NOT A TEMPERATURE, because the art has two rows and a
    /// renderer handed a number would have to invent the threshold — a second
    /// copy of a decision, which is what ASSA-128 cost us a day of false stall
    /// lines for. `false` for a machine: nothing in the sheets draws one yet.
    ///
    /// It is `SmelterState::Working`, the sim's own answer, and that carries
    /// the sim's own rule that fuel burns only while something is refining
    /// (`coal_only_burns_while_smelting`): a smelter sitting idle on a banked
    /// `burn_left` consumes nothing, so it is not a fire. THE EDGE I DID NOT
    /// RULE ON is `FireTooCool` — lit, too cool, burning nothing — which draws
    /// cold today and is the Game Director's to settle (ASSA-119 box 11).
    pub lit: bool,
    /// Every holder it has, in the sim's order. See [`SlotFacts`].
    pub slots: Vec<SlotFacts>,
    /// **WHICH OF THE THREE STANDING CONDITIONS THIS IS**, for branching and
    /// for colour: `"working"`, `"idle"` or `"stalled"`. One vocabulary across
    /// both kinds, from `BuildingState` — a caller asking "has this stopped?"
    /// should not have to learn two (`building.rs`'s own reason for that enum).
    ///
    /// `stopped` STAYS and is not this. The bool is the sim's judgement about
    /// whether a *person* is needed, and the two deliberately disagree: a
    /// smelter's `idle` is not a problem and a machine's always is
    /// (`MachineState::halted`). A client that derived one from the other would
    /// re-litigate ASSA-80's ruling in GDScript.
    pub state: String,
    /// That condition as the one sentence the sim writes for it
    /// (`debug::building_state_line`) — `stalled: no fuel`,
    /// `idle: deposit is mined out`, `mining Tonore`.
    ///
    /// **NOT A NEW WORDING, AND THAT IS WHY IT IS SEPARATE FROM `status`.** The
    /// menu needs the condition on its own line, in `FAILED` when it is a stall
    /// (Maren's ruling 5 on ASSA-316); `status` is the whole dense line the
    /// terminal table prints. Both are the same function's output, so they
    /// cannot say different things.
    pub state_line: String,
    /// How far through the unit in front of it, as `(done, total)`, or `None`
    /// when there is none — `World::building_work`. See [`sim::WorkReading`]
    /// for why it is a pair and never a fraction.
    pub work: Option<(i64, i64)>,
    /// That same batch as the sentence the sim writes for it
    /// (`debug::work_clause`) — `56 of 100 work toward the next unit`, `12 of
    /// 20 ticks into this batch` — or `None` exactly when [`Self::work`] is.
    ///
    /// **IT CROSSES BECAUSE THE NOUN IS A SIM DECISION AND A HOST MUST NOT
    /// PICK IT.** `work_clause`'s own docstring says so: *"a smelter's progress
    /// is ticks of a recipe and a drill's is work ... a host that picked the
    /// noun would be deciding which."* The machine menu draws the batch as a
    /// band off the pair (ASSA-339) and needs a label for it; with only the
    /// pair crossed, the only labels available to GDScript were a noun it had
    /// invented or no noun at all. Maren's ASSA-334 §6 measured this clause at
    /// 191 px and budgeted the row for it, so the words were always the plan —
    /// nothing had asked the binding for them. The pair STAYS: a band needs two
    /// numbers and this is one string.
    pub work_clause: Option<String>,
    /// Ticks of burn left in the unit currently in the fire, and how hot it is.
    /// Both zero when cold, and on a machine.
    ///
    /// Plain numbers and NOT a gauge, because the denominator — the full burn
    /// of a fuel unit, `reactivity * BURN_TICKS_PER_REACTIVITY` — is a rule,
    /// and a host multiplying it out would be writing that rule in GDScript.
    /// If the menu wants a burn band, that total becomes a sim function beside
    /// `building_work`; it is half a day and it is asked on ASSA-316 rather
    /// than guessed at here.
    pub burn_left: i64,
    pub burn_temperature: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TileFacts {
    pub in_bounds: bool,
    pub pos: (i32, i32),
    pub chunk: (i32, i32),
    pub chunks_from_spawn: i64,
    pub is_spawn: bool,
    /// The sim's word for the GROUND here, EMPTY when it has none: `spawn`,
    /// `no deposit here`, or nothing at all on a tile whose deposit does the
    /// talking (`sim::debug::ground_note`).
    ///
    /// Same contract as [`DepositFacts::reach_note`] — wording the sim owns and
    /// a host only renders — and it is here for the reason that field is:
    /// `hud.gd` spelled "empty ground" itself, so the cursor section called a
    /// tile empty on the line above the smelter standing on it (ASSA-146),
    /// while `sim-cli` and the inspector each held their own copy of the same
    /// sentence.
    ///
    /// **`is_spawn` STAYS, and is not this.** A caller that must BRANCH on the
    /// tile being spawn needs the bool; this is the one to show a player.
    pub ground_note: String,
    pub deposit: Option<DepositFacts>,
    pub building: Option<BuildingFacts>,
    pub players_here: Vec<String>,
}

/// ONE HOLDER OF A BUILDING, as a menu row needs it (ASSA-321, under
/// ASSA-316's machine menu).
///
/// Before this, the only thing that crossed about a building's contents was
/// `status` — one prose sentence. A menu built on that would have to parse
/// `in 3 Tonore ore (C) · fuel 0 (0 ticks burning at 0)`, which is ASSA-140's
/// bill: `button_play` asked `status.begins_with("mining")` and mislabelled
/// the demo's own payoff. `stopped` exists because of that incident; this is
/// the same remedy for the rest of the sentence.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SlotFacts {
    /// `SlotRole::name` — "input", "fuel", "output", "buffer". The sim's noun,
    /// so the window and the terminal cannot drift (ASSA-146).
    pub role: String,
    /// **THE STRING `PlayerCommand::Insert` DESERIALISES, OR `None`.** Taken
    /// from serde itself rather than typed here, because a tag this crate spelt
    /// by hand would be a second copy of the wire format: it would survive a
    /// variant rename and send a command the relay drops.
    ///
    /// `None` on the output slot and a machine's buffer, which are emptied by
    /// `Take`. A host with no tag cannot build an `Insert` for them at all, so
    /// a menu cannot offer a put control where the rules have no target — the
    /// refusal is structural, not remembered (ASSA-43).
    pub insert_tag: Option<String>,
    /// What is in it, or `None` for empty. The same `StackFacts` the pack rows
    /// get, so one stack is drawn one way wherever it is standing.
    pub held: Option<StackFacts>,
    /// How many units are in it: `held`'s count, or 0. Here as well as on
    /// `held` because a fill is `count` over `cap` whether or not the slot has
    /// anything in it, and an empty slot still has a band to draw.
    pub count: i64,
    /// What the sim will accept — the tuning cap for a smelter's slots, and the
    /// `Capacity` its parts give a machine. **A RATIO AS TWO SIM NUMBERS**
    /// (ASSA-276 move 3): nothing here is a percentage, and no host multiplies
    /// anything out to get the denominator.
    pub cap: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StackFacts {
    pub kind: String,
    pub species: i64,
    pub species_name: String,
    pub grade: String,
    pub count: i64,
    pub name: String,
}

/// ONE CARRIED STACK AGAINST ONE SLOT: the put control a machine menu draws,
/// and whether pressing it would do anything (ASSA-351).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InsertOfferFacts {
    /// The stack as the pack rows spell it, so a menu row and a put command
    /// are built from one dictionary and `AssayActions.item_of_stack` needs no
    /// rearranging (`stack_dict`'s own rule).
    pub stack: StackFacts,
    /// **`None` MEANS PRESSABLE.** Otherwise the sim's own sentence for why
    /// nothing would move — `sim::debug::insert_refusal`, which is the event
    /// log's wording byte for byte. Never this crate's and never GDScript's.
    pub refusal: Option<String>,
}

/// EVERY CARRIED STACK CROSSED AGAINST ONE INSERTABLE SLOT.
///
/// **THE CLIENT USED TO DERIVE THIS AND GOT IT WRONG FOUR CONTROLS OUT OF
/// FOUR** (ASSA-351). `hud.gd::insert_slots` keyed on the item's KIND alone,
/// out of the recipe table, and offered both slots on the honest ground that
/// *"which one a species is good for … is a sheet reading and only the sim has
/// it"*. The reading it was missing is that a REFUSAL is a sheet reading too:
/// grade, the held item, reactivity at grade, the walls' heat tolerance. In the
/// one 1x frame we have of a machine menu, all four put controls were acts
/// `sim::step` refuses — on the surface the board asked for by name.
///
/// So the crossing happens here, once, over `insert_rejection` — the same
/// function `step` itself calls, so a control cannot disagree with its press.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SlotOffersFacts {
    /// The wire tag `PlayerCommand::Insert` deserialises, from serde and not
    /// typed here — same source as `SlotFacts::insert_tag`.
    pub slot: String,
    /// What the sim calls this slot (`input`, `fuel`), for a row that wants to
    /// name it in prose rather than in a command.
    pub role: String,
    /// In the pack's own order, which is `Inventory`'s sorted order and so the
    /// same on every peer. **Every carried stack appears, refused or not —
    /// except the categorically wrong kind**: a pack of only grade-A refined
    /// must still open a menu with a named reason rather than an empty box
    /// (ASSA-301), but a gear is not a rung of any ladder and gets no row. See
    /// the `WrongItem` note in `insert_offer_facts`, which is the one
    /// judgement on this item the Game Director may want back.
    pub offers: Vec<InsertOfferFacts>,
}

/// ONE PART OF A DESIGN, as a menu row: kind, species, grade and mass, and
/// nothing else (Game Director's ruling on ASSA-7). Mass is the only number
/// that moves the verdict; every other sheet property belongs to the assay
/// panel, and over-showing is how a part menu becomes a spreadsheet.
///
/// `mass_low`/`mass_high` and not one number, for the same reason the headline
/// is a range: density is read off a sheet that bands until the species is
/// assayed. They are equal once it is.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PartFacts {
    pub kind: String,
    pub species: i64,
    pub species_name: String,
    /// The species' map letter, same source as a deposit's (`species_symbol`).
    /// A menu row already names its species in words, so this is not the row's
    /// non-colour read — it is how a player learns which letter on the map that
    /// name belongs to. Maren's ruling, 2026-10-02: once per deposit and once
    /// per row, never once per tile.
    pub symbol: String,
    pub grade: String,
    pub mass_low: i64,
    pub mass_high: i64,
}

/// ONE DESIGN A PLAYER HAS BUILT, as the part menu needs it.
///
/// EVERY JUDGEMENT IN HERE IS THE SIM'S. `verdict` is `BreakVerdict::label()`
/// off `Assembly::stat_range`, not three integers for a client to compare;
/// the masses and budgets are the sim's banded arithmetic; `durability` is the
/// pool the sim gave this machine. A second implementation of any of it would
/// be a second opinion, and two peers holding different opinions about whether
/// a design breaks is the one disagreement lockstep cannot absorb.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DesignFacts {
    /// Index into `Player::assemblies`, which is what `Equip` and
    /// `PlaceAssembly` take. -1 for the tool in hand, which has no index.
    pub index: i64,
    pub in_hand: bool,
    /// "SAFE" / "UNCERTAIN" / "WILL BREAK", the sim's own words.
    pub verdict: String,
    pub mass_low: i64,
    pub mass_high: i64,
    pub budget_low: i64,
    pub budget_high: i64,
    /// "held" or "planted", from the frame alone.
    pub mount: String,
    /// "90% of 2400-3600", or None on a planted design — the head contributes
    /// a pool whatever frame it sits on, but drill wear is parked, so on a
    /// planted machine the number would never move and would teach a mechanic
    /// that does not exist (Game Director's ruling on ASSA-5).
    pub durability: Option<String>,
    /// Species in this design whose sheet still reads rough, by name. THIS IS
    /// WHAT LETS "UNCERTAIN" NAME ITS OWN RESOLUTION — "assay Korvite to know"
    /// rather than a yellow border that reads as danger. Without it the state
    /// can only say "assay something", and 36.9% of the designs a player can
    /// build read UNCERTAIN (measured, 2000 worlds; ADR 0003 A8).
    pub unassayed: Vec<String>,
    /// **THE SIM'S SMALL PRINT FOR THIS VERDICT**, or `None` when the verdict is
    /// settled and good (ASSA-90). `sim::debug::verdict_note` writes it and the
    /// reference client prints the same string; before this the window composed
    /// its own from `unassayed` above and appended it whenever that list was
    /// non-empty, which offered an assay on a WILL BREAK design — an action
    /// that cannot move a verdict whose spans are already disjoint — and never
    /// said the design would break at all.
    ///
    /// `unassayed` stays because it is what the sentence is derived FROM, and a
    /// probe reads it. Whether the window should still be handed the raw list
    /// now that the sentence exists is the Game Director's call, asked on the
    /// item rather than decided here.
    pub note: Option<String>,
    pub parts: Vec<PartFacts>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// ONE QUESTION'S ANSWER, as the sim gave it (ASSA-254).
pub struct ProximityFacts {
    /// `debug::question_asked` -- the sim's label for the question, and also
    /// the prefix of `headline`.
    pub asked: String,
    /// `debug::proximity_headline`, VERBATIM. It already carries the species,
    /// the grade, the distance, the heading and both empty states.
    pub headline: String,
    /// The tile the answer is ABOUT, or `None` when nothing answers. The one
    /// fact the sentence cannot carry: a heading is true of the first step and
    /// false of the destination on a walk that is neither straight nor
    /// diagonal.
    ///
    /// **IT IS NOT "SOMEWHERE TO WALK TO", AND THAT DISTINCTION COST A DEAD
    /// BUTTON** (ASSA-263). It is the tile of the rock, which a map highlight
    /// will want later; whether there is a walk in it is [`Self::underfoot`].
    pub tile: Option<(i32, i32)>,
    /// Whether the answer is the tile the player is **already standing on**, in
    /// which case there is no walk to offer (ASSA-263).
    ///
    /// **WITHOUT THIS THE TAB SHIPPED A CONTROL THAT COULD ONLY WALK YOU WHERE
    /// YOU ALREADY WERE.** `debug::proximity_headline` says "right where you
    /// are standing" on `near.heading == None`, and `tile` is `Some` in exactly
    /// that case -- it is the tile under the player's feet. A client gating a
    /// button on `tile != null` therefore cannot tell "there is a rock to walk
    /// to" from "you are on it", and `mineralogy.gd` is forbidden to parse the
    /// sentence to find out. The Game Director photographed the result at
    /// 344 px on seed 14247 (ASSA-241, ruling 5: absent, not greyed).
    ///
    /// **A BOOL AND NOT `heading` OR `distance`, which ASSA-254 kept out on
    /// purpose.** Those two are already *in the sentence*, and sending them
    /// again invites a panel to render its own "15 tiles south-east" beside the
    /// sim's -- two vocabularies for one fact are free to disagree. A bool
    /// cannot be rendered as prose. It can only gate a control, which is the
    /// one thing the surface needed and the only reason it crosses.
    ///
    /// **FALSE WHEN NOTHING ANSWERS**, because nothing is underfoot then
    /// either. The two empty-ish states are different news and a host wants
    /// both: `tile == None` is "no answer at all", `underfoot` is "the answer
    /// is here". A control that offers a walk needs `tile.is_some() &&
    /// !underfoot`.
    pub underfoot: bool,
}

pub struct SpeciesFacts {
    pub id: i64,
    pub name: String,
    /// The species' map letter, from `sim::debug::species_symbol` — the SAME
    /// call a deposit's `symbol` and a part's come from. A species panel is
    /// only a legend if it carries the mark the map draws, and the one way to
    /// guarantee that is to read the same function rather than to agree with
    /// it. Never the name's first character: a player may rename a species and
    /// the letter does not follow (ASSA-73, Maren's glyph-and-tint ruling).
    pub symbol: String,
    pub assayed: bool,
    /// Property name to reading: the exact value once assayed, the sim's band
    /// ("26-50") until then.
    pub readings: Vec<(String, String)>,
    /// The same readings as their two ends, for a surface that DRAWS a
    /// reading instead of printing it (`sim::debug::reading_range`).
    ///
    /// Parallel to `readings` and from the same sim call, so the bar and the
    /// text beside it cannot disagree about one rock. An assayed reading is
    /// `(v, v)` — a point is a zero-width band, so a host draws one shape and
    /// needs no `assayed` branch of its own.
    pub reading_ranges: Vec<(String, (u8, u8))>,
    /// Still a bool and still sent, because two callers ask a yes/no question
    /// and neither of them is wording anything: the scripted session plan
    /// picks a deposit it can actually swing at, and the TILE line gates
    /// ASSA-47's reach invitation on it. What it may NOT be is the species
    /// panel's word for the mining axis — see `mining` below.
    pub hand_minable: bool,
    pub hand_lit_fuel: bool,
    /// **WHICH OF THE THREE MINING STATES, IN THE SIM'S OWN SENTENCE**
    /// (ASSA-135, Game Director). Byte-identical to what `species` prints in
    /// the terminal for this species.
    ///
    /// `hand_minable` above is a bit and the sim holds a three-state answer,
    /// so the window said "hand-minable" or said nothing: rock nothing can
    /// mine was rendered as the ABSENCE of a word, on the first screen a
    /// stranger reads, and 13.6% of deposits whose ore dead-ends were
    /// promised a smelter. This is the same move `lighting` made on ASSA-93
    /// for the ignition axis, and from the same function family.
    ///
    /// NOT optional, unlike `lighting`: every rock is in one of the three
    /// states, so there is no "the sim is silent here" case and a panel can
    /// never print a blank tag. The words come from
    /// `sim::debug::mining_note`; this crate words none of it and GDScript
    /// must never re-derive it from hardness.
    pub mining: String,
    /// **WHICH OF THE THREE LIGHTING STATES**, in the sim's own short label, or
    /// `None` when the sim does not call this rock fuel at all (ASSA-93).
    ///
    /// `hand_lit_fuel` above is a bit, and the sim holds a three-state answer:
    /// the window rendered a fuel nothing can light identically to a rock that
    /// is not fuel, and the board loaded 50 units of the first kind. The
    /// label comes from `sim::debug::lighting_tag` — this crate words none of
    /// it, and GDScript must not re-derive it from heat tolerance.
    ///
    /// Absent on a rock nothing can mine, for ASSA-68's reason: the lighting
    /// of something that can never enter an inventory is physics about a thing
    /// the player cannot touch, and the row already says it cannot be mined.
    pub lighting: Option<String>,
    /// **AT WHICH GRADE THIS ROCK IS FUEL AT ALL**, in the sim's own words, or
    /// `None` when no grade of it burns (ASSA-143).
    ///
    /// `lighting` above used to be computed from
    /// `fuel_grade(species).is_some()`: the binding called the function that
    /// holds the threshold and kept one bit of it, **on the line that computed
    /// it**. So the window said a rock was fuel and how it lit, and never at
    /// which grade — and on 18.8% of the rows it tags as fuel, grade C does
    /// not burn. A player reads "fuel, lights from cold", mines the nearest
    /// deposit and the fire stays cold.
    ///
    /// `sim::debug::fuel_tag` words all of it, including the "if you could
    /// mine it" conditional on rock nothing can mine; this crate words none of
    /// it and GDScript must never derive a grade from `readings`. Unlike
    /// `lighting` this is PRESENT on an unminable row, because the sim's own
    /// table says the fuel claim there too — ASSA-68 withheld the *lighting*
    /// of an untouchable rock, not the fact that it is fuel, and the clause
    /// carries its own conditional instead.
    pub fuel: Option<String>,
}

// Plain Rust, no engine types: everything here is reachable from `cargo test`.
impl AssaySim {
    /// Pull the `World` out of a `ServerMsg::Welcome`.
    pub fn world_from_welcome(text: &str) -> Result<World, String> {
        let value: serde_json::Value = serde_json::from_str(text).map_err(|why| why.to_string())?;
        let world = value
            .get("Welcome")
            .ok_or("not a Welcome message")?
            .get("world")
            .ok_or("a Welcome with no world in it")?;
        serde_json::from_value(world.clone()).map_err(|why| why.to_string())
    }

    /// Pull the `TickBundle` out of a `ServerMsg::Tick`.
    ///
    /// `Tick` is a NEWTYPE variant -- `Tick(TickBundle)`, not `Tick { .. }` --
    /// so serde writes `{"Tick": {"tick": 7, "inputs": []}}` and the bundle is
    /// the value, with no second level of naming.
    pub fn bundle_from_tick(text: &str) -> Result<TickBundle, String> {
        let value: serde_json::Value = serde_json::from_str(text).map_err(|why| why.to_string())?;
        let bundle = value.get("Tick").ok_or("not a Tick message")?;
        serde_json::from_value(bundle.clone()).map_err(|why| why.to_string())
    }

    /// The real work behind `apply_bundle_json`, callable without Godot.
    pub fn apply_bundle(&mut self, bundle: &TickBundle) -> bool {
        // A BUNDLE IS NUMBERED WITH THE TICK WE ARE AT, NOT THE ONE IT
        // PRODUCES, and I had this backwards until I read the relay: it builds
        // `TickBundle { tick: self.world.tick, .. }` and only then steps
        // (`sim-relay/src/main.rs`), `sim-net`'s `Welcome` says "the next
        // bundle you receive is for `world.tick`", and the reference client
        // refuses on `bundle.tick != world.tick` (`sim-cli/src/host.rs`). All
        // three agree; a `+ 1` here refused every bundle a real relay sends.
        if bundle.tick != self.world.tick {
            godot_warn!(
                "sim-godot: ignoring a bundle for tick {} while at tick {}",
                bundle.tick,
                self.world.tick
            );
            return false;
        }
        self.step_with(&bundle.inputs);
        true
    }

    /// Inputs, then exactly one `step`. The only way this crate changes a
    /// world.
    pub fn step_with(&mut self, inputs: &[Input]) {
        let mut events = Vec::new();
        sim::step::step(&mut self.world, inputs, &mut events);
        self.last_events = events;
    }

    pub fn hash_hex_string(&self) -> String {
        format!("{:016x}", fnv64(&self.world))
    }

    /// `hash_message_json` without Godot in the way, so a test can read the
    /// message back as a real `ClientMsg` and check the `u64` survived.
    pub fn hash_message_text(&self) -> Result<String, String> {
        serde_json::to_string(&ClientMsg::Hash {
            tick: self.world.tick,
            hash: self.world.state_hash(),
        })
        .map_err(|why| why.to_string())
    }

    pub fn seed_hex_string(&self) -> String {
        format!("{:016x}", self.world.seed)
    }

    pub fn seed_decimal_string(&self) -> String {
        self.world.seed.to_string()
    }

    /// A small fixed world for the load check. Small on purpose: the check
    /// runs on every exported build and must not cost a visible pause.
    pub fn self_check_world() -> World {
        World::new(WorldConfig {
            seed: 1,
            width_chunks: 2,
            height_chunks: 2,
        })
    }

    /// What the binding computes by stepping its own world once.
    pub fn self_check_value() -> String {
        let mut sim = Self::from_world(Self::self_check_world());
        sim.step_with(&[]);
        sim.hash_hex_string()
    }

    /// The same number by the other route: `sim::step` called directly, with
    /// no `AssaySim` in the way.
    pub fn self_check_expected_value() -> String {
        let mut world = Self::self_check_world();
        let mut events = Vec::new();
        sim::step::step(&mut world, &[], &mut events);
        format!("{:016x}", fnv64(&world))
    }

    pub fn from_world(world: World) -> Self {
        Self {
            world,
            last_events: Vec::new(),
        }
    }

    pub fn world(&self) -> &World {
        &self.world
    }

    fn world_events(&self) -> PackedStringArray {
        self.last_events
            .iter()
            .map(|event| gstring(&format!("{event:?}")))
            .collect()
    }

    /// One player's stacks, in the sim's own sorted order. An unknown player is
    /// an empty inventory, not a panic: a client asks this every frame and may
    /// ask it one frame before it has been welcomed.
    pub fn inventory_facts(&self, player: Option<PlayerId>) -> Vec<StackFacts> {
        let Some(player) = player.and_then(|id| self.world.player(id)) else {
            return Vec::new();
        };
        player
            .inventory
            .stacks()
            .iter()
            .map(|stack| StackFacts {
                kind: stack.item.kind.name().to_string(),
                species: stack.item.species.0 as i64,
                species_name: self.world.species(stack.item.species).name().to_string(),
                grade: stack.item.grade.letter().to_string(),
                count: stack.count as i64,
                name: self.world.item_name(stack.item),
            })
            .collect()
    }

    /// Engine-free half of [`AssaySim::insert_offers`] — see
    /// [`SlotOffersFacts`] for why this crossing is the sim's and not the
    /// client's.
    ///
    /// **THE SLOTS COME FROM `slot_facts`, NOT FROM A PAIR THIS FUNCTION
    /// KNOWS ABOUT.** A smelter has two insertable slots and an output that
    /// takes nothing; a machine's buffer takes nothing either. Walking
    /// `insert_tag` means a surface drawn from this cannot offer a put control
    /// where the rules have no target — the same structural refusal
    /// `SlotFacts::insert_tag` already carries, rather than a second list that
    /// agrees today.
    ///
    /// Empty for an unknown player or building, and empty for a building with
    /// no insertable slot: a menu with nothing to put is a menu with no rows,
    /// which is different from a menu whose rows are all refused.
    pub fn insert_offer_facts(
        &self,
        player: Option<PlayerId>,
        building: i64,
    ) -> Vec<SlotOffersFacts> {
        let Some(player) = player else {
            return Vec::new();
        };
        let Some(id) = u32::try_from(building).ok().map(sim::BuildingId) else {
            return Vec::new();
        };
        let Some(b) = self.world.building(id) else {
            return Vec::new();
        };
        let stacks: Vec<sim::ItemStack> = match self.world.player(player) {
            Some(p) => p.inventory.stacks().to_vec(),
            None => return Vec::new(),
        };
        let mut out = Vec::new();
        for (role, _, _) in self.world.building_slots(b) {
            let Some(slot) = role.insertable() else {
                continue;
            };
            let Some(tag) = insert_tag(slot) else {
                continue;
            };
            let offers = stacks
                .iter()
                .filter_map(|stack| {
                    // **THE WHOLE OFFER, NOT ONE UNIT.** The control a player
                    // presses is `put all N`, so the question asked here is
                    // the one the button sends. A clamp is not a refusal
                    // (ASSA-48), so `put all 50` at a slot with room for 3
                    // answers `None` and still inserts 3.
                    let reason = sim::step::insert_rejection(
                        &self.world,
                        player,
                        id,
                        slot,
                        stack.item,
                        stack.count,
                    );
                    // **`WrongItem` IS THE ONE REFUSAL THAT GETS NO ROW, and
                    // this is my narrowing of the Game Director's box 4 — it
                    // is the thing on this item to disagree with.** She ruled
                    // no refused control hidden, so that a pack of grade-A
                    // refined opens a menu with a named reason rather than an
                    // empty box. Read literally over every carried stack it
                    // also draws your gears, your spare smelter and your pick
                    // handle as dead fuel controls, two rows each: ten dead
                    // rows to teach the ladder with two, which is the hierarchy
                    // complaint that made this P1, inverted again.
                    //
                    // `WrongItem` is the only reason that is CATEGORICAL — no
                    // grade, no world state and no emptying of a slot makes a
                    // gear smelter input, which is what `plan_refusal_phrase`
                    // says about `NotAPart` in the same words. Every other
                    // reason is a rung: `AlreadyBestGrade` says you are at the
                    // top of one, `TooHotForWalls` says build a better smelter,
                    // `NotFuel` says this rock will not burn, `SlotFull` says
                    // empty it. Those teach; "a gear is not ore" does not.
                    //
                    // This is still the sim's judgement and not a kind filter
                    // come back: the client no longer reads the recipe table at
                    // all, and `WrongItem` is the rules' own word for the
                    // categorical case. Choosing AMONG the sim's answers is a
                    // caller's business; deriving one is not (`designs_of`).
                    if matches!(reason, Some(sim::RejectReason::WrongItem)) {
                        return None;
                    }
                    Some(InsertOfferFacts {
                        stack: StackFacts {
                            kind: stack.item.kind.name().to_string(),
                            species: stack.item.species.0 as i64,
                            species_name: self.world.species(stack.item.species).name().to_string(),
                            grade: stack.item.grade.letter().to_string(),
                            count: stack.count as i64,
                            name: self.world.item_name(stack.item),
                        },
                        refusal: reason.map(|_| {
                            sim::debug::insert_refusal(
                                &self.world,
                                player,
                                id,
                                slot,
                                stack.item,
                                stack.count,
                            )
                            .expect("the chain just returned a reason for this very press")
                        }),
                    })
                })
                .collect();
            out.push(SlotOffersFacts {
                slot: tag,
                role: role.name().to_string(),
                offers,
            });
        }
        out
    }

    /// Engine-free half of [`AssaySim::halt_lines`], so the rule it carries can
    /// be tested without an engine: a `PackedStringArray` cannot be built in a
    /// unit test at all (godot-ffi panics with "Godot engine not available"),
    /// which is why every readout in this crate is split this way.
    ///
    /// What is worth testing here is not the conversion — it is that the lines
    /// come from `World::halted` and so inherit its judgement about which
    /// standing states need a person. The Variant side is guarded from
    /// GDScript, in `tests/test_sim_binding.gd`, because that is the only side
    /// that can see it (ASSA-105).
    /// `Audience::Pointed` for the same reason `describe` uses it (ASSA-222):
    /// this reader has a mouse, not a command line, so the `BuildingId` that
    /// used to sit between the grade and the tile is a number with nothing to
    /// type it into. The tile stays — that is how you find the thing.
    pub fn halt_line_texts(&self) -> Vec<String> {
        sim::debug::halt_lines(&self.world, sim::debug::Audience::Pointed)
    }

    /// Engine-free half of [`AssaySim::attention_lines`] and
    /// [`AssaySim::attention_conditions`] **at once, which is the whole point**
    /// (ASSA-300).
    ///
    /// The two `#[func]`s above are each one `map` over this, so a line and its
    /// kind are produced by the same `filter_map` over the same event. The
    /// alternative — two functions each matching the loud set — is how one of
    /// them quietly stops covering a variant, which is the mistake
    /// `event_needs_attention` was collapsed into `sim::debug::attention` to
    /// prevent one layer down.
    ///
    /// `None` is an ACT: something that happened, which nothing can un-happen,
    /// so there is nothing to re-ask and no host may age it out (ASSA-239).
    pub fn attention_pairs(&self, who: Option<PlayerId>) -> Vec<(String, Option<BuildingId>)> {
        self.last_events
            .iter()
            .filter_map(|event| {
                let kind = sim::debug::attention(who, event)?;
                let about = match kind {
                    sim::debug::AttentionKind::Act => None,
                    sim::debug::AttentionKind::Condition { building } => Some(building),
                };
                Some((self.describe(who, event), about))
            })
            .collect()
    }

    /// EVERY BUILDING IN THE WORLD, FOR DRAWING, in the world's own order.
    ///
    /// ASSA-119. Until now a building was reachable only through `tile_facts`'s
    /// `building` key, one tile at a time — which is 500-odd dictionary
    /// allocations a frame over a 28x18 camera window, and still blind to the
    /// 2x2 smelter whose other half is one tile outside it. A renderer wants
    /// the list, the way it already gets `players()` and `deposits()`.
    ///
    /// THE SHAPE IS THE SIM'S AND THE RENDERER DERIVES NOTHING: the footprint,
    /// the part list and its order, and the grade all arrive decided. A client
    /// that worked out which kinds are 2x2, or stacked the parts in an order of
    /// its own, would draw a machine the game cannot build. That is the rule
    /// `Assembly::parts()` exists for — "every rule that has to pick a part
    /// walks that order, so two peers can never disagree".
    ///
    /// Engine-free so `cargo test` can pin it; `AssaySim::buildings` is the
    /// thin half. A `PackedStringArray` cannot be built in a Rust unit test at
    /// all (godot-ffi panics), which is why that split is not optional here.
    pub fn building_facts(&self) -> Vec<BuildingFacts> {
        self.world
            .buildings
            .iter()
            .map(|building| building_fact(&self.world, building))
            .collect()
    }

    /// What is on a tile. Out of bounds is reported, not hidden: a cursor is
    /// off the map most of the time and the readout has to say so.
    pub fn tile_facts(&self, x: i32, y: i32) -> TileFacts {
        let at = TilePos::new(x, y);
        let chunk = at.chunk();
        let in_bounds = self.world.in_bounds(at);
        TileFacts {
            in_bounds,
            pos: (x, y),
            chunk: (chunk.x, chunk.y),
            chunks_from_spawn: chunk.distance(self.world.spawn) as i64,
            is_spawn: at == self.world.spawn_tile(),
            ground_note: sim::debug::ground_note(&self.world, at).to_string(),
            deposit: if in_bounds {
                self.world.deposit_at(at).map(|deposit| DepositFacts {
                    id: deposit.id.0 as i64,
                    species: deposit.species.0 as i64,
                    species_name: self.world.species(deposit.species).name().to_string(),
                    center: (deposit.center.x, deposit.center.y),
                    radius: deposit.radius as i64,
                    amount: deposit.amount as i64,
                    purity: deposit.purity as i64,
                    grade: deposit.grade().letter().to_string(),
                    depleted: deposit.is_depleted(),
                    assayed: self.world.species(deposit.species).assayed,
                    hand_minable: sim::ladder::hand_minable(self.world.species(deposit.species)),
                    reach_note: sim::debug::deposit_dead_end_note(&self.world, deposit)
                        .unwrap_or_default(),
                })
            } else {
                None
            },
            building: if in_bounds {
                self.world
                    .building_at(at)
                    .map(|building| building_fact(&self.world, building))
            } else {
                None
            },
            players_here: self
                .world
                .players
                .iter()
                .filter(|player| player.pos == at)
                .map(|player| player.name.clone())
                .collect(),
        }
    }

    /// Every species as the players know it. THE BANDS ARE THE SIM'S
    /// (`sim::debug::reading`): a rough sheet is a 25-wide interval and a client
    /// that printed a single number from it would be inventing certainty.
    /// WHAT NEAR THIS PLAYER ANSWERS THE QUESTIONS — **one entry per ANSWER,
    /// which is not one per question** (ASSA-272, on top of ASSA-254 and the
    /// client leg of ASSA-241). When the same patch is the nearest answer to
    /// both questions, the sim returns a single entry whose label names both,
    /// so a panel that renders every entry in order renders the merge for free.
    ///
    /// **THE SENTENCE IS THE SIM'S, VERBATIM.** The Game Director's ruling is
    /// that the tab opens on one line answering the question, with the species
    /// table as evidence under it, so what crosses is the line itself --
    /// including both empty states, which are different news:
    /// `nothing_answers` where no patch can ever answer, `too_poor_answer`
    /// where a species would answer from a richer patch. A client composing
    /// any of that from parts would eventually disagree with the CLI printing
    /// the same line.
    ///
    /// **`distance` AND `heading` ARE DELIBERATELY ABSENT.** They are in the
    /// sentence. Sending them again would invite a panel to render its own
    /// "15 tiles south-east" beside the sim's, and two vocabularies for one
    /// fact are free to disagree.
    ///
    /// AN UNKNOWN PLAYER GETS AN EMPTY VEC, not a row of apologies:
    /// `proximity_headline` has its own "no such player" sentence and that
    /// belongs in a log, not in a mineralogy tab.
    pub fn proximity_facts(&self, player: Option<PlayerId>) -> Vec<ProximityFacts> {
        let Some(id) = player else {
            return Vec::new();
        };
        // **THE WHOLE ANSWER SET COMES FROM THE SIM NOW, INCLUDING HOW MANY
        // ANSWERS THERE ARE** (ASSA-272). This method used to loop
        // `Question::ALL` and build one entry each -- which is precisely the
        // shape that cannot express "one patch answers both", because nothing
        // inside a per-question call knows what the other question picked. The
        // search, the grouping, the sentence, the tile and the walk now all
        // come off one `debug::proximity_headlines` call, so this host cannot
        // disagree with the terminal about any of them.
        sim::debug::proximity_headlines(&self.world, id)
            .into_iter()
            .map(|answer| ProximityFacts {
                asked: answer.asked,
                headline: answer.line,
                tile: answer.tile.map(|t| (t.x, t.y)),
                underfoot: answer.underfoot,
            })
            .collect()
    }

    pub fn species_facts(&self) -> Vec<SpeciesFacts> {
        self.world
            .species
            .iter()
            .map(|species| SpeciesFacts {
                id: species.id.0 as i64,
                name: species.name().to_string(),
                symbol: sim::debug::species_symbol(species).to_string(),
                assayed: species.assayed,
                readings: Property::ALL
                    .into_iter()
                    .map(|property| {
                        (
                            property.name().to_string(),
                            sim::debug::reading(species, property),
                        )
                    })
                    .collect(),
                reading_ranges: Property::ALL
                    .into_iter()
                    .map(|property| {
                        (
                            property.name().to_string(),
                            sim::debug::reading_range(species, property),
                        )
                    })
                    .collect(),
                hand_minable: sim::ladder::hand_minable(species),
                hand_lit_fuel: sim::ladder::hand_lit_fuel(species),
                mining: sim::debug::mining_note(sim::debug::mining(
                    &self.world.species,
                    species.id,
                ))
                .to_string(),
                // ONE CALL TO `fuel_grade`, AND THE GRADE SURVIVES IT
                // (ASSA-143). This was `fuel_grade(species).is_some()` twice
                // over, which is how the threshold came to be computed and
                // dropped on one line.
                fuel: sim::ladder::fuel_grade(species)
                    .map(|grade| sim::debug::fuel_tag(grade, sim::ladder::hand_minable(species))),
                lighting: (sim::ladder::fuel_grade(species).is_some()
                    && sim::ladder::hand_minable(species))
                .then(|| {
                    sim::debug::lighting_tag(sim::ladder::lighting(&self.world.species, species.id))
                        .to_string()
                }),
            })
            .collect()
    }

    /// EVERY DESIGN ONE PLAYER HOLDS: the tool in hand first, then the built
    /// list in its own order, because `Equip` and `PlaceAssembly` index that
    /// order and a menu that reordered it would send the wrong one.
    ///
    /// Empty for a player the world does not have, and for one who has built
    /// nothing — which is every player until the craft chain runs.
    /// `[material, fuel]`, or empty. Engine-free half of `starter_pair`.
    pub fn starter_pair_ids(&self) -> Vec<i32> {
        match sim::ladder::starter_species(&self.world.species) {
            Some((material, fuel)) => vec![i32::from(material.0), i32::from(fuel.0)],
            None => Vec::new(),
        }
    }

    pub fn design_facts(&self, player: Option<PlayerId>) -> Vec<DesignFacts> {
        let Some(p) = player.and_then(|id| self.world.player(id)) else {
            return Vec::new();
        };
        let mut out = Vec::new();
        if let Some(tool) = &p.tool {
            out.push(self.design(-1, true, tool));
        }
        for (i, built) in p.assemblies.iter().enumerate() {
            out.push(self.design(i as i64, false, built));
        }
        out
    }

    fn design(&self, index: i64, in_hand: bool, built: &Built) -> DesignFacts {
        let a = &built.assembly;
        let range = a.stat_range(&self.world.species);

        let mut unassayed: Vec<String> = Vec::new();
        for part in a.parts() {
            let species = self.world.species(part.material.species);
            if !species.assayed && !unassayed.iter().any(|n| n == species.name()) {
                unassayed.push(species.name().to_string());
            }
        }
        DesignFacts {
            index,
            in_hand,
            verdict: range.verdict().label().to_string(),
            mass_low: range.low.mass as i64,
            mass_high: range.high.mass as i64,
            budget_low: range.low.budget as i64,
            budget_high: range.high.budget as i64,
            mount: match a.mount() {
                Some(Mount::Held) => "held".to_string(),
                Some(Mount::Planted) => "planted".to_string(),
                // A frame that is not a frame cannot be assembled, so this is
                // unreachable rather than a state to design for.
                None => "unmountable".to_string(),
            },
            // THE SIM'S OWN WORDING, not a second one. ADR 0003 A10 is a rule
            // about what a player may know -- the exact pool divided by a
            // published constant IS the head's effective strength -- so a menu
            // spelling it its own way is how the leak comes back in one host
            // and not the other.
            durability: match a.mount() {
                Some(Mount::Held) => Some(sim::debug::durability_readout(&self.world, built)),
                _ => None,
            },
            note: sim::debug::verdict_note(&self.world.species, a),
            unassayed,
            parts: a.parts().map(|part| part_fact(&self.world, part)).collect(),
        }
    }

    /// One event as a sentence, FROM THE SIM, which is the only copy of that
    /// wording now.
    ///
    /// This used to be a 215-line match of its own, and the duplication was not
    /// theoretical: it had no arm for any of the events the assembly model added,
    /// so it fell to `format!("{other:?}")` and showed players raw Rust `Debug`
    /// at the most dramatic moment in the game -- `MachineBroke { player:
    /// PlayerId(0), ... }` where Maren's ruling asks for "that design was too
    /// heavy". Nerite caught it; the probe's own evidence run printed it.
    ///
    /// THE FALLBACK ARM IS GONE BECAUSE THE MATCH IS GONE. PR #23 added that arm
    /// for a real reason -- an exhaustive `match Event` HERE made the client a
    /// brake on the sim's build -- and deleting the match keeps that property
    /// while removing the hole it left: `sim::debug::event_line` is exhaustive in
    /// the crate that owns `Event`, so a new variant now fails to compile for the
    /// person adding it, who is the one who knows what it should say.
    /// **`Pointed` IS THIS HOST'S ONE WORD IN THE DESCRIBER** (ASSA-222). It is
    /// not "the Godot wording": `sim::debug::Audience` names what a reader can
    /// address a building with, and in this host that is a mouse, so a
    /// `BuildingId` is a number with nothing to type it into. The sim is not
    /// told a window exists; it is told this reader points.
    ///
    /// IT IS SET HERE AND NOWHERE ELSE ON PURPOSE. `event_lines` and
    /// `attention_lines` both map `last_events` through this one call, which is
    /// what makes the loud line the SAME STRING as its log line rather than a
    /// second rendering that agrees today -- and `event_needs_attention` still
    /// picks which lines those are, for both audiences.
    pub fn describe(&self, me: Option<PlayerId>, event: &Event) -> String {
        sim::debug::event_line(&self.world, me, event, sim::debug::Audience::Pointed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    // **THE BINDING ITSELF NO LONGER ASKS ONE QUESTION AT A TIME** (ASSA-272):
    // `proximity_facts` takes the sim's whole answer list, so these two are
    // needed only here -- by the test that checks a merged line against the two
    // single-question sentences it replaces.
    use sim::debug::proximity_headline;
    use sim::proximity::Question;

    /// **THE LABEL THIS BINDING HANDS THE WINDOW IS THE SIM'S CONSTANT, NOT A
    /// COPY OF IT** (ASSA-158).
    ///
    /// The whole point of exposing it was that the window had been drawing a
    /// dead end in the cost's voice, and the fix must not be a second place
    /// where the Game Director's wording lives. `gstring` round-trips, so this
    /// also catches the label arriving empty — which would put an unlabelled
    /// clause back in the same series.
    #[test]
    fn the_dead_end_label_is_the_sims_own_word() {
        // **THE ENGINE-FREE HALF, AND A UNIT TEST HAS NO CHOICE.** Calling the
        // `#[func]` here panics in godot-ffi — "Godot binding accessed before
        // initialization" — because `gstring` touches the engine, which is the
        // same reason `halt_line_texts` exists beside `halt_lines`. I wrote the
        // `#[func]` version of this test first and it did exactly that.
        let exposed = AssaySim::dead_end_label_text();
        assert_eq!(
            exposed,
            sim::debug::DEAD_END_LABEL,
            "the binding is handing the window a different word from the one \
             `sim-cli`'s catalogue prints"
        );
        assert!(
            !exposed.trim().is_empty(),
            "an empty label puts the dead end back in the cost's series"
        );
    }

    /// GDScript gets the rules identity from here, as text, and puts it in
    /// `Hello` (ASSA-40). Sixteen hex digits is also what stops it being
    /// mangled: a client whose id arrived through a double would be refused
    /// by every host, which is the least debuggable failure available.
    #[test]
    fn the_rules_identity_crosses_as_the_sims_own_hex_text() {
        let id = AssaySim::rules_id_string();
        assert_eq!(id, sim::RULES_ID);
        assert_eq!(id.len(), 16, "{id}");
        assert!(id.chars().all(|c| c.is_ascii_hexdigit()), "{id}");
    }

    // Only the tests name these now: the event wording they used to feed is
    // `sim::debug::event_line`'s, and this crate no longer matches on `Event`.
    use sim::building::Slot;
    use sim::command::StopReason;

    /// The relay's own world, so these tests exercise the shape a client is
    /// actually sent rather than a copy of it that can drift (ASSA-53).
    fn fresh() -> World {
        sim_net::fresh_world(4242)
    }

    /// THE WHOLE POINT OF THE CRATE: stepping here must land on the same hash
    /// the rest of the sim would. Read from the sim, never pinned — the
    /// golden hash moved twice on 2026-10-01 alone.
    #[test]
    fn stepping_through_the_binding_matches_stepping_the_sim_directly() {
        let mut theirs = fresh();
        let mut events = Vec::new();
        sim::step::step(&mut theirs, &[], &mut events);

        let mut ours = AssaySim::from_world(fresh());
        ours.step_with(&[]);

        assert_eq!(
            ours.hash_hex_string(),
            format!("{:016x}", fnv64(&theirs)),
            "the binding stepped to a different world than the sim did"
        );
    }

    /// A hash crosses as 16 hex digits and never as a number.
    #[test]
    fn the_hash_is_sixteen_hex_digits() {
        let sim = AssaySim::from_world(fresh());
        let hex = sim.hash_hex_string();
        assert_eq!(hex.len(), 16, "got {hex}");
        assert!(hex.chars().all(|c| c.is_ascii_hexdigit()), "got {hex}");
    }

    /// A seed too big for a double survives as text. This is the case that
    /// silently corrupts if anyone "simplifies" it to a number later.
    #[test]
    fn a_seed_past_two_to_the_53_survives_as_text() {
        let mut world = fresh();
        world.seed = u64::MAX - 1;
        let sim = AssaySim::from_world(world);
        assert_eq!(sim.seed_hex_string(), "fffffffffffffffe");
        // And in decimal, which is what goes on screen.
        assert_eq!(sim.seed_decimal_string(), "18446744073709551614");
        // What a double would have done to it:
        assert_ne!((u64::MAX - 1) as f64 as u64, u64::MAX - 1);
    }

    /// Out-of-order bundles are refused, not guessed at. BOTH DIRECTIONS: the
    /// off-by-one I actually shipped was accepting `tick + 1`, which refuses
    /// every bundle a real relay sends, and a test that only checked `+ 5`
    /// could not tell the two conventions apart.
    #[test]
    fn a_bundle_for_any_tick_but_ours_changes_nothing() {
        for wrong in [5_i64, 1, -1] {
            let mut sim = AssaySim::from_world(fresh());
            let before = sim.hash_hex_string();
            let at = sim.world().tick;
            let bundle = TickBundle {
                tick: (at as i64 + wrong) as u64,
                inputs: Vec::new(),
            };
            assert!(!sim.apply_bundle(&bundle), "accepted tick {at}{wrong:+}");
            assert_eq!(
                sim.hash_hex_string(),
                before,
                "a refused bundle still changed the world"
            );
            assert_eq!(sim.tick(), at as i64, "a refused bundle still advanced us");
        }
    }

    /// A BUNDLE IS NUMBERED WITH THE TICK WE ARE AT, and applying it puts us on
    /// the next one. The relay builds the bundle before it steps, `sim-net`'s
    /// `Welcome` says the next bundle is for `world.tick`, and `sim-cli` refuses
    /// anything else -- so this is the one convention, not a choice.
    #[test]
    fn a_bundle_numbered_with_our_own_tick_advances_us_one() {
        let mut sim = AssaySim::from_world(fresh());
        let start = sim.tick();
        let next = TickBundle {
            tick: sim.world().tick,
            inputs: Vec::new(),
        };
        assert!(sim.apply_bundle(&next));
        assert_eq!(sim.tick(), start + 1);
        // And the one after it, so an off-by-one cannot pass by being wrong
        // only once.
        let after = TickBundle {
            tick: sim.world().tick,
            inputs: Vec::new(),
        };
        assert!(sim.apply_bundle(&after));
        assert_eq!(sim.tick(), start + 2);
    }

    /// **THE BINDING'S WELCOME IS THE RELAY'S WELCOME, PROVED RATHER THAN
    /// READ** (ASSA-53, from the Systems engineer's own flag on ASSA-37).
    ///
    /// `fresh_welcome_text` exists so the client's headless suite has a real
    /// world instead of a hand-built dictionary, and its whole value rests on
    /// being what a relay would send. Reading the two side by side proves that
    /// for today only: the person who makes them differ will be whoever next
    /// edits `sim-relay`, who has no reason to open this file. If they drift,
    /// **every client test keeps passing against a world no relay would send**
    /// and nothing goes red.
    ///
    /// So it is compared on the world's own **state hash**, not field by field.
    /// A hand-written field list is a third spelling that can drift too, and it
    /// would silently stop covering anything added to `World` later.
    ///
    /// Both halves matter: the world must be the relay's `fresh_world`, and the
    /// joining player must arrive through `step` as `SystemCommand::AddPlayer`
    /// rather than being pushed onto `World::players`, because only `step`
    /// makes the join part of the tick every peer replays.
    #[test]
    fn the_fresh_welcome_is_the_world_a_relay_would_send() {
        let welcome = fresh_welcome_text("4242", "ada");
        let from_binding =
            AssaySim::world_from_welcome(&welcome).expect("the binding writes a valid Welcome");

        // The relay's path, spelled out here on purpose: its own constructor,
        // then the joiner added by `step`.
        let mut expected = sim_net::fresh_world(4242);
        sim::step::step(
            &mut expected,
            &[Input::System(sim::SystemCommand::AddPlayer {
                name: "ada".to_string(),
            })],
            &mut Vec::new(),
        );

        assert_eq!(
            from_binding.state_hash(),
            expected.state_hash(),
            "the binding's Welcome is not the world a relay would send: \
             {} chunks vs {} chunks, {} players vs {} players",
            from_binding.width_chunks,
            expected.width_chunks,
            from_binding.players.len(),
            expected.players.len()
        );

        // NON-VACUITY: a different seed must NOT match, or this test would pass
        // against any two worlds that happen to be the same shape.
        let mut other = sim_net::fresh_world(4243);
        sim::step::step(
            &mut other,
            &[Input::System(sim::SystemCommand::AddPlayer {
                name: "ada".to_string(),
            })],
            &mut Vec::new(),
        );
        assert_ne!(
            from_binding.state_hash(),
            other.state_hash(),
            "a state hash that ignores the seed would make the check above empty"
        );
    }

    /// A Welcome is read out of the real message shape, tag and all.
    #[test]
    fn a_welcome_message_yields_its_world() {
        let world = fresh();
        let msg = serde_json::json!({"Welcome": {"player": 0, "world": world}});
        let back = AssaySim::world_from_welcome(&msg.to_string()).expect("should parse");
        assert_eq!(fnv64(&back), fnv64(&world));
    }

    /// The two routes the shipped build's selfcheck compares must agree here
    /// too, or the check in `scripts/selfcheck.gd` can never pass and the
    /// failure would first show up in CI on a Windows runner.
    #[test]
    fn the_two_self_check_routes_agree() {
        let value = AssaySim::self_check_value();
        assert_eq!(value, AssaySim::self_check_expected_value());
        assert_eq!(value.len(), 16, "got {value}");
        assert_ne!(value, "0000000000000000", "a zero hash is not evidence");
    }

    /// THE MESSAGE GDSCRIPT CANNOT BUILD. A `Hash` carries a `u64`; GDScript's
    /// ints are signed, so half of all hashes cannot be spelled there at all.
    /// This reads the JSON back as a real `ClientMsg` and checks the number
    /// against the sim's own, which is the only way to know nothing was rounded
    /// on the way out.
    #[test]
    fn a_hash_message_carries_the_sims_own_u64() {
        let mut world = fresh();
        // Forced past 2^53 so a double round-trip could not survive it. The
        // relay compares this number for equality; near enough is a desync.
        world.seed = u64::MAX - 12345;
        let sim = AssaySim::from_world(world);
        let text = sim.hash_message_text().expect("should serialise");
        let back: ClientMsg = serde_json::from_str(&text).expect("should parse");
        let ClientMsg::Hash { tick, hash } = back else {
            panic!("serialised as something other than a Hash: {text}");
        };
        assert_eq!(tick, sim.world().tick);
        assert_eq!(hash, sim.world().state_hash());
        assert_eq!(format!("{hash:016x}"), sim.hash_hex_string());
    }

    /// A hash is due exactly when `sim-net` says, and the host asks after
    /// stepping — same place `sim-cli` asks.
    #[test]
    fn a_hash_is_due_every_hash_every_ticks_and_not_between() {
        let mut sim = AssaySim::from_world(fresh());
        assert!(sim.hash_due(), "tick 0 is a multiple of HASH_EVERY");
        let mut due = 0;
        for _ in 0..(HASH_EVERY * 2) {
            let bundle = TickBundle {
                tick: sim.world().tick,
                inputs: Vec::new(),
            };
            assert!(sim.apply_bundle(&bundle));
            if sim.hash_due() {
                due += 1;
                assert_eq!(sim.world().tick % HASH_EVERY, 0);
            }
        }
        assert_eq!(due, 2, "two hashes due across {} ticks", HASH_EVERY * 2);
    }

    /// A `Tick` arrives as a whole `ServerMsg`, and `Tick` is a newtype variant,
    /// so the bundle sits directly under the tag with no second name. Built from
    /// the real `ServerMsg` type rather than a hand-written string, so a change
    /// to the wire shape fails here instead of at a relay.
    #[test]
    fn a_tick_message_yields_its_bundle() {
        let bundle = TickBundle {
            tick: 7,
            inputs: Vec::new(),
        };
        let text = serde_json::to_string(&sim_net::ServerMsg::Tick(bundle.clone())).unwrap();
        assert_eq!(
            AssaySim::bundle_from_tick(&text).expect("should parse"),
            bundle
        );
    }

    #[test]
    fn a_message_that_is_not_a_tick_is_an_error() {
        assert!(AssaySim::bundle_from_tick(r#"{"Desync":{"tick":5}}"#).is_err());
        assert!(AssaySim::bundle_from_tick("{").is_err());
    }

    #[test]
    fn a_message_that_is_not_a_welcome_is_an_error() {
        assert!(AssaySim::world_from_welcome(r#"{"Refused":{"reason":"no"}}"#).is_err());
    }

    /// A world with one player in it, added the only legal way: a system
    /// command through `step`.
    /// **THE TAB'S HEADLINE IS `debug::proximity_headline`, BYTE FOR BYTE**
    /// (ASSA-254 box 1, and the same reason the two `species_table` tests
    /// above live in this crate: the two surfaces meet HERE). `sim/tests` can
    /// see the sentence but not what the binding sends; the client suite can
    /// see what arrives but has no sim to compare it with. A GDScript panel
    /// that re-worded one clause would be green in both.
    ///
    /// **IT ASKS `proximity_facts`, NOT THE `#[func]`, AND NOT BY CHOICE.**
    /// Godot types abort in a `cargo test` ("Godot engine not available"), so
    /// the logic lives in the facts method and the `#[func]` only carries it
    /// across. I wrote it the other way round first and two tests died saying
    /// exactly that.
    ///
    /// **EVERY SEED IS WALKED AND BOTH ANSWER STATES ARE COUNTED**, because a
    /// test over worlds where nothing was ever absent never ran the empty arm
    /// -- and the empty arm is the one the Game Director asked for by name
    /// ("a world where the honest answer is nothing here burns").
    ///
    /// **AND `underfoot` IS PAIRED WITH THE SENTENCE RATHER THAN WITH THE FIELD
    /// IT CAME FROM** (ASSA-263). `row.underfoot == near.heading.is_none()`
    /// would be a tautology -- it is how the binding computes it. The claim
    /// worth asserting is that it agrees with the words the player reads, so
    /// the one place the two can be compared compares them: the literal below
    /// is quoted from `debug.rs` on purpose, and a reworded sentence SHOULD
    /// redden this test.
    #[test]
    fn the_tabs_headline_and_tile_are_the_sims_own_answer() {
        /// `debug::proximity_headline`'s words for the no-walk case, quoted
        /// deliberately: this test exists to catch the two drifting apart.
        const STANDING_ON_IT: &str = "right where you are standing";
        let (mut answered, mut empty, mut standing, mut merged) = (0, 0, 0, 0);
        for seed in 1..40 {
            let mut sim = AssaySim::from_world(sim_net::fresh_world(seed));
            sim.step_with(&[Input::System(sim::SystemCommand::AddPlayer {
                name: "limpet".to_string(),
            })]);
            let id = sim.world().players.first().expect("a player was added").id;
            let rows = sim.proximity_facts(Some(id));
            // **ONE ROW PER ANSWER, AND THE SIM SAYS HOW MANY THAT IS**
            // (ASSA-272). This asserted `Question::ALL.len()` until one patch
            // answering both questions became one row; the claim that survived
            // the merge is the one worth making anyway -- the binding passes
            // the sim's list through, neither dropping nor splitting an entry.
            let answers = sim::debug::proximity_headlines(sim.world(), id);
            assert_eq!(
                rows.len(),
                answers.len(),
                "seed {seed}: the binding sent {} rows for the sim's {} answers",
                rows.len(),
                answers.len()
            );
            // AND EVERY QUESTION IS ANSWERED EXACTLY ONCE, merged or not: a
            // merge that lost a question would be a shorter list that still
            // matched the line above.
            for &q in Question::ALL.iter() {
                let covered = answers.iter().filter(|a| a.questions.contains(&q)).count();
                assert_eq!(
                    covered, 1,
                    "seed {seed}: {q:?} is answered by {covered} of the sim's answers, not 1"
                );
            }
            let me = sim.world().player(id).expect("the player we added").pos;
            for (row, answer) in rows.iter().zip(answers.iter()) {
                // THE SIM'S SENTENCE, NOT A SENTENCE LIKE IT.
                assert_eq!(
                    row.headline, answer.line,
                    "seed {seed}: the binding re-worded the headline"
                );
                assert!(
                    row.headline.starts_with(&row.asked),
                    "seed {seed}: `asked` must be the headline's own prefix, so a body \
                     rendering both would say it twice"
                );
                // **A MERGED ROW KEEPS EVERY CLAUSE OF BOTH ANSWERS IT
                // REPLACES** (ASSA-272 box 3), measured against the sentences
                // it replaced rather than against a literal I typed: each
                // single-question headline's reading and trailing clause must
                // still be in the merged line.
                if answer.questions.len() > 1 {
                    merged += 1;
                    for &q in &answer.questions {
                        let alone = proximity_headline(sim.world(), id, q);
                        let (_, clauses) = alone
                            .split_once(": ")
                            .expect("a headline is `label: answer`");
                        for clause in clauses.split(" · ").skip(1) {
                            assert!(
                                row.headline.contains(clause),
                                "seed {seed}: the merged line dropped `{clause}` from \
                                 `{alone}`"
                            );
                        }
                    }
                }
                for &q in &answer.questions {
                    // AND THE TILE AGREES WITH THE SEARCH ABOUT WHETHER THERE IS ONE.
                    match sim.world().nearest_answering(q, me) {
                        Some(n) => {
                            answered += 1;
                            assert_eq!(
                                row.tile,
                                Some((n.tile.x, n.tile.y)),
                                "seed {seed}: the tile is not the one the sim named"
                            );
                            // AND WHETHER THERE IS A WALK IN IT AGREES WITH THE
                            // SENTENCE THE PLAYER READS.
                            assert_eq!(
                                row.underfoot,
                                row.headline.contains(STANDING_ON_IT),
                                "seed {seed}: `underfoot` is {} and the sim's sentence says \
                             otherwise -- `{}`",
                                row.underfoot,
                                row.headline
                            );
                            if row.underfoot {
                                standing += 1;
                                // **THIS IS WHAT MADE THE CONTROL DEAD**: the tile
                                // the answer is about is the tile the player is on,
                                // so `go here` would walk them nowhere.
                                assert_eq!(
                                    row.tile,
                                    Some((me.x, me.y)),
                                    "seed {seed}: the answer is underfoot but names a tile that is \
                                 not the player's own"
                                );
                            }
                        }
                        None => {
                            empty += 1;
                            assert!(
                                row.tile.is_none(),
                                "seed {seed}: nothing answers, so there must be no tile rather \
                             than a corner of the world the sim never offered"
                            );
                            assert!(
                                !row.underfoot,
                                "seed {seed}: nothing answers, so nothing is underfoot either"
                            );
                        }
                    }
                }
            }
        }
        assert!(
            answered > 0 && empty > 0 && standing > 0 && merged > 0,
            "an answer state never came up, so its arm never ran: \
             answered {answered}, empty {empty}, underfoot {standing}, merged {merged}"
        );
    }

    /// A PLAYER WHO IS NOT IN THIS WORLD GETS AN EMPTY LIST, not a row of
    /// apologies. `proximity_headline` has its own "no such player" sentence,
    /// and handing that to a panel would make a missing player look like a
    /// mineralogy answer.
    #[test]
    fn proximity_facts_refuses_a_player_who_is_not_here() {
        let (sim, _) = with_a_player("limpet");
        assert!(sim.proximity_facts(None).is_empty());
        assert!(sim.proximity_facts(Some(PlayerId(9999))).is_empty());
    }

    fn with_a_player(name: &str) -> (AssaySim, PlayerId) {
        let mut sim = AssaySim::from_world(fresh());
        sim.step_with(&[Input::System(sim::SystemCommand::AddPlayer {
            name: name.to_string(),
        })]);
        let id = sim.world().players.first().expect("a player was added").id;
        (sim, id)
    }

    /// **THIS HOST'S AUDIENCE IS `Pointed`, AND WITHOUT THIS TEST THAT IS A
    /// SILENT CHOICE** (ASSA-222).
    ///
    /// `sim::debug::event_line` takes an audience now and `sim/tests/
    /// event_audience.rs` pins what each one produces -- but nothing there can
    /// see WHICH one this crate passes. Flipping `describe` to `Audience::Typed`
    /// compiles, keeps all 389 Rust tests green, and quietly puts `building 0`
    /// back into the window the board called hard on the eyes. That is the
    /// "diverge silently" case this item's acceptance asks for, and it lives
    /// here because this is the only crate that knows the answer.
    ///
    /// It asserts on the species name read out of the world, never a literal:
    /// species are generated and nothing may name one.
    #[test]
    fn this_client_describes_events_to_a_reader_who_points() {
        let (mut sim, me) = with_a_player("marlow");
        let species = sim.world().species[0].id;
        let smelter = Item::new(sim::ItemKind::Smelter, species, sim::Grade::C);
        sim.world
            .player_mut(me)
            .expect("the player joined")
            .inventory
            .add(smelter, 1);
        let spawn = sim.world().spawn_tile();
        let pos = sim::TilePos::new(spawn.x + 1, spawn.y);
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Place { item: smelter, pos },
        )]);
        let building = sim
            .world()
            .buildings
            .first()
            .expect("the smelter was placed, or this proves nothing")
            .id;
        let noun = sim::debug::building_name(
            sim.world(),
            sim.world().building(building).expect("it is standing"),
        );

        // `ItemsTaken` and not `BuildingPlaced`: the placement sentence already
        // names the item, so its arm DROPS the handle rather than replacing it,
        // and a test on it could not tell naming from dropping. This event goes
        // through the naming path against a building that is still standing.
        let line = sim.describe(
            Some(me),
            &sim::Event::ItemsTaken {
                player: me,
                building,
                item: Item::new(sim::ItemKind::Refined, species, sim::Grade::C),
                count: 1,
            },
        );

        assert!(
            line.contains(&noun),
            "the window's log does not say WHICH building, which is the defect \
             Nerite reported at 1x.\nwanted: {noun}\nline:   {line}"
        );
        assert!(
            !line.contains(&format!("building {}", building.0)),
            "this window has no command line, so a BuildingId in its log is a \
             number a player can do nothing with. If this is red, `describe` \
             has been handed the typed reader's audience.\nline: {line}"
        );
    }

    /// WHAT THE HUD SHOWS OF YOUR OWN STACKS. Kind, species and grade are the
    /// three things an item stacks by, and the grade is a LETTER because that is
    /// what the sim calls it.
    #[test]
    fn an_inventory_reads_back_as_the_sims_own_stacks() {
        let (mut sim, me) = with_a_player("limpet");
        let species = sim.world().species[1].id;
        let ore = Item::new(sim::ItemKind::Ore, species, sim::Grade::B);
        // Put straight in: this test is about reading an inventory, not about
        // the twenty-odd ticks hand mining would take to fill one.
        sim.world
            .player_mut(me)
            .expect("the player exists")
            .inventory
            .add(ore, 7);

        let stacks = sim.inventory_facts(Some(me));
        assert_eq!(stacks.len(), 1, "got {stacks:?}");
        let stack = &stacks[0];
        assert_eq!(stack.kind, "ore");
        assert_eq!(stack.species, species.0 as i64);
        assert_eq!(stack.species_name, sim.world().species(species).name());
        assert_eq!(stack.grade, "B");
        assert_eq!(stack.count, 7);
        assert_eq!(stack.name, sim.world().item_name(ore));
    }

    /// A design, built straight onto the player: this file tests what the menu
    /// READS, and the craft chain that produces one has its own tests in `sim`.
    fn design(sim: &AssaySim, mount: Mount, species: &[usize], grade: sim::Grade) -> Built {
        let item = |i: usize| Item::new(sim::ItemKind::Refined, sim.world().species[i].id, grade);
        let assembly = Assembly::new(
            sim::Part::new(sim::PartKind::Frame(mount), item(species[0])),
            vec![sim::Part::new(
                sim::PartKind::Head,
                item(species[species.len() - 1]),
            )],
        );
        Built::new(assembly, &sim.world().species)
    }

    /// THE INDEX IS THE COMMAND'S ARGUMENT, so the order is not cosmetic:
    /// `Equip` and `PlaceAssembly` take a position in `Player::assemblies`, and
    /// a menu that sorted the list would equip the wrong machine. The tool in
    /// hand has no index of its own and says so with -1.
    #[test]
    fn the_held_tool_comes_first_and_the_built_list_keeps_its_own_index() {
        let (mut sim, me) = with_a_player("limpet");
        let hand = design(&sim, Mount::Held, &[0], sim::Grade::B);
        let first = design(&sim, Mount::Planted, &[1], sim::Grade::B);
        let second = design(&sim, Mount::Planted, &[2], sim::Grade::C);
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.tool = Some(hand);
            p.assemblies = vec![first, second];
        }

        let designs = sim.design_facts(Some(me));
        assert_eq!(designs.len(), 3, "got {designs:?}");
        assert_eq!((designs[0].index, designs[0].in_hand), (-1, true));
        assert_eq!((designs[1].index, designs[1].in_hand), (0, false));
        assert_eq!((designs[2].index, designs[2].in_hand), (1, false));
        assert_eq!(designs[0].mount, "held");
        assert_eq!(designs[1].mount, "planted");
    }

    /// **THE SMALL PRINT IS THE SIM'S SENTENCE, AND SAFE HAS NONE** (ASSA-90).
    /// Asserted against `sim::debug::verdict_note` on every design rather than
    /// against strings I expected, because the failure worth catching is this
    /// crate growing a second wording — which is the defect the item was filed
    /// for, one layer up in `hud.gd`.
    #[test]
    fn the_small_print_is_the_sims_sentence_and_a_safe_design_has_none() {
        let (mut sim, me) = with_a_player("limpet");
        // **ALL THREE VERDICTS ARE BUILT, NOT HOPED FOR.** My first version
        // swept the roster and asserted it had met "at least two" -- and a
        // mutation that turned the over-budget sentence into an assay offer
        // left it GREEN, because this world happened never to produce a WILL
        // BREAK design. The arm existed and nothing reached it.
        //
        // So two sheets are set deliberately: light-and-strong is SAFE at any
        // grade, dense-and-weak is WILL BREAK, and both are assayed so their
        // spans are points. The rest of the roster stays rough and supplies
        // UNCERTAIN.
        {
            let world = &mut sim.world;
            let (safe, breaks) = (world.species[0].id, world.species[1].id);
            let s = world.species_mut(safe);
            s.assayed = true;
            s.sheet.density = 1;
            s.sheet.strength = 100;
            let b = world.species_mut(breaks);
            b.assayed = true;
            b.sheet.density = 100;
            b.sheet.strength = 1;
        }
        let mut built = Vec::new();
        for i in 0..sim.world().species.len() {
            for grade in [sim::Grade::C, sim::Grade::A] {
                built.push(design(&sim, Mount::Planted, &[i], grade));
                built.push(design(&sim, Mount::Held, &[i], grade));
            }
        }
        sim.world
            .player_mut(me)
            .expect("the player exists")
            .assemblies = built.clone();

        let designs = sim.design_facts(Some(me));
        let mut seen: std::collections::HashSet<&str> = std::collections::HashSet::new();
        for (facts, b) in designs.iter().zip(built.iter()) {
            let want = sim::debug::verdict_note(&sim.world().species, &b.assembly);
            assert_eq!(facts.note, want, "design {}: {facts:?}", facts.index);
            seen.insert(facts.verdict.as_str());
            match facts.verdict.as_str() {
                "SAFE" => assert!(facts.note.is_none(), "{facts:?}"),
                // The whole point: the verdict the window never announced.
                "WILL BREAK" => {
                    let note = facts.note.as_deref().unwrap_or("");
                    assert!(note.contains("over budget"), "{facts:?}");
                    assert!(
                        !note.contains("assay"),
                        "an assay cannot move a settled verdict: {facts:?}"
                    );
                }
                "UNCERTAIN" => assert!(
                    facts.note.as_deref().unwrap_or("").starts_with("assay "),
                    "{facts:?}"
                ),
                other => panic!("the sim grew a fourth verdict: {other}"),
            }
        }
        // Non-vacuity, and it is an equality rather than a floor: every arm
        // above must have been reached, or a mutation inside an unvisited one
        // reports nothing. That is exactly what happened with `>= 2`.
        for want in ["SAFE", "UNCERTAIN", "WILL BREAK"] {
            assert!(seen.contains(want), "{want} was never built: met {seen:?}");
        }
    }

    /// THE VERDICT IS THE SIM'S WORD, NEVER THIS CRATE'S ARITHMETIC. Checked
    /// against `stat_range().verdict()` on every design rather than against a
    /// string I expected, because the failure worth catching is this host
    /// quietly growing its own opinion about whether a machine breaks.
    #[test]
    fn the_verdict_and_the_numbers_are_the_sims_own() {
        let (mut sim, me) = with_a_player("limpet");
        let mut built = Vec::new();
        for i in 0..sim.world().species.len() {
            built.push(design(&sim, Mount::Planted, &[i], sim::Grade::B));
        }
        sim.world
            .player_mut(me)
            .expect("the player exists")
            .assemblies = built.clone();

        let designs = sim.design_facts(Some(me));
        assert_eq!(designs.len(), built.len());
        let mut seen = std::collections::HashSet::new();
        for (facts, b) in designs.iter().zip(built.iter()) {
            let range = b.assembly.stat_range(&sim.world().species);
            assert_eq!(facts.verdict, range.verdict().label());
            assert_eq!(facts.mass_low, range.low.mass as i64);
            assert_eq!(facts.mass_high, range.high.mass as i64);
            assert_eq!(facts.budget_low, range.low.budget as i64);
            assert_eq!(facts.budget_high, range.high.budget as i64);
            seen.insert(facts.verdict.clone());
            assert!(
                ["SAFE", "UNCERTAIN", "WILL BREAK"].contains(&facts.verdict.as_str()),
                "{} is not one of the sim's three states",
                facts.verdict
            );
        }
        assert!(!seen.is_empty());
    }

    /// A ROW MUST ADD UP TO THE HEADLINE IT SITS UNDER. A player looking at an
    /// over-budget design picks the part to change out of these rows, and rows
    /// that do not sum to the mass the verdict was formed on would send them
    /// after the wrong one.
    #[test]
    fn the_part_rows_sum_to_the_designs_own_mass() {
        let (mut sim, me) = with_a_player("limpet");
        let built = design(&sim, Mount::Planted, &[0, 1], sim::Grade::B);
        sim.world
            .player_mut(me)
            .expect("the player exists")
            .assemblies = vec![built];

        let facts = &sim.design_facts(Some(me))[0];
        assert_eq!(facts.parts.len(), 2, "a frame and a head: {facts:?}");
        let low: i64 = facts.parts.iter().map(|p| p.mass_low).sum();
        let high: i64 = facts.parts.iter().map(|p| p.mass_high).sum();
        assert_eq!(low, facts.mass_low, "part rows must sum to the low mass");
        assert_eq!(high, facts.mass_high, "part rows must sum to the high mass");
        for part in &facts.parts {
            assert!(!part.kind.is_empty() && !part.species_name.is_empty());
            assert!(["C", "B", "A"].contains(&part.grade.as_str()), "{part:?}");
        }
    }

    /// THE STARTER PAIR IS THE SIM'S, AND IT IS THE PAIR A DEMO CAN COUNT ON.
    ///
    /// Worldgen rerolls the roster until the ladder holds, so every world has
    /// one; a scripted session that picked its own fuel would be guessing from a
    /// rough sheet about a rule (reactivity against heat tolerance, both scaled
    /// by grade) that only the sim may decide.
    #[test]
    fn the_starter_pair_is_two_different_species_the_sim_chose() {
        let (sim, _me) = with_a_player("limpet");
        let pair = sim.starter_pair_ids();
        assert_eq!(pair.len(), 2, "every world has a starter pair: {pair:?}");
        let (material, fuel) = (pair[0], pair[1]);
        for id in [material, fuel] {
            assert!(
                (id as usize) < sim.world.species.len(),
                "{id} is not a species in this world"
            );
        }
        // THE FUEL IS A HAND-LIT FUEL, which is the half a client could not
        // judge: `hand_lit_fuel` is a rule about reactivity and heat tolerance,
        // read off the TRUE sheet, and before an assay a client only has a
        // 25-wide band to guess from.
        let fuel_species = &sim.world.species[fuel as usize];
        assert!(
            sim::ladder::hand_lit_fuel(fuel_species),
            "the starter fuel cannot be lit by hand: {:?}",
            fuel_species.sheet
        );
        // AND THEY MAY BE THE SAME SPECIES. I asserted they could not be and
        // this test caught me: `starter_species` takes rung zero's material and
        // the first hand-lit fuel in the roster, and nothing stops one species
        // from being both. `first_plate.rs` searches for a seed where they
        // differ because it wants two deposits; a scripted session must not
        // assume it, or it fails on perfectly good worlds.
        if material == fuel {
            assert!(
                sim::ladder::hand_lit_fuel(&sim.world.species[material as usize]),
                "one species serving as both must still be a hand-lit fuel"
            );
        }
    }

    /// AN ITEM'S JSON IS SERDE'S, INCLUDING THE AWKWARD ONE. `handle` is
    /// `PartKind::Frame(Mount::Held)`, so it nests three deep, and that is the
    /// shape GDScript would be most likely to get wrong by hand. Pinned here so
    /// a rename or a serde attribute on any of the three enums shows up as this
    /// test failing rather than as a relay quietly dropping a command.
    #[test]
    fn an_items_json_is_the_shape_serde_writes_and_a_bad_name_is_empty() {
        for (kind, grade, wanted) in [
            ("ore", "c", r#"{"kind":"Ore","species":3,"grade":"C"}"#),
            (
                "refined",
                "B",
                r#"{"kind":"Refined","species":3,"grade":"B"}"#,
            ),
            (
                "smelter",
                "a",
                r#"{"kind":"Smelter","species":3,"grade":"A"}"#,
            ),
            (
                "head",
                "c",
                r#"{"kind":{"Part":"Head"},"species":3,"grade":"C"}"#,
            ),
            (
                "handle",
                "c",
                r#"{"kind":{"Part":{"Frame":"Held"}},"species":3,"grade":"C"}"#,
            ),
            (
                "frame",
                "c",
                r#"{"kind":{"Part":{"Frame":"Planted"}},"species":3,"grade":"C"}"#,
            ),
            (
                "hopper",
                "c",
                r#"{"kind":{"Part":"Hopper"},"species":3,"grade":"C"}"#,
            ),
            // The prefixed spelling `code()` writes must mean the same item.
            (
                "part:head",
                "c",
                r#"{"kind":{"Part":"Head"},"species":3,"grade":"C"}"#,
            ),
        ] {
            let got = item_text(kind, 3, grade);
            assert_eq!(got, wanted, "{kind}:{grade}");
            // And it round-trips: the text the client will send parses back into
            // the item it claims to be.
            let back: Item = serde_json::from_str(&got).expect("serde reads it back");
            assert_eq!(back.species, SpeciesId(3), "{kind}:{grade}");
        }
        for (kind, grade) in [("ore", "z"), ("widget", "c"), ("", "c")] {
            assert_eq!(
                item_text(kind, 3, grade),
                "",
                "'{kind}':'{grade}' should not spell an item"
            );
        }
        // A species id that cannot be a `SpeciesId` is refused rather than
        // wrapped: a command naming species 300 is a bug, not a request.
        assert_eq!(item_text("ore", 300, "c"), "");
    }

    /// SERDE REFUSES A FLOAT WHERE A `u8` BELONGS, and that is the trap worth
    /// pinning: Godot's JSON parses every number as a double, so a client that
    /// round-trips its own command text turns `3` into `3.0` and the relay drops
    /// the command before `step` ever sees it. The failure arrives as "the
    /// action never happened", nowhere near the cause.
    #[test]
    fn serde_refuses_a_float_species_and_accepts_what_the_client_should_send() {
        let good = r#"{"kind":"Ore","species":3,"grade":"C"}"#;
        assert_eq!(item_echo_text(good), good, "serde should read its own text");
        for bad in [
            r#"{"kind":"Ore","species":3.0,"grade":"C"}"#,
            r#"{"kind":"Ore","species":"3","grade":"C"}"#,
            r#"{"kind":{"Part":"Handle"},"species":3,"grade":"C"}"#,
            r#"{"kind":"Ore","grade":"C"}"#,
            "not json at all",
        ] {
            assert_eq!(item_echo_text(bad), "", "serde should have refused {bad}");
        }
        // Key order is serde's business, not the client's: the same item written
        // in another order is still that item.
        assert_eq!(
            item_echo_text(r#"{"grade":"C","species":3,"kind":"Ore"}"#),
            good
        );
    }

    /// EVERY COMMAND A BUTTON SENDS, AGAINST THE DESERIALISER THAT READS IT.
    ///
    /// The client's buttons (ASSA-37) build these in GDScript, so this pins both
    /// halves: the shapes serde accepts, and the three near-misses that would
    /// have reached a relay and been dropped without a word. `{"Stop": {}}` is
    /// the one I actually shipped — a unit variant written as an object — and it
    /// left a demo world mining itself to death while the probe said OK.
    #[test]
    fn serde_reads_every_command_a_button_sends_and_refuses_the_near_misses() {
        let item = r#"{"kind":"Ore","species":0,"grade":"C"}"#;
        let refined = r#"{"kind":"Refined","species":0,"grade":"C"}"#;
        for good in [
            r#""Mine""#.to_string(),
            r#""Stop""#.to_string(),
            r#""Assay""#.to_string(),
            r#""Unequip""#.to_string(),
            r#"{"MoveTo":{"target":{"x":4,"y":5}}}"#.to_string(),
            format!(r#"{{"Craft":{{"recipe":"Smelter","item":{item},"count":1}}}}"#),
            format!(r#"{{"Place":{{"item":{item},"pos":{{"x":4,"y":5}}}}}}"#),
            format!(r#"{{"Insert":{{"building":1,"slot":"Fuel","item":{item},"count":2}}}}"#),
            r#"{"Take":{"building":1}}"#.to_string(),
            r#"{"Pickup":{"building":1}}"#.to_string(),
            format!(r#"{{"MakePart":{{"kind":"Head","material":{refined},"count":1}}}}"#),
            format!(
                r#"{{"MakePart":{{"kind":{{"Frame":"Held"}},"material":{refined},"count":1}}}}"#
            ),
            format!(r#"{{"Assemble":{{"frame":{refined},"mounted":[{refined}]}}}}"#),
            r#"{"Equip":{"assembly":0}}"#.to_string(),
            r#"{"PlaceAssembly":{"assembly":0,"pos":{"x":4,"y":5}}}"#.to_string(),
        ] {
            assert_ne!(
                command_echo_text(&good),
                "",
                "serde should have read {good}"
            );
        }
        for bad in [
            // A unit variant written as an object. Shipped once; dropped silently.
            r#"{"Mine":{}}"#.to_string(),
            r#"{"Stop":{}}"#.to_string(),
            // Godot's JSON would write these if a client ever round-tripped its
            // own command text.
            r#"{"Equip":{"assembly":0.5}}"#.to_string(),
            r#"{"MoveTo":{"target":{"x":4.5,"y":5}}}"#.to_string(),
            // A `SystemCommand` is not a player's to send, and the relay's
            // refusal should not be the first thing that notices.
            r#"{"AddPlayer":{"name":"limpet"}}"#.to_string(),
            r#""Walk""#.to_string(),
            "not json at all".to_string(),
        ] {
            assert_eq!(
                command_echo_text(&bad),
                "",
                "serde should have refused {bad}"
            );
        }
    }

    /// THE CATALOGUE AND THE RECIPE TABLE, as the client is handed them. Only
    /// the number-free part is checked here, because `tag_variant` needs no
    /// engine but a `Dictionary` does — the GDScript side holds the tags against
    /// `command_echo`.
    #[test]
    fn the_part_and_recipe_tags_handed_to_the_client_are_serdes_own() {
        let tags: Vec<String> = PartKind::ALL
            .iter()
            .map(|kind| serde_json::to_string(kind).expect("a part kind serialises"))
            .collect();
        assert_eq!(
            tags,
            vec![
                "\"Head\"",
                "{\"Frame\":\"Held\"}",
                "{\"Frame\":\"Planted\"}",
                "\"Hopper\""
            ],
            "the catalogue's wire tags moved; the client's buttons carry them"
        );
        // And nothing in a tag is a number, which is what lets them cross as
        // Variants at all.
        for kind in PartKind::ALL {
            let value = serde_json::to_value(kind).expect("a part kind serialises");
            assert!(
                !has_a_number(&value),
                "{value} holds a number, so it cannot cross as a Variant"
            );
        }
        for id in sim::RecipeId::ALL {
            let value = serde_json::to_value(id).expect("a recipe id serialises");
            assert!(!has_a_number(&value), "{value} holds a number");
        }
    }

    /// `PART_MATERIAL` IS THE KIND `step` ACTUALLY ACCEPTS, not a comment about
    /// one. The client puts a `Make` button on a pack row because that row's
    /// item kind matches this, so if the rule moved in `sim` and this did not,
    /// the button would appear on the wrong row and every press would be
    /// dropped. Submitted both ways through the real `step`.
    #[test]
    fn a_part_is_made_of_the_material_this_catalogue_names() {
        let (mut sim, me) = with_a_player("limpet");
        let species = sim.world().species[0].id;
        let right = Item::new(AssaySim::PART_MATERIAL, species, sim::Grade::B);
        let wrong = Item::new(sim::ItemKind::Ore, species, sim::Grade::B);
        for item in [right, wrong] {
            sim.world
                .player_mut(me)
                .expect("the player exists")
                .inventory
                .add(item, 20);
        }
        let make = |material: Item| {
            Input::player(
                me,
                sim::PlayerCommand::MakePart {
                    kind: PartKind::Head,
                    material,
                    count: 1,
                },
            )
        };
        sim.step_with(&[make(wrong)]);
        let head = Item::new(sim::ItemKind::Part(PartKind::Head), species, sim::Grade::B);
        assert!(
            !sim.world()
                .player(me)
                .expect("exists")
                .inventory
                .has(head, 1),
            "a part was made out of {}, which `step` is supposed to refuse",
            wrong.kind.name()
        );
        sim.step_with(&[make(right)]);
        assert!(
            sim.world()
                .player(me)
                .expect("exists")
                .inventory
                .has(head, 1),
            "a part could not be made out of {}, which the catalogue names as its material",
            AssaySim::PART_MATERIAL.name()
        );
    }

    fn has_a_number(value: &serde_json::Value) -> bool {
        match value {
            serde_json::Value::Number(_) => true,
            serde_json::Value::Array(items) => items.iter().any(has_a_number),
            serde_json::Value::Object(fields) => fields.values().any(has_a_number),
            _ => false,
        }
    }

    /// A FRESH WELCOME IS A WELCOME, and the client's own reader is what says
    /// so: `world_from_welcome` is the function a real relay's message goes
    /// through, so a test world that only `serde_json` could read would prove
    /// nothing about the client.
    ///
    /// AND THE PLAYER IS IN IT. The relay adds a joiner with
    /// `SystemCommand::AddPlayer` on a tick and only then welcomes them; a world
    /// with an empty `players` list would leave every button in the suite acting
    /// as a player who does not exist.
    #[test]
    fn a_fresh_welcome_carries_a_world_with_the_joining_player_in_it() {
        let text = fresh_welcome_text("777042", "limpet");
        let world = AssaySim::world_from_welcome(&text).expect("the client can read it");
        assert_eq!(world.seed, 777042);
        assert_eq!(
            (world.width_chunks, world.height_chunks),
            (6, 4),
            "a test world should be the relay's size"
        );
        assert_eq!(world.players.len(), 1, "the joining player is missing");
        assert_eq!(world.players[0].name, "limpet");
        assert_eq!(
            world.players[0].pos,
            world.spawn_tile(),
            "a joiner starts at spawn"
        );
        // Added THROUGH `step`, which is why the world has moved a tick.
        assert_eq!(world.tick, 1);
        assert_eq!(fresh_welcome_text("not a seed", "limpet"), "");
    }

    /// THE SPECIES LETTER IS THE SIM'S, AND IT IS THE *GENERATED* NAME'S.
    ///
    /// A deposit on the map carries it so that colour is not the only thing
    /// telling two species apart (Decision #36), and a menu row carries it so a
    /// player can learn which letter goes with which name. Both must be the
    /// letter `worldgen` guarantees is distinct per world, which is the
    /// GENERATED name's — not `species_names()`'s first character, because that
    /// name becomes the discoverer's as soon as someone renames a species and
    /// nothing stops two renames from starting with the same letter.
    ///
    /// So this renames two species to collide on purpose and checks the letters
    /// do not follow.
    #[test]
    fn the_species_letter_survives_a_rename_that_would_collide() {
        let (mut sim, me) = with_a_player("limpet");
        let built = design(&sim, Mount::Held, &[0, 1], sim::Grade::B);
        sim.world
            .player_mut(me)
            .expect("the player exists")
            .assemblies = vec![built];

        let generated: Vec<char> = sim
            .world
            .species
            .iter()
            .map(sim::debug::species_symbol)
            .collect();
        let distinct: std::collections::BTreeSet<char> = generated.iter().copied().collect();
        assert_eq!(
            distinct.len(),
            generated.len(),
            "worldgen is supposed to guarantee distinct initials: {generated:?}"
        );

        // Both species in the design answer to the same name from here on, which
        // is a player's right. The letter is not a player's to collide.
        for id in [0usize, 1] {
            sim.world.species[id].player_name = Some("Zed".to_string());
        }

        let facts = &sim.design_facts(Some(me))[0];
        for part in &facts.parts {
            assert_eq!(
                part.species_name, "Zed",
                "the row should show the chosen name: {part:?}"
            );
            let wanted = generated[part.species as usize].to_string();
            assert_eq!(
                part.symbol, wanted,
                "the letter followed the rename instead of the generated name: {part:?}"
            );
        }
        assert_ne!(
            facts.parts[0].symbol, facts.parts[1].symbol,
            "two species collapsed onto one letter: {:?}",
            facts.parts
        );
    }

    /// `unassayed` IS WHAT LETS "UNCERTAIN" NAME ITS OWN RESOLUTION. Each rough
    /// species once, by name; nothing at all once they are known. Without it
    /// the state can only advise "assay something", and the ruling is that
    /// UNCERTAIN must not read as danger.
    #[test]
    fn unassayed_names_each_rough_species_once_and_goes_quiet_when_known() {
        let (mut sim, me) = with_a_player("limpet");
        for species in &mut sim.world.species {
            species.assayed = false;
        }
        let one_species = design(&sim, Mount::Planted, &[1, 1], sim::Grade::B);
        let two_species = design(&sim, Mount::Planted, &[0, 1], sim::Grade::B);
        sim.world
            .player_mut(me)
            .expect("the player exists")
            .assemblies = vec![one_species, two_species];

        let designs = sim.design_facts(Some(me));
        assert_eq!(
            designs[0].unassayed,
            vec![sim.world().species[1].name().to_string()],
            "a design of one rough species must name it once, not twice"
        );
        assert_eq!(designs[1].unassayed.len(), 2, "got {:?}", designs[1]);

        for species in &mut sim.world.species {
            species.assayed = true;
        }
        for facts in sim.design_facts(Some(me)) {
            assert!(
                facts.unassayed.is_empty(),
                "nothing is rough any more: {facts:?}"
            );
            assert_eq!(
                facts.mass_low, facts.mass_high,
                "an assayed design reads exact"
            );
        }
    }

    /// DURABILITY IS HELD-ONLY, and absent rather than empty when it does not
    /// apply: the head contributes a pool whatever frame it sits on, but drill
    /// wear is parked, so on a planted machine the number would never move.
    #[test]
    fn only_a_held_design_reports_durability() {
        let (mut sim, me) = with_a_player("limpet");
        let held = design(&sim, Mount::Held, &[0], sim::Grade::B);
        let planted = design(&sim, Mount::Planted, &[0], sim::Grade::B);
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.tool = Some(held);
            p.assemblies = vec![planted];
        }

        let designs = sim.design_facts(Some(me));
        let durability = designs[0]
            .durability
            .as_ref()
            .expect("a held design has a pool");
        // A10 is said in SWINGS USED, not as a percentage of the band (the
        // Game Director reversed that on ASSA-5: a percentage plus the
        // player's own swing count identifies the exact pool after six
        // swings). Marlow changed `sim::debug::durability_readout`; this
        // assertion follows it, which is the point of the menu taking its
        // wording from the sim.
        assert!(
            durability.starts_with("0 of ") && durability.ends_with(" swings used"),
            "a design nobody has used yet has used no swings: {durability}"
        );
        assert_eq!(
            designs[1].durability, None,
            "a planted design must not report a pool at all"
        );

        // ONCE THE SPECIES IS ASSAYED the pool is exact and may be shown as
        // one — A10's rule is about what a ROUGH sheet gives away, and this is
        // the branch that proves the menu takes its wording from the sim
        // rather than always printing a percentage.
        for species in &mut sim.world.species {
            species.assayed = true;
        }
        let exact = sim.design_facts(Some(me))[0]
            .durability
            .clone()
            .expect("a held design has a pool");
        assert!(
            !exact.contains('%') && !exact.contains('-'),
            "an assayed design reads against one exact number of swings \
             rather than a band, got {exact}"
        );
    }

    /// A client asks for its designs every frame, with no player id before the
    /// relay welcomes it and none at all before anyone builds anything.
    #[test]
    fn designs_for_nobody_are_empty_rather_than_a_crash() {
        let (sim, me) = with_a_player("limpet");
        assert!(sim.design_facts(None).is_empty());
        assert!(sim.design_facts(player_id_of(-1)).is_empty());
        assert!(sim.design_facts(Some(PlayerId(9999))).is_empty());
        assert!(
            sim.design_facts(Some(me)).is_empty(),
            "a player who has built nothing has no designs"
        );
    }

    /// A client asks for its inventory every frame and has no player id until
    /// the relay welcomes it. Nothing it can ask may panic a shipped build.
    #[test]
    fn an_inventory_for_nobody_is_empty_rather_than_a_crash() {
        let (sim, _) = with_a_player("limpet");
        assert!(sim.inventory_facts(None).is_empty());
        assert!(sim.inventory_facts(player_id_of(-1)).is_empty());
        assert!(sim.inventory_facts(Some(PlayerId(9999))).is_empty());
    }

    /// THE HOVER READOUT'S ONE JOB: say what the sim has on that tile. The
    /// deposit is found by `World::deposit_at`, so a radius is the circle the
    /// sim means and not a square this crate drew round the centre.
    #[test]
    fn a_tile_reports_the_deposit_covering_it_and_nothing_at_its_edge() {
        let sim = AssaySim::from_world(fresh());
        let deposit = sim
            .world()
            .deposits
            .iter()
            .find(|d| !d.is_depleted())
            .expect("a generated world has deposits")
            .clone();

        let on_it = sim.tile_facts(deposit.center.x, deposit.center.y);
        let found = on_it.deposit.expect("the centre tile is on the deposit");
        assert!(on_it.in_bounds);
        assert_eq!(found.id, deposit.id.0 as i64);
        assert_eq!(found.purity, deposit.purity as i64);
        assert_eq!(found.grade, deposit.grade().letter().to_string());
        assert_eq!(found.radius, deposit.radius as i64);
        assert!(!found.assayed, "a fresh world has assayed nothing");
        assert_eq!(
            on_it.chunk,
            (deposit.center.chunk().x, deposit.center.chunk().y)
        );

        // Just outside the radius, on the diagonal, which is where a square
        // would wrongly still report it.
        let out = i32::from(deposit.radius) + 1;
        let beside = sim.tile_facts(deposit.center.x + out, deposit.center.y + out);
        assert!(
            beside.deposit.is_none(),
            "a tile {out} away diagonally reported {:?}",
            beside.deposit
        );
    }

    /// **THE CLIENT MUST NEVER WORK REACH OUT** (ASSA-43). 40.7% of deposits
    /// are of a species nothing in the game can mine, and the tile line used
    /// to describe them exactly like the ones that yield — down to inviting an
    /// assay whose sheet a player can never spend. The fact and the sentence
    /// both come from `sim`, so `hud.gd` has no reason to hold an opinion
    /// about the number 40, and both halves are checked here: the dead rock
    /// AND a live one, because a field that was always `false` would satisfy
    /// half a test.
    #[test]
    fn a_deposit_reports_whether_anything_can_mine_it() {
        let mut world = fresh();
        let dead = world.deposits[0].clone();
        world.species_mut(dead.species).sheet.hardness =
            sim::tuning::HAND_MINE_MAX_HARDNESS as u8 + 1;
        // USABLE, NOT MERELY MINABLE (ASSA-52). This asked for `hand_minable`
        // and then asserted an empty note, which was only true while the note
        // had one cause. A minable rock can now carry a sentence of its own —
        // it can be impossible to smelt — so the "nothing to say" case has to
        // pick a rock that really has nothing to say. It passed by luck on
        // this seed; luck is not a predicate.
        let live = world
            .deposits
            .iter()
            .find(|d| sim::ladder::usable_from_bare_hands(&world.species, d.species))
            .expect("a world the ladder guarantees has a usable deposit")
            .clone();
        let sim = AssaySim::from_world(world);

        let out_of_reach = sim
            .tile_facts(dead.center.x, dead.center.y)
            .deposit
            .expect("on the deposit");
        assert!(!out_of_reach.hand_minable);
        assert!(
            out_of_reach
                .reach_note
                .contains(sim.world().species(dead.species).name()),
            "the client is handed the sentence, named: {:?}",
            out_of_reach.reach_note
        );

        let in_reach = sim
            .tile_facts(live.center.x, live.center.y)
            .deposit
            .expect("on the deposit");
        assert!(in_reach.hand_minable);
        assert_eq!(
            in_reach.reach_note, "",
            "nothing to say about a rock that yields, and an empty note is how \
             `hud.gd` knows to leave the line alone"
        );
    }

    /// **THE SCHEMATIC'S MARK IS KEYED ON THE WIDER GATE, AND THE TWO REALLY DO
    /// DIFFER** (ASSA-199; ASSA-187 was mine and it marked the narrower set).
    ///
    /// `hand_minable` asks whether anything gets the ore OUT. The sim's dead-end
    /// note also covers the quieter case — a rock you can break and cannot smelt
    /// — so a mark keyed on `hand_minable` draws those exactly like good ore.
    ///
    /// **THE SWEEP IS THE ASSERTION, NOT THE SEED.** One world could differ by
    /// luck, so this walks thirty and requires the gap to be REAL somewhere and
    /// the containment to hold EVERYWHERE: a rock nothing can mine is always a
    /// dead end, so `!hand_minable` must imply a note on every deposit of every
    /// world. A note that stopped covering the unsmeltable half would keep the
    /// containment and lose the gap, which is why both are checked.
    #[test]
    fn the_dead_end_note_is_a_wider_gate_than_hand_minable() {
        let mut worlds_with_a_gap = 0;
        let mut deposits = 0;
        let mut minable_but_dead = 0;
        for seed in 1..=30u64 {
            let world = sim_net::fresh_world(seed);
            let mut gap_here = 0;
            for deposit in &world.deposits {
                let (minable, note) = map_disc_facts(&world, deposit);
                deposits += 1;
                assert!(
                    minable || !note.is_empty(),
                    "seed {seed}: a rock nothing can mine carries no dead-end sentence, so the \
                     note cannot be the mark's predicate"
                );
                if minable && !note.is_empty() {
                    gap_here += 1;
                }
            }
            minable_but_dead += gap_here;
            if gap_here > 0 {
                worlds_with_a_gap += 1;
            }
        }
        assert!(
            worlds_with_a_gap > 0,
            "over 30 worlds and {deposits} deposits, not one rock was minable-but-dead. Either \
             the two gates have become opposites again or this sweep is measuring nothing — and \
             the Game Director counted 16.3% of 423 deposits in that state."
        );
        assert!(
            minable_but_dead * 20 > deposits,
            "{minable_but_dead} of {deposits} deposits are minable and still a dead end (under \
             5%). The Game Director measured 16.3%; a number this small means the note stopped \
             carrying the unsmeltable half and `hand_minable` would do."
        );
    }

    /// The cursor is off the map most of the time. That is a fact to report, not
    /// a reason to guess at tile (0, 0).
    #[test]
    fn a_tile_off_the_map_says_so_and_holds_nothing() {
        let sim = AssaySim::from_world(fresh());
        for (x, y) in [(-1, 4), (4, -1), (9999, 4), (4, 9999)] {
            let facts = sim.tile_facts(x, y);
            assert!(!facts.in_bounds, "({x}, {y}) claimed to be in bounds");
            assert!(facts.deposit.is_none());
            assert!(facts.building.is_none());
            assert_eq!(facts.pos, (x, y));
        }
        let spawn = sim.world().spawn_tile();
        assert!(sim.tile_facts(spawn.x, spawn.y).is_spawn);
    }

    /// A ROUGH SHEET IS AN INTERVAL AND MUST LOOK LIKE ONE. Until a deposit is
    /// assayed every property reads as the sim's 25-wide band; a client that
    /// printed one number from it would be inventing certainty the player has
    /// not paid for.
    #[test]
    fn a_rough_sheet_reads_as_a_band_and_an_assayed_one_as_a_number() {
        let mut sim = AssaySim::from_world(fresh());
        let first = sim.world().species[0].id;

        let rough = &sim.species_facts()[0];
        assert!(!rough.assayed);
        for (property, reading) in &rough.readings {
            assert!(
                reading.contains('-'),
                "{property} read as {reading}, not a band, while unassayed"
            );
        }

        sim.world.species_mut(first).assayed = true;
        let exact = &sim.species_facts()[0];
        assert!(exact.assayed);
        for (property, reading) in &exact.readings {
            assert!(
                reading.parse::<u32>().is_ok(),
                "{property} read as {reading} after assaying, not a number"
            );
        }
        assert_eq!(exact.readings.len(), Property::ALL.len());
        assert_eq!(exact.name, sim.world().species(first).name());
    }

    /// **THE BAR AND THE TEXT BESIDE IT ARE ONE ANSWER** (ASSA-256).
    /// `readings` crosses the sentence and `reading_ranges` crosses the two
    /// numbers a surface draws. A panel whose band disagrees with the string
    /// under it is worse than either alone: a player cannot tell which of them
    /// lied, and both came from us.
    ///
    /// **CHECKED AS THE TWO PAYLOADS AGAINST EACH OTHER**, the shape
    /// `hand_minable` is checked in. No expected number is written here, so
    /// worldgen may move and this still means what it says.
    ///
    /// The last assertion is the one a host's drawing code leans on: a band is
    /// a point EXACTLY when the species is assayed, so one shape draws both
    /// states and no renderer needs an `assayed` branch to decide which.
    #[test]
    fn a_readings_band_and_its_text_cross_as_one_answer() {
        let mut sim = AssaySim::from_world(fresh());
        let first = sim.world().species[0].id;

        for assayed in [false, true] {
            sim.world.species_mut(first).assayed = assayed;
            let facts = &sim.species_facts()[0];
            assert_eq!(facts.assayed, assayed);
            assert_eq!(facts.reading_ranges.len(), Property::ALL.len());

            for (property, reading) in &facts.readings {
                let found = facts
                    .reading_ranges
                    .iter()
                    .find(|(p, _)| p == property)
                    .map(|(_, range)| *range);
                let Some((lo, hi)) = found else {
                    panic!("{property} crossed a reading and no range to draw it with");
                };
                let expected = if assayed {
                    lo.to_string()
                } else {
                    format!("{lo}-{hi}")
                };
                assert_eq!(
                    reading, &expected,
                    "{property}: the text says {reading} and the band says {lo}-{hi}"
                );
                assert_eq!(
                    assayed,
                    lo == hi,
                    "{property}: a zero-width band must mean assayed and nothing else"
                );
            }
        }
    }

    /// THE MAP LETTER IS NOT THE NAME'S FIRST CHARACTER, and a client reaching
    /// for `name[0]` is the shortcut this field exists to remove. A player may
    /// rename a species; the mark already drawn on the map does not follow, so
    /// the two are allowed to disagree and a legend built from the name would
    /// stop being a key to the map (ASSA-73, Maren's glyph-and-tint ruling).
    ///
    /// The other half of that claim -- that the panel's letter is the same one
    /// a DEPOSIT draws -- is asserted in the client suite, because both of
    /// those surfaces are Godot dictionaries that `cargo test` cannot build.
    #[test]
    fn a_rename_does_not_move_the_species_map_letter() {
        let mut sim = AssaySim::from_world(fresh());
        let first = sim.world().species[0].id;
        let before = sim.species_facts()[0].symbol.clone();
        assert!(!before.is_empty(), "a species with no map letter");

        sim.world.species_mut(first).player_name = Some("Zzzzqqq".to_string());
        let after = &sim.species_facts()[0];
        assert_eq!(after.name, "Zzzzqqq", "the rename did not take");
        assert_eq!(
            after.symbol, before,
            "renaming to Zzzzqqq moved the map letter from {before} to {}",
            after.symbol
        );
    }

    /// **THE PANEL'S MINING SENTENCE IS THE TABLE'S, BYTE FOR BYTE**
    /// (ASSA-135, Game Director's box 1). The species panel and `sim-cli`'s
    /// `species` table are one surface at two widths, and a player who read
    /// one and then the other must not have to work out whether two phrasings
    /// mean one thing.
    ///
    /// THIS IS THE TEST THAT COULD HAVE PREVENTED THE BUG and the reason it
    /// lives in this crate: the two surfaces meet HERE. `sim/tests` can see
    /// the table but not what the binding sends, and the client suite can see
    /// what arrives but has no table to compare it with. The old field was a
    /// bool, so there was nothing to compare and three states became two.
    ///
    /// Every seed is walked rather than one, with all three states asserted to
    /// have come up: a world where some state never occurred would pass every
    /// assertion over it.
    #[test]
    fn the_species_panels_mining_note_is_the_tables_own_words() {
        use sim::debug::{Mining, mining, mining_note, species_table};

        let (mut too_hard, mut unsmeltable, mut usable) = (0, 0, 0);
        for seed in 1..40 {
            let sim = AssaySim::from_world(sim_net::fresh_world(seed));
            let world = sim.world();
            let table = species_table(world);
            for facts in sim.species_facts() {
                let species = &world.species[facts.id as usize];
                match mining(&world.species, species.id) {
                    Mining::TooHard => too_hard += 1,
                    Mining::ByHandNotSmeltable => unsmeltable += 1,
                    Mining::ByHand => usable += 1,
                }
                // AGAINST THE TABLE'S SHIPPED TEXT, NOT AGAINST A LITERAL. A
                // colour literal keeps passing after the table moves; this
                // asserts the two surfaces agree, so rewording either one
                // alone is what reddens.
                let row = table
                    .lines()
                    .find(|l| l.contains(&facts.name))
                    .unwrap_or_else(|| panic!("seed {seed}: no table row for {}", facts.name));
                assert!(
                    !facts.mining.is_empty(),
                    "seed {seed} {}: every rock is in one of three states and this one said nothing",
                    facts.name
                );
                assert!(
                    row.contains(&facts.mining),
                    "seed {seed} {}: the panel says {:?} and the table row reads {row}",
                    facts.name,
                    facts.mining
                );
                // AND IT IS ONE OF THE THREE, not a sentence this crate
                // composed that happens to appear in the row.
                assert!(
                    [Mining::TooHard, Mining::ByHandNotSmeltable, Mining::ByHand]
                        .iter()
                        .any(|state| mining_note(*state) == facts.mining),
                    "seed {seed} {}: {:?} is not one of the sim's three notes",
                    facts.name,
                    facts.mining
                );
            }
        }
        assert!(
            too_hard > 10 && unsmeltable > 3 && usable > 10,
            "a state never came up, so the panel never rendered it: \
             too_hard {too_hard}, unsmeltable {unsmeltable}, usable {usable}"
        );
    }

    /// **THE PANEL'S FUEL CLAIM CARRIES THE GRADE, AND IT IS THE TABLE'S OWN
    /// WORDS** (ASSA-143, Game Director). The panel used to be handed
    /// `fuel_grade(species).is_some()` — the threshold computed and thrown
    /// away on one line — so it said "fuel" and never at which grade, and on
    /// 18.8% of the rows it tags as fuel grade C does not burn.
    ///
    /// Same place and same reason as the mining test above: `sim/tests` can
    /// see the table but not what the binding sends, and the client suite can
    /// see what arrives but has no table to compare it with. The two surfaces
    /// meet in this crate, which is where a dropped clause is visible.
    ///
    /// **A NONE IS ASSERTED AS HARD AS A SOME.** "The sim does not call this
    /// rock fuel" and "the sim does and the panel lost it" would both show up
    /// as a missing tag, so the absent case is pinned to `fuel_grade` being
    /// `None` rather than merely tolerated.
    #[test]
    fn the_species_panels_fuel_tag_is_the_tables_own_words() {
        use sim::debug::{fuel_tag, species_table};

        // Every case the clause has, counted, because an assertion that never
        // ran is not a green: three grades times minable-or-not, and the
        // not-fuel rows that must carry no tag at all.
        let (mut at_c, mut at_b, mut at_a, mut unminable, mut not_fuel) = (0, 0, 0, 0, 0);
        for seed in 1..60 {
            let sim = AssaySim::from_world(sim_net::fresh_world(seed));
            let world = sim.world();
            let table = species_table(world);
            for facts in sim.species_facts() {
                let species = &world.species[facts.id as usize];
                let row = table
                    .lines()
                    .find(|l| l.contains(&facts.name))
                    .unwrap_or_else(|| panic!("seed {seed}: no table row for {}", facts.name));
                match sim::ladder::fuel_grade(species) {
                    None => {
                        not_fuel += 1;
                        // THE PANEL MAY NOT CALL A ROCK FUEL THAT THE SIM DOES
                        // NOT, which is the other half of the claim and the
                        // half a literal-free test would miss.
                        assert!(
                            facts.fuel.is_none(),
                            "seed {seed} {}: no grade of this burns and the panel said {:?}",
                            facts.name,
                            facts.fuel
                        );
                        assert!(
                            !row.contains("fuel at"),
                            "seed {seed} {}: the table claims fuel where the ladder has none: {row}",
                            facts.name
                        );
                    }
                    Some(grade) => {
                        let minable = sim::ladder::hand_minable(species);
                        if minable {
                            match grade {
                                sim::Grade::C => at_c += 1,
                                sim::Grade::B => at_b += 1,
                                sim::Grade::A => at_a += 1,
                            }
                        } else {
                            unminable += 1;
                        }
                        let tag = facts.fuel.as_deref().unwrap_or_else(|| {
                            panic!(
                                "seed {seed} {}: the sim burns this at {} and the panel said nothing",
                                facts.name,
                                grade.letter()
                            )
                        });
                        // AGAINST THE SIM'S FUNCTION, not against a literal: a
                        // literal keeps passing after the wording moves, and
                        // the whole defect was one surface wording its own.
                        assert_eq!(
                            tag,
                            fuel_tag(grade, minable),
                            "seed {seed} {}: the panel worded the fuel claim itself",
                            facts.name
                        );
                        // AND AGAINST THE TABLE'S SHIPPED TEXT, so rewording
                        // either surface alone reddens.
                        assert!(
                            row.contains(tag),
                            "seed {seed} {}: the panel says {tag:?} and the table row reads {row}",
                            facts.name
                        );
                        // THE GRADE IS ON THE SURFACE AND NOT MERELY IMPLIED.
                        // This is the one literal in here and it is the item's
                        // actual claim: a player can read the letter.
                        assert!(
                            tag.contains(grade.letter()),
                            "seed {seed} {}: {tag:?} does not name grade {}",
                            facts.name,
                            grade.letter()
                        );
                    }
                }
            }
        }
        assert!(
            at_c > 10 && at_b > 3 && at_a > 3 && unminable > 3 && not_fuel > 10,
            "a case never came up, so the panel never rendered it: at_c {at_c}, at_b {at_b}, \
             at_a {at_a}, unminable {unminable}, not_fuel {not_fuel}"
        );
    }

    /// **A ROCK THAT BURNS ONLY ABOVE GRADE C LOOKS DIFFERENT FROM ONE THAT
    /// BURNS AT C** (ASSA-143 box 4). The point of the item: these two rows
    /// were identical on screen, and one of them is a player walking to a
    /// deposit for nothing.
    ///
    /// Asserted as a PARTITION over a whole roster rather than on two chosen
    /// rows — if any two species with different thresholds ever rendered the
    /// same tag, this fails, and no hand-picked pair can hide it.
    #[test]
    fn two_fuels_with_different_thresholds_do_not_render_alike() {
        // Seed 152's roster carries all three thresholds AND the unminable
        // conditional: Riomite C, Zernrosine B, Nerdunite and Valium A, with
        // Bakase and Torgoline fuel nobody can mine. It is the seed on this
        // item's window shot, so the picture and this test are about one world.
        let sim = AssaySim::from_world(sim_net::fresh_world(152));
        let world = sim.world();
        let mut by_grade: std::collections::BTreeMap<char, Vec<String>> = Default::default();
        for facts in sim.species_facts() {
            let species = &world.species[facts.id as usize];
            if let Some(grade) = sim::ladder::fuel_grade(species)
                && sim::ladder::hand_minable(species)
            {
                by_grade
                    .entry(grade.letter())
                    .or_default()
                    .push(facts.fuel.clone().expect("a fuel row with no tag"));
            }
        }
        assert_eq!(
            by_grade.len(),
            3,
            "seed 152 is on the window shot BECAUSE it holds all three thresholds; it now holds \
             {by_grade:?} and either the shot or this seed needs replacing"
        );
        // One wording per threshold, and no wording shared across two.
        for (grade, tags) in &by_grade {
            let first = &tags[0];
            assert!(
                tags.iter().all(|t| t == first),
                "two rocks that both burn at {grade} are described differently: {tags:?}"
            );
        }
        let mut wordings: Vec<&String> = by_grade.values().map(|tags| &tags[0]).collect();
        wordings.sort();
        wordings.dedup();
        assert_eq!(
            wordings.len(),
            3,
            "three thresholds rendered as {} distinct rows: {by_grade:?}",
            wordings.len()
        );
    }

    /// EVENTS ARE SENTENCES, NOT DEBUG DUMPS, and the one about me says "you".
    /// `{event:?}` is still available as `last_events` for an engineer; what a
    /// player reads may not contain `PlayerId(0)`.
    #[test]
    fn an_event_about_me_says_you_and_never_leaks_debug_shapes() {
        let (sim, me) = with_a_player("limpet");
        let species = sim.world().species[0].id;
        let item = Item::new(sim::ItemKind::Ore, species, sim::Grade::C);
        let head = Item::new(
            sim::ItemKind::Part(sim::assembly::PartKind::Head),
            species,
            sim::Grade::C,
        );
        let events = vec![
            Event::PlayerJoined {
                player: me,
                name: "limpet".into(),
            },
            Event::MoveStarted {
                player: me,
                from: TilePos::new(1, 1),
                to: TilePos::new(2, 2),
            },
            Event::PlayerArrived {
                player: me,
                pos: TilePos::new(2, 2),
            },
            Event::PlayerStopped {
                player: me,
                pos: TilePos::new(2, 2),
            },
            Event::MiningStarted {
                player: me,
                deposit: sim::DepositId(0),
                species,
            },
            Event::OreMined {
                player: me,
                deposit: sim::DepositId(0),
                item,
                amount: 2,
            },
            Event::MiningStopped {
                player: me,
                deposit: sim::DepositId(0),
                reason: StopReason::Depleted,
            },
            Event::DepositDepleted {
                deposit: sim::DepositId(0),
            },
            Event::SpeciesDiscovered {
                player: me,
                species,
            },
            Event::AssayStarted {
                player: me,
                deposit: sim::DepositId(0),
                species,
            },
            Event::AssayStopped {
                player: me,
                deposit: sim::DepositId(0),
                reason: StopReason::LeftDeposit,
            },
            Event::SpeciesAssayed {
                player: me,
                species,
            },
            Event::SpeciesRenamed {
                player: me,
                species,
                name: "tin".into(),
            },
            Event::RenameGranted {
                species,
                from: me,
                to: PlayerId(1),
            },
            Event::CraftStarted {
                player: me,
                recipe: sim::RECIPES[0].id,
                item,
                count: 2,
            },
            Event::ItemCrafted {
                player: me,
                recipe: sim::RECIPES[0].id,
                item,
                count: 1,
                remaining: 1,
            },
            Event::CraftingStopped {
                player: me,
                recipe: sim::RECIPES[0].id,
                reason: StopReason::OutOfInputs,
            },
            Event::BuildingPlaced {
                player: me,
                building: sim::BuildingId(1),
                item,
                pos: TilePos::new(3, 3),
            },
            Event::BuildingRemoved {
                player: me,
                building: sim::BuildingId(1),
                item,
                pos: TilePos::new(3, 3),
            },
            Event::ItemsInserted {
                player: me,
                building: sim::BuildingId(1),
                slot: Slot::Fuel,
                item,
                count: 3,
                left: 0,
            },
            Event::ItemsTaken {
                player: me,
                building: sim::BuildingId(1),
                item,
                count: 3,
            },
            Event::ItemSmelted {
                building: sim::BuildingId(1),
                item,
                count: 1,
            },
            Event::CommandRejected {
                player: me,
                command: sim::PlayerCommand::Mine,
                reason: sim::RejectReason::NotOnDeposit,
            },
            // THE EIGHT THE ASSEMBLY MODEL ADDED, and the reason this list grew:
            // they had no arm at all and fell to `format!("{other:?}")`, so a
            // player saw `MachineBroke { player: PlayerId(0), ... }` at the most
            // dramatic moment in the game. The wording is one function in `sim`
            // now, exhaustive there, so this list is a check that the Godot path
            // reaches it -- not the thing holding the arms in place.
            Event::PartsMade {
                player: me,
                part: head,
                count: 2,
            },
            Event::Assembled {
                player: me,
                assembly: 0,
            },
            Event::Equipped { player: me },
            Event::Unequipped { player: me },
            Event::MachinePlaced {
                player: me,
                building: sim::BuildingId(1),
                pos: TilePos::new(12, 9),
            },
            Event::MachineBroke {
                player: me,
                pos: Some(TilePos::new(12, 9)),
                mass: 564,
                budget: 60,
                lost: vec![head],
                returned: vec![item],
            },
            Event::ToolWornOut {
                player: me,
                head,
                handle: item,
            },
        ];
        for event in &events {
            let line = sim.describe(Some(me), event);
            // A Debug shape is more than a newtype: `{ ` is the struct-literal
            // form every unworded variant used to come out as.
            assert!(
                !line.contains("{ ") && !line.contains("Part("),
                "{event:?} leaked a Debug shape: {line}"
            );
            assert!(!line.is_empty(), "{event:?} described as nothing");
            assert!(
                !line.contains("PlayerId(") && !line.contains("SpeciesId("),
                "{event:?} leaked a Debug shape: {line}"
            );
            // READ IT OUT LOUD. "you's design broke" contains "you" and passes any
            // check for it, which is how a possessive built from a name survives
            // into the one event a player is most likely to read twice.
            assert!(
                !line.contains("you's"),
                "{event:?} reads as a possessive of 'you': {line}"
            );
            // Every line about me is about me by name.
            if !matches!(
                event,
                Event::DepositDepleted { .. } | Event::ItemSmelted { .. }
            ) {
                assert!(line.contains("you"), "{event:?} did not say you: {line}");
            }
        }

        // Seen by somebody else, the same event names me instead.
        let theirs = sim.describe(Some(PlayerId(42)), &events[0]);
        assert!(theirs.contains("limpet"), "got {theirs}");
        assert!(!theirs.contains("you"), "got {theirs}");
    }

    /// **THE PRESS A CLIENT MUST NOT CONFIRM, THROUGH THE SURFACE A CLIENT
    /// ACTUALLY CALLS** (ASSA-102, for the Game Director's ASSA-86 ruling 2).
    ///
    /// The names are the ones `inventory_of` hands over, which is the whole
    /// contract: GDScript gives back what it was given. `tests/part_press.rs`
    /// pins the rule; this pins that the host asks it the right question and
    /// repeats the sim's answer without touching it.
    #[test]
    fn a_doomed_part_press_comes_back_as_the_sims_own_sentence() {
        let name = |kind: PartKind| sim::ItemKind::Part(kind).name().to_string();
        let head = name(PartKind::Head);
        let handle = name(PartKind::Frame(Mount::Held));
        let hopper = name(PartKind::Hopper);

        // A head cannot be the first part, and the sentence is the sim's.
        assert_eq!(
            press_refusal_text(&[], &head),
            sim::debug::assembly_error_phrase(sim::AssemblyError::FrameIsNotAFrame),
        );
        // A hopper on a handle: the fourth case the Game Director's run found.
        assert_eq!(
            press_refusal_text(std::slice::from_ref(&handle), &hopper),
            sim::debug::assembly_error_phrase(sim::AssemblyError::NoSuchSlot(PartKind::Hopper)),
        );
        // A handle first is merely unfinished, so the press is confirmed.
        assert_eq!(press_refusal_text(&[], &handle), "");
        // And a head on it completes a tool.
        assert_eq!(press_refusal_text(std::slice::from_ref(&handle), &head), "");
    }

    /// A row that is not a part at all is answered by the sim's catalogue
    /// sentence, not by a string this host made up.
    #[test]
    fn a_row_that_is_not_a_part_is_refused_in_the_sims_words() {
        let text = press_refusal_text(&[], "ore");
        assert_eq!(text, sim::debug::not_a_part_phrase("ore"));
        // The same holds for a name already in the buffer, which is the half a
        // single-argument check would miss.
        assert_eq!(
            press_refusal_text(&["ore".to_string()], "head"),
            sim::debug::not_a_part_phrase("ore"),
        );
    }

    /// **THE PRESS AND THE TERMINAL SAY ONE SENTENCE ABOUT ONE NOUN** — the
    /// box QA could not tick on ASSA-102, closed where both sides are
    /// reachable.
    ///
    /// The other tests here compare `press_refusal_text` with the function it
    /// calls, so they agree with themselves by construction and said nothing
    /// when `event_line` rendered the same refusal as `ore#3(B)`. This one
    /// drives a real `Assemble` through `step`, words the rejection the way
    /// `sim-cli` does, and asks whether what the client would have shown
    /// AHEAD of the press is inside it. Nothing here is a typed sentence, so
    /// it follows the Game Director's wording wherever she moves it.
    #[test]
    fn the_refusal_a_press_shows_is_inside_the_one_the_terminal_prints() {
        let (mut sim, me) = with_a_player("limpet");
        let species = sim.world().species[0].id;
        let ore = Item::new(sim::ItemKind::Ore, species, sim::Grade::B);
        let head = Item::new(sim::ItemKind::Part(PartKind::Head), species, sim::Grade::B);
        for item in [ore, head] {
            sim.world
                .player_mut(me)
                .expect("the player exists")
                .inventory
                .add(item, 4);
        }

        // The pack row the player would press, named the way `inventory_of`
        // hands it over — which is the only subject the client ever holds.
        let row = sim::ItemKind::Ore.name();
        let press = press_refusal_text(&[], row);
        assert!(!press.is_empty(), "an ore frame must refuse the press");

        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Assemble {
                frame: ore,
                mounted: vec![head],
            },
        )]);
        let rejected = sim
            .last_events
            .iter()
            .find(|e| matches!(e, sim::Event::CommandRejected { .. }))
            .expect("an ore frame is refused by `step`, or this proves nothing");
        // `Pointed`, because this test is about what THIS client's player reads
        // twice -- on the press and in the log. `describe` is the same choice.
        let line = sim::debug::event_line(
            sim.world(),
            Some(me),
            rejected,
            sim::debug::Audience::Pointed,
        );

        assert!(
            line.contains(&press),
            "the press and the log disagree about a refusal the player sees \
             twice.\npress: {press}\nlog:   {line}"
        );
    }

    /// **EVERY PART KIND ROUND-TRIPS THROUGH ITS OWN NAME**, which is what
    /// `press_refusal_text` rests on: a kind whose name the sim could not look
    /// up again would come back as "not a machine part" for a real pack row.
    ///
    /// Over the catalogue, so a fifth part kind is covered by this test the
    /// day it is added rather than the day someone remembers.
    #[test]
    fn a_part_kinds_own_name_finds_it_again() {
        for kind in PartKind::ALL {
            let name = sim::ItemKind::Part(kind).name();
            assert_eq!(
                sim::ItemKind::from_name(name).and_then(sim::ItemKind::part),
                Some(kind),
                "{name} did not find its way back to {kind:?}"
            );
            // And it is never mistaken for a doomed press by accident: as the
            // first part, exactly the frames are allowed.
            assert_eq!(
                press_refusal_text(&[], name).is_empty(),
                kind.is_frame(),
                "{name} as the first part disagrees with is_frame()"
            );
        }
    }

    /// **THE WINDOW'S HALTED SURFACE IS THE SIM'S `halted()`, NOT A SECOND
    /// OPINION** (ASSA-94): same count, same order, same sentences.
    ///
    /// The stall is driven through `step` -- a smelter placed, ore in, nothing
    /// to burn -- rather than built by hand out of a `BuildingState`. The thing
    /// under test is whether this binding ASKS THE SIM, so a stall I assembled
    /// myself would be the fixture agreeing with me rather than with the rules.
    ///
    /// **THE EMPTY ASSERTION COMES FIRST AND IS NOT A WARM-UP.** A smelter with
    /// nothing in it reads `idle: nothing to refine`, which follows every
    /// successful batch and asks nobody for anything; if that reached this
    /// surface the panel would cry wolf after every smelt, which is the Game
    /// Director's standing constraint on this item.
    /// ASSA-119: the world view needs the LIST, and every number on it is the
    /// sim's.
    ///
    /// THE FOOTPRINT IS THE ASSERTION THAT MATTERS. A smelter is 2x2 and a
    /// machine 1x1, `pos` is the TOP-LEFT of that block, and a renderer that
    /// worked out for itself which kinds are big would draw a smelter over one
    /// tile of a world the sim has given it four. Checked against the sim's own
    /// answer and not against a 2 typed here, so a footprint that changes in
    /// `building.rs` changes here rather than silently disagreeing.
    #[test]
    fn every_building_is_listed_with_the_footprint_the_sim_gave_it() {
        let (mut sim, me) = with_a_player("limpet");
        assert!(
            sim.building_facts().is_empty(),
            "a fresh world already holds buildings, so this test proves nothing"
        );
        let species = sim.world().species[0].id;
        let smelter = Item::new(sim::ItemKind::Smelter, species, sim::Grade::B);
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.inventory.add(smelter, 1);
        }
        let at = sim.world().player(me).expect("exists").pos;
        let spot = sim::TilePos::new(at.x + 1, at.y);
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Place {
                item: smelter,
                pos: spot,
            },
        )]);

        let facts = sim.building_facts();
        assert_eq!(facts.len(), 1, "{facts:?}");
        let placed = &facts[0];
        let theirs = sim
            .world()
            .building_at(spot)
            .expect("the smelter was placed");
        assert_eq!(placed.id, theirs.id.0 as i64);
        assert_eq!(placed.kind, "smelter");
        assert_eq!(placed.pos, (spot.x, spot.y));
        assert_eq!(
            placed.footprint,
            theirs.kind.footprint(),
            "the footprint is the sim's, never a size this crate decided"
        );
        assert_eq!(
            placed.footprint,
            (2, 2),
            "and today that is 2x2, which is what a renderer has to cover"
        );
        assert_eq!(placed.species, species.0 as i64);
        assert_eq!(
            placed.status,
            sim::debug::building_status(sim.world(), theirs),
            "the status is the sim's sentence, not a second copy of the wording"
        );
        // THE NAME IS THE SIM'S TOO (ASSA-136). `kind` stays the bare noun for
        // anything that branches; what a player is shown carries the species
        // and grade, because that species is what caps the fire and what comes
        // back in the pack — and after ASSA-131 it is also what the sprite's
        // tint is claiming.
        assert_eq!(
            placed.name,
            sim::debug::building_name(sim.world(), theirs),
            "the name is the sim's words, not a second copy of them"
        );
        // Built from the item that was actually placed, never from a letter
        // typed here: a check that hardcodes the quantity it is checking tests
        // the typing (ASSA-98, and I have shipped that mistake myself).
        assert_eq!(
            placed.name,
            format!(
                "{} smelter ({})",
                sim.world().species(smelter.species).name(),
                smelter.grade.letter()
            ),
            "a player is shown species, kind and grade"
        );
        assert_ne!(
            placed.name, placed.kind,
            "and that is more than the bare noun `kind` already carried"
        );
        // EVERY TILE THE SIM OCCUPIES IS INSIDE THE REPORTED BLOCK. This is the
        // real content of "pos is the top-left", and it fails if `pos` were ever
        // the CENTRE — which is the other convention in this repo
        // (`World::spawn_tile`) and the easy thing to assume.
        for tile in sim::building::footprint_tiles(theirs.pos, theirs.kind.footprint()) {
            let inside = tile.x >= placed.pos.0
                && tile.y >= placed.pos.1
                && tile.x < placed.pos.0 + placed.footprint.0
                && tile.y < placed.pos.1 + placed.footprint.1;
            assert!(
                inside,
                "the sim occupies {tile:?}, which is outside the block {:?} + {:?}",
                placed.pos, placed.footprint
            );
            assert!(
                sim.world().building_at(tile).is_some(),
                "{tile:?} is inside the reported block and holds no building"
            );
        }
        // A SMELTER IS NOT AN ASSEMBLY, so it has no parts to draw. Empty
        // rather than one guessed frame part: a renderer overlaying a frame
        // sprite on a smelter would be drawing a machine the game cannot build,
        // which is the one thing `art/mock_scene.py`'s header forbids.
        assert!(placed.parts.is_empty(), "{:?}", placed.parts);
    }

    /// **A SMELTER IS DRAWN LIT ONLY WHILE SOMETHING BURNS IN IT**, and the
    /// fire is driven through `step` rather than set here: what is under test
    /// is that this binding asks `World::smelter_state`, so a `lit` I arranged
    /// by hand would be the fixture agreeing with me instead of with the rules.
    ///
    /// Cove's sheet ships two rows, `cold` and `lit` (ASSA-126), and this is
    /// the only fact that chooses between them. It is a boolean here for the
    /// reason on the field: a renderer handed a temperature would have to
    /// invent the threshold, which is the second copy of a decision that
    /// ASSA-128 just cost us a day of false stall lines for.
    ///
    /// **THE SEAM IS ASSERTED TOO.** Between two units of fuel a smelter spends
    /// one tick at `burn_left == 0`, which is the tick ASSA-128 announced a
    /// stall on. If that reached here the smelter would BLINK COLD once per
    /// unit burned, in the window, for a fire that never went out.
    #[test]
    fn a_smelter_reads_lit_only_while_a_fire_is_burning_in_it() {
        let (mut sim, me) = with_a_player("marlow");
        let rock = sim.world().species[0].id;
        let fuel_species = sim.world().species[1].id;
        // Sheets set on purpose: ore this smelter's walls can take, and a fuel
        // that lights from a hand spark. Worldgen rolls a roster per seed and
        // this test is not about which roster it rolled.
        sim.world.species_mut(rock).sheet = sim::Sheet {
            density: 50,
            strength: 50,
            hardness: 30,
            heat_tolerance: 60,
            reactivity: 1,
            conductivity: 50,
        };
        sim.world.species_mut(fuel_species).sheet = sim::Sheet {
            density: 50,
            strength: 50,
            hardness: 30,
            heat_tolerance: sim::tuning::HAND_SPARK_TEMPERATURE as u8,
            reactivity: 60,
            conductivity: 50,
        };
        let smelter = Item::new(sim::ItemKind::Smelter, rock, sim::Grade::B);
        let ore = Item::new(sim::ItemKind::Ore, rock, sim::Grade::A);
        let fuel = Item::new(sim::ItemKind::Ore, fuel_species, sim::Grade::A);
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.inventory.add(smelter, 1);
            p.inventory.add(ore, 15);
            p.inventory.add(fuel, 3);
        }
        let at = sim.world().player(me).expect("exists").pos;
        let spot = sim::TilePos::new(at.x + 1, at.y);
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Place {
                item: smelter,
                pos: spot,
            },
        )]);
        let id = sim
            .world()
            .building_at(spot)
            .expect("the smelter was placed")
            .id;

        assert!(
            !sim.building_facts()[0].lit,
            "a smelter with nothing in it is cold: {:?}",
            sim.building_facts()[0]
        );

        // **ORE IN AND NOTHING TO BURN: STILL COLD, AND THIS IS THE ARM THE
        // OBVIOUS MISTAKE FAILS.** `lit = anything but Idle` passes every other
        // assertion in this test and draws a fire in a smelter that is stalled
        // asking the player for fuel. Found by mutation, not by inspection.
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Insert {
                building: id,
                slot: sim::Slot::Input,
                item: ore,
                count: 15,
            },
        )]);
        assert!(
            sim.building_facts()[0].status.contains("stalled: no fuel"),
            "premise: this arm is only worth anything if it is a STALL and not idle: {:?}",
            sim.building_facts()[0].status
        );
        assert!(
            !sim.building_facts()[0].lit,
            "a smelter stalled for want of fuel has no fire in it: {:?}",
            sim.building_facts()[0]
        );

        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Insert {
                building: id,
                slot: sim::Slot::Fuel,
                item: fuel,
                count: 3,
            },
        )]);
        assert!(
            sim.building_facts()[0].lit,
            "ore and lightable fuel in: {:?}",
            sim.building_facts()[0]
        );

        // 300 ticks of refining against 120 per unit of this fuel, so the run
        // crosses two seams. The premise is asserted from the sim's own output
        // rather than assumed: a smelter that never lit would also never blink.
        let mut blinked: Vec<(u64, String)> = Vec::new();
        let mut cold_after: u32 = 0;
        for _ in 0..300 {
            sim.step_with(&[]);
            let lit = sim.building_facts()[0].lit;
            let sim::BuildingKind::Smelter(s) = &sim
                .world()
                .building(id)
                .expect("still standing")
                .kind
                .clone()
            else {
                panic!("the building stopped being a smelter")
            };
            // "Still has ore in it" is the premise of the assertion, not the
            // assertion: a smelter blinking cold with nothing left to refine is
            // the banked-fire case below, and a different question.
            match (lit, s.input.is_some()) {
                (false, true) => {
                    blinked.push((sim.world().tick, sim.building_facts()[0].status.clone()))
                }
                (false, false) => cold_after += 1,
                _ => {}
            }
        }
        let sim::BuildingKind::Smelter(s) = &sim
            .world()
            .building(id)
            .expect("still standing")
            .kind
            .clone()
        else {
            panic!("the building stopped being a smelter")
        };
        assert!(
            s.output.is_some_and(|o| o.count >= 10),
            "premise: it has to have refined a batch, not sat there: {s:?}"
        );
        assert!(
            s.fuel.is_none(),
            "premise: every unit of fuel burned, so both seams were crossed: {s:?}"
        );
        assert_eq!(
            blinked,
            Vec::new(),
            "the fire never went out while there was ore to refine, so the sprite may not blink"
        );
        // **AND THE EDGE THE GAME DIRECTOR HAS NOT RULED ON, PINNED SO IT
        // CANNOT CHANGE QUIETLY.** When the ore runs out the smelter reads cold
        // while still holding a banked fire — the status line above says
        // `fuel empty (60 ticks burning at 60) ... idle: nothing to refine`.
        // That follows from the sim's rule that fuel burns only while
        // something is refining, and it is one line to reverse if she wants a
        // smelter to keep glowing between batches.
        assert!(
            cold_after > 0,
            "premise: the run has to outlast the batch for this edge to be pinned at all"
        );
    }

    /// **A STALL AND ITS RECOVERY, DRIVEN THROUGH `step`** — the one case
    /// ASSA-300 exists for, and the only one that proves a host has a way back.
    ///
    /// Before this, the Godot client had nothing to ask: the stall event is an
    /// edge, so `the … smelter (A) stopped: no fuel` sat over the world after
    /// the smelter was refuelled while the pinned count beside it had already
    /// dropped to zero. The three facts a host needs are asserted at three
    /// moments of one real world, not arranged by hand.
    #[test]
    fn a_stall_arrives_as_a_condition_about_a_building_and_stops_being_halted_when_it_is_fixed() {
        let (mut sim, me) = with_a_player("marlow");
        let rock = sim.world().species[0].id;
        let fuel_species = sim.world().species[1].id;
        // The same two sheets `a_smelter_reads_lit_only_…` sets, and for the
        // same reason: ore these walls can take, and a fuel that lights from a
        // hand spark. Worldgen rolls a roster per seed; this test is not about
        // which one it rolled.
        sim.world.species_mut(rock).sheet = sim::Sheet {
            density: 50,
            strength: 50,
            hardness: 30,
            heat_tolerance: 60,
            reactivity: 1,
            conductivity: 50,
        };
        sim.world.species_mut(fuel_species).sheet = sim::Sheet {
            density: 50,
            strength: 50,
            hardness: 30,
            heat_tolerance: sim::tuning::HAND_SPARK_TEMPERATURE as u8,
            reactivity: 60,
            conductivity: 50,
        };
        let smelter = Item::new(sim::ItemKind::Smelter, rock, sim::Grade::B);
        let ore = Item::new(sim::ItemKind::Ore, rock, sim::Grade::A);
        let fuel = Item::new(sim::ItemKind::Ore, fuel_species, sim::Grade::A);
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.inventory.add(smelter, 1);
            p.inventory.add(ore, 15);
            p.inventory.add(fuel, 3);
        }
        let at = sim.world().player(me).expect("exists").pos;
        let spot = sim::TilePos::new(at.x + 1, at.y);
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Place {
                item: smelter,
                pos: spot,
            },
        )]);
        let id = sim
            .world()
            .building_at(spot)
            .expect("the smelter was placed")
            .id;

        // 1. AN EMPTY SMELTER IS NOT A CONDITION. `Idle` is what follows every
        //    finished batch, so a surface that listed it would cry wolf.
        assert!(
            !sim.is_halted(i64::from(id.0)),
            "an empty smelter is idle, which the sim refuses to call a stall"
        );

        // 2. ORE IN, NOTHING TO BURN: the stall fires, and it arrives as a
        //    CONDITION carrying this building.
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Insert {
                building: id,
                slot: sim::Slot::Input,
                item: ore,
                count: 15,
            },
        )]);
        let pairs = sim.attention_pairs(Some(me));
        let about: Vec<Option<BuildingId>> = pairs.iter().map(|(_, b)| *b).collect();
        assert!(
            about.contains(&Some(id)),
            "premise: the stall edge has to be in this tick's events at all: {pairs:?}"
        );
        let said = pairs
            .iter()
            .find(|(_, b)| *b == Some(id))
            .map(|(line, _)| line.clone())
            .expect("just asserted");
        assert!(
            sim.is_halted(i64::from(id.0)),
            "the condition is true on the tick its sentence is said: {said}"
        );

        // **AND THE TWO WORDINGS DO NOT MATCH, WHICH IS WHY THE ID IS CARRIED**
        // (ASSA-67): a host that compared the toast with the pinned list would
        // never clear anything. This fails if they ever converge, which would
        // be a design change and not a pass.
        let pinned = sim.halt_line_texts();
        assert!(
            !pinned.contains(&said),
            "the notice and the pinned line are two wordings of one condition; \
             if they are now identical, the id this test guards is no longer needed: \
             {said:?} vs {pinned:?}"
        );

        // 3. FUEL IN: the condition is gone on the tick it is fixed, so the
        //    sentence has somewhere to go. This is the half that did not exist.
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Insert {
                building: id,
                slot: sim::Slot::Fuel,
                item: fuel,
                count: 3,
            },
        )]);
        assert!(
            !sim.is_halted(i64::from(id.0)),
            "refuelled and working, so nothing about it is still stopped: {:?}",
            sim.building_facts()[0].status
        );
        // AND THE PINNED BLOCK AGREES, because both are `World::halted`
        // (ASSA-300 box 6: the toast and the count never disagree about
        // whether anything is stopped).
        assert!(
            sim.halt_line_texts().is_empty(),
            "a host keying the toast on `is_halted` and the block on `halt_lines` \
             must not be able to disagree: {:?}",
            sim.halt_line_texts()
        );
    }

    /// **A REFUSAL IS AN ACT AND MUST NEVER BE AGEABLE** (ASSA-239: a failure
    /// that faded out would be the one class of sentence a player cannot
    /// recover).
    ///
    /// `-1` and not the building it was about, even when the refused command
    /// names one: the act happened, nothing can un-happen it, so there is no
    /// condition to re-ask. A host handed an id here would take the sentence
    /// down the moment that building was healthy — which it already is, because
    /// the refusal was about the player's reach, not the machine.
    #[test]
    fn a_refusal_is_an_act_with_no_building_to_re_ask() {
        let (mut sim, me) = with_a_player("marlow");
        let species = sim.world().species[0].id;
        let ore = Item::new(sim::ItemKind::Ore, species, sim::Grade::C);
        // Insert into a building that does not exist: rejected, and the command
        // names a `BuildingId` so this is the arm where carrying one would look
        // reasonable.
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Insert {
                building: BuildingId(7),
                slot: sim::Slot::Input,
                item: ore,
                count: 1,
            },
        )]);
        let pairs = sim.attention_pairs(Some(me));
        assert_eq!(
            pairs.len(),
            1,
            "premise: a refused command has to be one attention line: {pairs:?}"
        );
        assert_eq!(
            pairs[0].1, None,
            "a refusal is an ACT: {:?} must never carry a building a host could \
             watch go healthy",
            pairs[0]
        );
    }

    /// **THE LINE AND ITS KIND COME FROM THE SAME EVENT, INDEX FOR INDEX.**
    ///
    /// The two `#[func]`s a host calls are each one `map` over `attention_pairs`,
    /// so this is a property rather than an agreement — but it is the property
    /// the whole fix rests on, and a future hand that reintroduced a second
    /// filter would break it silently. Driven over a tick carrying BOTH kinds
    /// at once, because a fixture with one of them cannot tell a correct
    /// pairing from a constant.
    #[test]
    fn an_act_and_a_condition_in_one_tick_keep_their_own_kinds() {
        let (mut sim, me) = with_a_player("marlow");
        let rock = sim.world().species[0].id;
        sim.world.species_mut(rock).sheet = sim::Sheet {
            density: 50,
            strength: 50,
            hardness: 30,
            heat_tolerance: 60,
            reactivity: 1,
            conductivity: 50,
        };
        let smelter = Item::new(sim::ItemKind::Smelter, rock, sim::Grade::B);
        let ore = Item::new(sim::ItemKind::Ore, rock, sim::Grade::A);
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.inventory.add(smelter, 1);
            p.inventory.add(ore, 15);
        }
        let at = sim.world().player(me).expect("exists").pos;
        let spot = sim::TilePos::new(at.x + 1, at.y);
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Place {
                item: smelter,
                pos: spot,
            },
        )]);
        let id = sim
            .world()
            .building_at(spot)
            .expect("the smelter was placed")
            .id;
        // One tick, two inputs: the ore that stalls it, and a second insert into
        // a building that is not there, which is refused.
        sim.step_with(&[
            Input::player(
                me,
                sim::PlayerCommand::Insert {
                    building: id,
                    slot: sim::Slot::Input,
                    item: ore,
                    count: 15,
                },
            ),
            Input::player(
                me,
                sim::PlayerCommand::Insert {
                    building: BuildingId(9999),
                    slot: sim::Slot::Input,
                    item: ore,
                    count: 1,
                },
            ),
        ]);
        let pairs = sim.attention_pairs(Some(me));
        let acts = pairs.iter().filter(|(_, b)| b.is_none()).count();
        let conditions = pairs.iter().filter(|(_, b)| *b == Some(id)).count();
        assert_eq!(
            (acts, conditions),
            (1, 1),
            "premise: this tick must carry one of each kind, or the test cannot \
             tell a pairing from a constant: {pairs:?}"
        );
        // AND THE SENTENCES ARE NOT SWAPPED. The condition's line is the one
        // the sim says about the machine; the act's is the refusal.
        for (line, about) in &pairs {
            match about {
                Some(_) => assert!(
                    !line.contains("refused"),
                    "a refusal arrived carrying a building: {line}"
                ),
                None => assert!(
                    line.contains("refused"),
                    "a machine's condition arrived as an act: {line}"
                ),
            }
        }
    }

    /// An id nothing in the world answers to is not stopped. A machine that has
    /// been picked up cannot keep a sentence on screen for ever.
    #[test]
    fn an_unknown_building_is_not_halted() {
        let sim = AssaySim::from_world(fresh());
        assert!(!sim.is_halted(0));
        assert!(!sim.is_halted(9999));
        assert!(!sim.is_halted(-1));
    }

    /// A MACHINE CARRIES ITS PARTS IN `Assembly::parts()` ORDER, FRAME FIRST.
    ///
    /// A machine has no single drawing: `art/rig.py` rule 2 is that one is drawn
    /// by overlaying whole part sprites at one frame position, and the frame has
    /// to be the bottom layer. The order is the sim's canonical one — "every
    /// rule that has to pick a part walks that order, so two peers can never
    /// disagree" — and a renderer inventing its own would stack a machine
    /// differently from the way the game reasons about it.
    #[test]
    fn a_machine_carries_its_parts_frame_first_at_the_grade_it_was_built_at() {
        let (mut sim, me) = with_a_player("marlow");
        let species = sim.world().species[0].id;
        let material = Item::new(sim::ItemKind::Refined, species, sim::Grade::B);
        let frame = sim::assembly::Part::of(
            sim::assembly::PartKind::Frame(sim::assembly::Mount::Planted),
            material,
        );
        let head = sim::assembly::Part::of(sim::assembly::PartKind::Head, material);
        let assembly = sim::assembly::Assembly::new(frame, vec![head]);
        let at = sim.world().player(me).expect("exists").pos;
        let spot = sim::TilePos::new(at.x + 2, at.y);
        let roster = sim.world().species.clone();
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.assemblies
                .push(sim::assembly::Built::new(assembly.clone(), &roster));
        }
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::PlaceAssembly {
                assembly: 0,
                pos: spot,
            },
        )]);
        let facts = sim.building_facts();
        assert_eq!(facts.len(), 1, "the machine was not placed: {facts:?}");
        let placed = &facts[0];
        assert_eq!(placed.kind, "machine");
        assert_eq!(placed.footprint, (1, 1));
        let want: Vec<String> = assembly
            .parts()
            .map(|part| part.kind.name().to_string())
            .collect();
        let got: Vec<String> = placed.parts.iter().map(|p| p.kind.clone()).collect();
        assert_eq!(got, want, "frame first, then the mounted parts");
        assert_eq!(got[0], "frame", "{got:?}");
        assert_eq!(placed.parts[0].grade, "B");
    }

    // -----------------------------------------------------------------------
    // ASSA-321: the slots, the batch and the condition, as data
    // -----------------------------------------------------------------------

    /// **THE TAG A MENU IS HANDED IS THE TAG THE SIM PARSES**, held against a
    /// real `PlayerCommand` rather than against the string I typed.
    ///
    /// This is the premise every put button rests on: the client submits
    /// commands as JSON, so a tag spelt by hand in this crate would survive a
    /// variant rename and the relay would drop every insert. Asserting it
    /// against my own constant is the shape that stays green while both sides
    /// are wrong together — which my box-7 test did last week, and it is the
    /// reason this test exists at all.
    #[test]
    fn the_insert_tag_a_menu_is_handed_is_the_one_the_sim_parses() {
        for slot in [sim::Slot::Input, sim::Slot::Fuel] {
            let tag = insert_tag(slot).expect("a slot an Insert can name has a tag");
            let command = sim::PlayerCommand::Insert {
                building: sim::BuildingId(1),
                slot,
                item: Item::new(sim::ItemKind::Ore, sim::SpeciesId(0), sim::Grade::A),
                count: 2,
            };
            let wire = serde_json::to_string(&command).expect("a command serialises");
            assert!(
                wire.contains(&format!("\"slot\":\"{tag}\"")),
                "the tag {tag} is not how {slot:?} appears on the wire: {wire}"
            );
            // And it comes back as the same slot, which is the half a `contains`
            // cannot see.
            let back: sim::PlayerCommand =
                serde_json::from_str(&wire).expect("and deserialises again");
            assert_eq!(back, command);
        }
    }

    /// A smelter's three holders cross with their contents and the cap the SIM
    /// will accept — and the output slot carries no tag, so a menu cannot offer
    /// a put control for an act the rules have no target for (ASSA-43).
    #[test]
    fn a_smelters_slots_carry_their_contents_the_sims_caps_and_no_tag_for_the_output() {
        let (mut sim, me) = with_a_player("nacre");
        let rock = sim.world().species[0].id;
        sim.world.species_mut(rock).sheet = sim::Sheet {
            density: 50,
            strength: 50,
            hardness: 30,
            heat_tolerance: 60,
            reactivity: 1,
            conductivity: 50,
        };
        let smelter = Item::new(sim::ItemKind::Smelter, rock, sim::Grade::B);
        let ore = Item::new(sim::ItemKind::Ore, rock, sim::Grade::A);
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.inventory.add(smelter, 1);
            p.inventory.add(ore, 7);
        }
        let at = sim.world().player(me).expect("exists").pos;
        let spot = sim::TilePos::new(at.x + 1, at.y);
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Place {
                item: smelter,
                pos: spot,
            },
        )]);
        let id = sim.world().building_at(spot).expect("placed").id;
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Insert {
                building: id,
                slot: sim::Slot::Input,
                item: ore,
                count: 7,
            },
        )]);

        let facts = sim.building_facts();
        let slots = &facts[0].slots;
        let roles: Vec<&str> = slots.iter().map(|s| s.role.as_str()).collect();
        assert_eq!(
            roles,
            vec!["input", "fuel", "output"],
            "the set of rows is the sim's, in the order a player fixes things in"
        );

        let input = &slots[0];
        assert_eq!(input.count, 7);
        assert_eq!(
            input.cap as u32,
            sim::tuning::SMELTER_INPUT_CAP,
            "the cap is what the sim accepts, so a fill needs no host arithmetic"
        );
        let held = input.held.as_ref().expect("seven ore are in it");
        assert_eq!(held.count, 7);
        assert_eq!(
            held.name,
            sim.world().item_name(ore),
            "a slot's stack is named by the sim, exactly as a pack row is"
        );
        assert_eq!(
            input.insert_tag.as_deref(),
            Some("Input"),
            "and the tag round-trips through the sim: see the test above"
        );

        assert_eq!(slots[1].count, 0, "nothing was put in the fuel slot");
        assert!(slots[1].held.is_none(), "empty is absent, not a zero stack");
        assert_eq!(slots[1].insert_tag.as_deref(), Some("Fuel"));

        assert_eq!(
            slots[2].insert_tag, None,
            "NOTHING can be inserted into an output slot: `Slot` has no variant \
             for it, so a menu is handed no way to try"
        );
        assert_eq!(slots[2].cap as u32, sim::tuning::SMELTER_OUTPUT_CAP);
    }

    /// **ONE REFUSED PUT CONTROL AND ONE PRESSABLE ONE, IN THE SAME SLOT**
    /// (ASSA-351). This is the payload `hud.gd::insert_slots` used to derive
    /// from the item's kind, which offered both slots for any kind some
    /// non-hand recipe eats — so a pack of grade-A refined got four full-width
    /// controls and `sim::step` refused all four.
    ///
    /// The fixture is the board's own frame in miniature: a pack holding
    /// grade-A refined (which can never enter an input: nothing refines above
    /// A) beside ore of the same species (which can). The crossing has to tell
    /// them apart in one list, keep both rows, and put the SIM's sentence on
    /// the dead one.
    #[test]
    fn a_refused_put_control_crosses_the_sims_own_sentence_and_a_pressable_one_crosses_none() {
        let (mut sim, me) = with_a_player("nacre");
        let rock = sim.world().species[0].id;
        sim.world.species_mut(rock).sheet = sim::Sheet {
            density: 50,
            strength: 50,
            hardness: 30,
            heat_tolerance: 60,
            // Below the fuel threshold on purpose, so the Fuel slot refuses
            // everything and the Input slot is where the interesting split is.
            reactivity: 1,
            conductivity: 50,
        };
        let smelter = Item::new(sim::ItemKind::Smelter, rock, sim::Grade::B);
        let ore = Item::new(sim::ItemKind::Ore, rock, sim::Grade::A);
        let best = Item::new(sim::ItemKind::Refined, rock, sim::Grade::A);
        // Categorically not smelter input and not fuel: the one stack that must
        // get NO row in either slot.
        let gear = Item::new(sim::ItemKind::Gear, rock, sim::Grade::B);
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.inventory.add(smelter, 1);
            p.inventory.add(ore, 7);
            p.inventory.add(best, 2);
            p.inventory.add(gear, 3);
        }
        let at = sim.world().player(me).expect("exists").pos;
        let spot = sim::TilePos::new(at.x + 1, at.y);
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Place {
                item: smelter,
                pos: spot,
            },
        )]);
        let id = sim.world().building_at(spot).expect("placed").id;

        let crossed = sim.insert_offer_facts(Some(me), id.0 as i64);
        let slots: Vec<&str> = crossed.iter().map(|s| s.slot.as_str()).collect();
        assert_eq!(
            slots,
            vec!["Input", "Fuel"],
            "the insertable slots only, in the sim's order: an output slot has \
             no `Slot` variant, so no row is offered for it at all"
        );

        let input = &crossed[0];
        let kinds: Vec<&str> = input.offers.iter().map(|o| o.stack.kind.as_str()).collect();
        assert_eq!(
            kinds,
            vec!["ore", "refined"],
            "a refused stack still gets a row -- the refined is grade A and \
             dead -- but the gear is categorically not input and gets none"
        );
        assert!(
            crossed[1].offers.iter().all(|o| o.stack.kind != "gear"),
            "and the gear is no more fuel than it is input"
        );

        let dead = input
            .offers
            .iter()
            .find(|o| o.stack.kind == "refined")
            .expect("the grade-A refined is in the pack");
        let why = dead
            .refusal
            .as_deref()
            .expect("grade A cannot be refined further, so this control is dead");
        assert!(
            why.contains(sim::debug::best_grade_note()),
            "the reason beside a dead control is the sim's own: {why:?}"
        );
        assert_eq!(
            dead.refusal,
            sim::debug::insert_refusal(sim.world(), me, id, sim::Slot::Input, best, 2),
            "and this crate re-words nothing on the way through"
        );

        let live = input
            .offers
            .iter()
            .find(|o| o.stack.kind == "ore")
            .expect("the ore is in the pack");
        assert_eq!(
            live.refusal, None,
            "ore of the smelter's own species goes in: the fix must not \
             disable the working path"
        );

        // SELF-CHECK ON THE FIXTURE'S OWN AIM. Every assertion above is
        // satisfied by a world where the split never happened — all refused,
        // or all pressable — if the two `find`s happened to land on the same
        // kind of answer. One frame has to contain both.
        let refused = input.offers.iter().filter(|o| o.refusal.is_some()).count();
        let pressable = input.offers.iter().filter(|o| o.refusal.is_none()).count();
        assert_eq!(
            (refused, pressable),
            (1, 1),
            "the point of this fixture is one of each in one list: {:?}",
            input.offers
        );

        // And the slot a sheet reading rules out entirely: unreactive rock is
        // not fuel at any grade, so both rows are dead and both say why.
        let fuel = &crossed[1];
        assert!(
            fuel.offers.iter().all(|o| o.refusal.is_some()),
            "reactivity 1 is below the fuel threshold for every stack here"
        );
    }

    /// **A MACHINE'S ONE HOLDER IS BOUNDED BY ITS OWN PARTS**, not by a tuning
    /// constant — which is the rule a client listing the slots itself would
    /// have had to know. Two drills with different hoppers have different caps,
    /// and the fixture proves the number moves rather than trusting one world.
    #[test]
    fn a_machines_buffer_takes_its_cap_from_the_parts_it_was_built_from() {
        let (mut sim, me) = with_a_player("nacre");
        let species = sim.world().species[0].id;
        let material = Item::new(sim::ItemKind::Refined, species, sim::Grade::B);
        let frame = sim::assembly::Part::of(
            sim::assembly::PartKind::Frame(sim::assembly::Mount::Planted),
            material,
        );
        let head = sim::assembly::Part::of(sim::assembly::PartKind::Head, material);
        let hopper = sim::assembly::Part::of(sim::assembly::PartKind::Hopper, material);
        let bare = sim::assembly::Assembly::new(frame, vec![head]);
        let hoppered = sim::assembly::Assembly::new(frame, vec![head, hopper]);
        let roster = sim.world().species.clone();
        let at = sim.world().player(me).expect("exists").pos;
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.assemblies
                .push(sim::assembly::Built::new(bare.clone(), &roster));
            p.assemblies
                .push(sim::assembly::Built::new(hoppered.clone(), &roster));
        }
        // Planted one tile apart, so both are in the same fact list.
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::PlaceAssembly {
                assembly: 1,
                pos: sim::TilePos::new(at.x + 2, at.y),
            },
        )]);
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::PlaceAssembly {
                assembly: 0,
                pos: sim::TilePos::new(at.x + 3, at.y),
            },
        )]);

        let facts = sim.building_facts();
        assert_eq!(facts.len(), 2, "both machines must plant: {facts:?}");
        for machine in &facts {
            assert_eq!(
                machine.slots.len(),
                1,
                "a machine has one holder, and it is not a smelter's three"
            );
            assert_eq!(machine.slots[0].role, "buffer");
            assert_eq!(
                machine.slots[0].insert_tag, None,
                "ore leaves a drill by Take: a machine has no insertable slot \
                 at all (`RejectReason::NotInsertable`)"
            );
        }
        let caps: Vec<i64> = facts.iter().map(|f| f.slots[0].cap).collect();
        assert_eq!(
            caps[0] as u32,
            hoppered.stats(&roster).capacity,
            "the cap is this machine's own Capacity stat"
        );
        assert_eq!(caps[1] as u32, bare.stats(&roster).capacity);
        assert_ne!(
            caps[0], caps[1],
            "the fixture has to make the number MOVE, or a cap read off a \
             constant would pass this test"
        );
    }

    /// **THE TAG IS NOT `stopped` RENAMED**, and the arm that proves it is a
    /// smelter's idle: the sim says `idle` and `stopped == false` on the same
    /// building, because an empty smelter follows every finished batch and is
    /// not something to fix (ASSA-80, restated on ASSA-94). A client deriving
    /// one from the other would re-litigate that ruling in GDScript.
    #[test]
    fn the_state_tag_and_the_stopped_bool_are_allowed_to_disagree() {
        let (mut sim, me) = with_a_player("nacre");
        let rock = sim.world().species[0].id;
        let smelter = Item::new(sim::ItemKind::Smelter, rock, sim::Grade::B);
        sim.world
            .player_mut(me)
            .expect("the player exists")
            .inventory
            .add(smelter, 1);
        let at = sim.world().player(me).expect("exists").pos;
        let spot = sim::TilePos::new(at.x + 1, at.y);
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Place {
                item: smelter,
                pos: spot,
            },
        )]);

        let facts = sim.building_facts();
        assert_eq!(facts[0].state, "idle");
        assert!(
            !facts[0].stopped,
            "an empty smelter is idle and is NOT a problem: the two fields \
             carry different questions"
        );
        assert_eq!(
            facts[0].state_line,
            sim::debug::building_state_line(sim.world(), sim.world().building_at(spot).unwrap()),
            "the sentence is the sim's one wording, not a second copy"
        );
        assert_eq!(
            facts[0].work, None,
            "nothing is in front of it, so there is no batch to report"
        );
        // AND NO SENTENCE FOR THE BATCH THAT IS NOT THERE (ASSA-334): the menu
        // branches on this to draw no band at all, so an empty string here
        // would reach the screen as a blank row.
        assert_eq!(
            facts[0].work_clause, None,
            "no batch, so no clause: `0 of 20 ticks` on an empty smelter reads as a promise"
        );
        assert_eq!((facts[0].burn_left, facts[0].burn_temperature), (0, 0));
    }

    /// **A SMELTER BLOCKED ON ITS OUTPUT CROSSES AS `stalled`, `stopped`, AND
    /// COLD** (ASSA-350). The window drew a burning fire on this machine for as
    /// long as the condition existed, because `lit` is only
    /// `matches!(state, Working { .. })` and `smelter_state` said `Working`
    /// forever.
    ///
    /// **THIS NEEDS NO BINDING EDIT AND THAT IS THE CLAIM BEING TESTED.** The
    /// `state` arm is a wildcard on the stall reason
    /// (`SmelterState::Stalled(_) => "stalled"`), so a new variant arrives as
    /// the tag a client already reads, `stopped` follows `halted()`, and `lit`
    /// goes false because nothing is burning. I told the Game Director I would
    /// read these three rather than assume them; this is the reading, asserted.
    #[test]
    fn a_smelter_blocked_on_its_output_crosses_as_stalled_stopped_and_cold() {
        let (mut sim, me) = with_a_player("nacre");
        let rock = sim.world().species[0].id;
        let other = sim.world().species[1].id;
        let smelter = Item::new(sim::ItemKind::Smelter, rock, sim::Grade::B);
        sim.world
            .player_mut(me)
            .expect("the player exists")
            .inventory
            .add(smelter, 1);
        let at = sim.world().player(me).expect("exists").pos;
        let spot = sim::TilePos::new(at.x + 1, at.y);
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Place {
                item: smelter,
                pos: spot,
            },
        )]);
        let id = sim.world().building_at(spot).expect("placed").id;

        // Set the slots directly: what is under test is the three fields a
        // window reads, not the rules that get a smelter here (sim's own
        // `smelter.rs` pins those). A burning fire, ore of `rock` in the input,
        // and a bar of refined `other` in the way.
        {
            let b = sim.world.building_mut(id).expect("placed");
            let sim::building::BuildingKind::Smelter(s) = &mut b.kind else {
                panic!("the fixture places a smelter")
            };
            s.input = Some(sim::ItemStack::new(
                Item::new(sim::ItemKind::Ore, rock, sim::Grade::A),
                5,
            ));
            s.output = Some(sim::ItemStack::new(
                Item::new(sim::ItemKind::Refined, other, sim::Grade::A),
                1,
            ));
            s.burn_left = 10;
            s.burn_temperature = 100;
        }

        let facts = sim.building_facts();
        assert_eq!(
            facts[0].state, "stalled",
            "a new stall reason arrives as the tag a client already reads"
        );
        assert!(
            facts[0].stopped,
            "a conflict no supply resolves is something to fix, so it joins halt_lines"
        );
        assert!(
            !facts[0].lit,
            "NOTHING IS BURNING IN IT: the window drew a fire on this machine \
             for as long as smelter_state said Working"
        );
        assert_eq!(
            facts[0].state_line,
            sim::debug::building_state_line(sim.world(), sim.world().building(id).unwrap()),
            "the sentence is the sim's one wording, not a second copy"
        );
        assert!(
            facts[0].state_line.contains("output still holds"),
            "and it names the condition the player has to clear: {}",
            facts[0].state_line
        );
        // THE ITEM IS SPELLED AS THE SLOT SPELLS IT. A player reads the
        // sentence and then looks at the slot; two spellings of one item is
        // ASSA-43/52, which is why the sentence calls `item_name`.
        let held = facts[0].slots[2]
            .held
            .as_ref()
            .expect("the output slot holds the bar this test put there");
        assert!(
            facts[0].state_line.contains(&held.name),
            "the stall names {:?} and the slot row says {:?}",
            facts[0].state_line,
            held.name
        );
    }

    /// The batch crosses as the pair the sim decided, and keeps crossing while
    /// the smelter is STOPPED — the reading a player needs to know that feeding
    /// it resumes rather than restarts.
    #[test]
    fn the_batch_a_smelter_is_part_way_through_crosses_as_two_numbers() {
        let (mut sim, me) = with_a_player("nacre");
        let rock = sim.world().species[0].id;
        let fuel_species = sim.world().species[1].id;
        sim.world.species_mut(rock).sheet = sim::Sheet {
            density: 50,
            strength: 50,
            hardness: 30,
            heat_tolerance: 60,
            reactivity: 1,
            conductivity: 50,
        };
        sim.world.species_mut(fuel_species).sheet = sim::Sheet {
            density: 50,
            strength: 50,
            hardness: 30,
            heat_tolerance: sim::tuning::HAND_SPARK_TEMPERATURE as u8,
            reactivity: 60,
            conductivity: 50,
        };
        let smelter = Item::new(sim::ItemKind::Smelter, rock, sim::Grade::B);
        let ore = Item::new(sim::ItemKind::Ore, rock, sim::Grade::A);
        let fuel = Item::new(sim::ItemKind::Ore, fuel_species, sim::Grade::A);
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.inventory.add(smelter, 1);
            p.inventory.add(ore, 5);
            p.inventory.add(fuel, 1);
        }
        let at = sim.world().player(me).expect("exists").pos;
        let spot = sim::TilePos::new(at.x + 1, at.y);
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Place {
                item: smelter,
                pos: spot,
            },
        )]);
        let id = sim.world().building_at(spot).expect("placed").id;

        // Ore and no fuel: stalled, and the batch has not started.
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Insert {
                building: id,
                slot: sim::Slot::Input,
                item: ore,
                count: 5,
            },
        )]);
        let stalled = &sim.building_facts()[0];
        assert_eq!(stalled.state, "stalled");
        assert_eq!(
            stalled.work,
            Some((0, i64::from(sim::RecipeId::Refine.recipe().ticks))),
            "a stall does not remove the batch in front of it"
        );

        // Now light it and let it work.
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Insert {
                building: id,
                slot: sim::Slot::Fuel,
                item: fuel,
                count: 1,
            },
        )]);
        for _ in 0..6 {
            sim.step_with(&[]);
        }
        let working = &sim.building_facts()[0];
        assert_eq!(working.state, "working");
        let (done, total) = working.work.expect("a working smelter has a batch");
        assert_eq!(total, i64::from(sim::RecipeId::Refine.recipe().ticks));
        assert!(done > 0 && done < total, "mid-batch: {done} of {total}");
        assert!(
            working.burn_left > 0 && working.burn_temperature > 0,
            "a fire is burning in it: {working:?}"
        );
        // THE PAIR IS THE SIM'S, not a number this crate reproduced.
        let theirs = sim
            .world()
            .building_work(sim.world().building(id).expect("standing"))
            .expect("the sim says there is a batch");
        assert_eq!(
            (done, total),
            (i64::from(theirs.done), i64::from(theirs.total))
        );
        // AND THE WORDS FOR IT ARE THE SIM'S TOO (ASSA-334). The menu draws a
        // band off the pair and needs a label; the noun is a sim decision
        // (`work_clause`: "a host that picked the noun would be deciding
        // which"), so the clause crosses rather than being composed in
        // GDScript. **ASSERTED AS PRESENT FIRST**: `Option == Option` is
        // satisfied by two `None`s, and a field that crossed nothing at all
        // would pass a bare `assert_eq!` here on every building in the game.
        assert_eq!(
            working.work_clause,
            sim::debug::work_clause(sim.world(), sim.world().building(id).expect("standing")),
            "the clause is the sim's one wording, not a second copy"
        );
        assert!(
            working
                .work_clause
                .as_deref()
                .is_some_and(|clause| clause.contains("of")),
            "a working smelter has a clause with its two numbers in it: {:?}",
            working.work_clause
        );
        // **NONE EXACTLY WHEN THE PAIR IS NONE**, which is the branch the menu
        // reads: no batch draws no band and no label, never an empty one.
        assert_eq!(
            stalled.work.is_some(),
            stalled.work_clause.is_some(),
            "the pair and the clause disagree about whether there is a batch"
        );
    }

    /// **EVERY PART OF A PLANTED MACHINE CARRIES ITS OWN MATERIAL**, which is
    /// the whole of what makes one drawable (ASSA-138).
    ///
    /// The part sheets have a ROW PER GRADE and are tinted PER SPECIES, so a
    /// renderer handed one grade and one species for the whole machine draws a
    /// mixed drill as if it were all frame — a picture of a machine the player
    /// did not build. That is exactly what this binding used to hand over:
    /// `Vec<String>` of kind names, with one `grade` taken off the frame.
    ///
    /// **THE FIXTURE IS MIXED ON PURPOSE AND THE TEST IS WORTHLESS WITHOUT IT.**
    /// `a_machine_carries_its_parts_frame_first…` builds every part from one
    /// material, so a binding that reported the frame's grade for all of them
    /// would pass it — the assertion cannot fail, which is not evidence. Here
    /// the head is a different species AND a different grade from the frame,
    /// and both facts are asserted to differ before anything else is checked.
    #[test]
    fn a_mixed_material_machine_reports_each_parts_own_species_and_grade() {
        let (mut sim, me) = with_a_player("limpet");
        assert!(
            sim.world().species.len() >= 2,
            "premise: one species in the roster and this test cannot see a mix"
        );
        let first = sim.world().species[0].id;
        let second = sim.world().species[1].id;
        let frame = sim::assembly::Part::of(
            sim::assembly::PartKind::Frame(sim::assembly::Mount::Planted),
            Item::new(sim::ItemKind::Refined, first, sim::Grade::C),
        );
        let head = sim::assembly::Part::of(
            sim::assembly::PartKind::Head,
            Item::new(sim::ItemKind::Refined, second, sim::Grade::A),
        );
        let assembly = sim::assembly::Assembly::new(frame, vec![head]);
        let at = sim.world().player(me).expect("exists").pos;
        let spot = sim::TilePos::new(at.x + 2, at.y);
        let roster = sim.world().species.clone();
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.assemblies
                .push(sim::assembly::Built::new(assembly.clone(), &roster));
        }
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::PlaceAssembly {
                assembly: 0,
                pos: spot,
            },
        )]);
        let facts = sim.building_facts();
        assert_eq!(facts.len(), 1, "the machine was not placed: {facts:?}");
        let parts = &facts[0].parts;
        assert_eq!(parts.len(), 2, "{parts:?}");
        assert_ne!(
            parts[0].grade, parts[1].grade,
            "the fixture stopped being mixed, so this test cannot fail: {parts:?}"
        );
        assert_ne!(
            parts[0].species, parts[1].species,
            "the fixture stopped being mixed, so this test cannot fail: {parts:?}"
        );
        for (part, fact) in assembly.parts().zip(parts.iter()) {
            assert_eq!(fact.kind, part.kind.name());
            assert_eq!(fact.grade, part.material.grade.letter().to_string());
            assert_eq!(fact.species, part.material.species.0 as i64);
            assert_eq!(
                fact.species_name,
                sim.world().species(part.material.species).name(),
                "the name belongs to the PART's species, not the building's"
            );
        }
        // AND THE SAME MACHINE IN THE BENCH MENU SAYS THE SAME THING. These
        // are one object (Maren, ASSA-131 ruling 2) and now literally one
        // function; this is what would catch them being given two again.
        let held = sim.design(-1, true, &sim::assembly::Built::new(assembly, &roster));
        assert_eq!(
            held.parts, *parts,
            "the bench and the map disagree about a drill"
        );
    }

    #[test]
    fn the_halt_lines_are_the_sims_own_in_its_own_order() {
        let (mut sim, me) = with_a_player("limpet");
        let species = sim.world().species[0].id;
        let smelter = Item::new(sim::ItemKind::Smelter, species, sim::Grade::B);
        let ore = Item::new(sim::ItemKind::Ore, species, sim::Grade::B);
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.inventory.add(smelter, 1);
            p.inventory.add(ore, 4);
        }
        let at = sim.world().player(me).expect("exists").pos;
        let spot = sim::TilePos::new(at.x + 1, at.y);
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Place {
                item: smelter,
                pos: spot,
            },
        )]);
        let id = sim
            .world()
            .building_at(spot)
            .expect("the smelter was placed")
            .id;
        assert!(
            sim.halt_line_texts().is_empty(),
            "an empty smelter is idle, not halted, or this surface cries wolf \
             after every finished batch: {:?}",
            sim.halt_line_texts()
        );

        // Ore in, nothing that will burn: the sim's own stall, on its own edge.
        sim.step_with(&[Input::player(
            me,
            sim::PlayerCommand::Insert {
                building: id,
                slot: sim::building::Slot::Input,
                item: ore,
                count: 1,
            },
        )]);

        let lines = sim.halt_line_texts();
        let expected = sim::debug::halt_lines(sim.world(), sim::debug::Audience::Pointed);
        assert!(
            !expected.is_empty(),
            "the fixture stalled nothing, so this test proves nothing"
        );
        assert_eq!(
            lines.len(),
            expected.len(),
            "the binding and the sim disagree about how many have stopped"
        );
        for (i, want) in expected.iter().enumerate() {
            assert_eq!(
                lines[i], *want,
                "line {i} is not the sim's own sentence, in the sim's own order"
            );
        }

        // **THIS USED TO ASSERT THE TERMINAL'S TABLE CONTAINED THE WINDOW'S LINE
        // VERBATIM, AND ASSA-222 BREAKS THAT ON PURPOSE.** The window's reader
        // points, so its line carries no `BuildingId`; the terminal's reader
        // types `take 0`, so its line must. Byte-identity between the two
        // surfaces is no longer the invariant and quietly deleting the check
        // would have thrown away the part that still holds.
        //
        // WHAT STILL HOLDS, AND IT IS THE PART WITH TEETH: they are one wording
        // that differs ONLY by the id. So the terminal's line, with the id taken
        // back out, must be the window's line exactly -- a stall reworded on one
        // surface still shows up right here, which is what this test was for.
        let typed = sim::debug::halt_lines(sim.world(), sim::debug::Audience::Typed);
        let id = sim.world().buildings[0].id.0;
        assert!(
            typed[0].contains(&format!(" {id} at (")),
            "the terminal's reader lost the handle they type into `take`: {}",
            typed[0]
        );
        assert!(
            !expected[0].contains(&format!(" {id} at (")),
            "the window's reader still carries a handle with nothing to type it \
             into: {}",
            expected[0]
        );
        assert_eq!(
            typed[0].replace(&format!(" {id} at ("), " at ("),
            expected[0],
            "the two surfaces differ by more than the id, so one of them has \
             been reworded"
        );
        assert!(
            sim::debug::halted_table(sim.world()).contains(&typed[0]),
            "the terminal's own table no longer contains the terminal's line: {}",
            sim::debug::halted_table(sim.world())
        );
    }

    // ----- ASSA-140: the demo asks the sim which drill this world carries ---

    /// The showcase seed, pinned everywhere: `window_shot.gd`, every picture
    /// the board has been shown, and the demo request.
    const SHOWCASE_SEED: u64 = 14247;

    /// THE WORLD THE DEMO IS STANDING IN WHEN IT PLANTS, which is not a fresh
    /// one: it has mined and ASSAYED the starter material, so that species'
    /// sheet reads exact and the verdict is formed on numbers rather than on a
    /// 25-wide band. Maren's first pass measured a fresh world and got
    /// UNCERTAIN almost everywhere -- a property of the band, not the design.
    ///
    /// Only the MATERIAL is assayed, not the whole roster: that is what the
    /// loop actually does, and a single-species drill reads no other sheet.
    fn assayed_world(seed: u64) -> (World, i64) {
        let mut world = sim_net::fresh_world(seed);
        let (material, _) = sim::ladder::starter_species(&world.species)
            .expect("every world has a starter pair; ASSA-139 pins that");
        for species in &mut world.species {
            if species.id == material {
                species.assayed = true;
            }
        }
        (world, i64::from(material.0))
    }

    /// The sim's verdict for each hopper count 0..=MAX on the demo's drill.
    fn verdicts(world: &World, material: i64) -> Vec<String> {
        (0..=sim::tuning::MAX_HOPPER_SLOTS)
            .map(|hoppers| {
                let mut mounted = vec!["head".to_string()];
                mounted.extend(std::iter::repeat_n("hopper".to_string(), hoppers as usize));
                let facts = design_if_built_facts(world, "frame", &mounted, material, "A");
                assert!(
                    facts.fault.is_empty(),
                    "{hoppers} hoppers is inside MAX_HOPPER_SLOTS and was refused: {facts:?}"
                );
                facts.verdict
            })
            .collect()
    }

    /// **THE PROJECTION AND THE BUILT LIST MUST NEVER DISAGREE**, because the
    /// whole point is that a run can ask before it spends 500 ticks and then
    /// get what it was promised. Both read `Assembly::stat_range`; what this
    /// catches is one of them growing a second way to assemble the parts --
    /// a mount, an order, a grade applied to the wrong part.
    ///
    /// Driven at every hopper count and at all three grades, because a
    /// single-count version of this stayed green under a mutation that swapped
    /// the head's material for the frame's: with one species they are equal.
    #[test]
    fn the_verdict_for_a_design_not_yet_built_is_the_one_it_gets_when_it_is() {
        let (mut sim, me) = with_a_player("marlow");
        // **ONE ASSAYED SPECIES AND ONE ROUGH ONE, because a roster where every
        // sheet reads exact has `low == high` on every stat and CANNOT SEE a
        // band mixed up.** My first version assayed all six: a mutation setting
        // `mass_high` to `mass_low` left all fifteen assertions green, and a
        // client would have drawn a banded design as a certainty.
        sim.world.species[0].assayed = true;
        sim.world.species[1].assayed = false;
        let mut seen: Vec<String> = Vec::new();
        let mut saw_a_band = false;
        for (index, grade) in [
            (0usize, sim::Grade::C),
            (0, sim::Grade::B),
            (0, sim::Grade::A),
            (1, sim::Grade::C),
            (1, sim::Grade::B),
            (1, sim::Grade::A),
        ] {
            let material = i64::from(sim.world().species[index].id.0);
            for hoppers in 0..=sim::tuning::MAX_HOPPER_SLOTS as usize {
                let item = Item::new(ItemKind::Refined, sim.world().species[index].id, grade);
                let real = Built::new(
                    Assembly::new(
                        sim::Part::new(sim::PartKind::Frame(Mount::Planted), item),
                        std::iter::once(sim::Part::new(sim::PartKind::Head, item))
                            .chain(
                                std::iter::repeat_n((), hoppers)
                                    .map(|()| sim::Part::new(sim::PartKind::Hopper, item)),
                            )
                            .collect(),
                    ),
                    &sim.world().species,
                );
                sim.world.player_mut(me).expect("the player").assemblies = vec![real];
                let built = sim.design_facts(Some(me))[0].clone();

                let mut mounted = vec!["head".to_string()];
                mounted.extend(std::iter::repeat_n("hopper".to_string(), hoppers));
                let asked = design_if_built_facts(
                    sim.world(),
                    "frame",
                    &mounted,
                    material,
                    &grade.letter().to_string(),
                );
                assert_eq!(
                    (
                        &asked.verdict,
                        asked.mass_low,
                        asked.mass_high,
                        asked.budget_low,
                        asked.budget_high
                    ),
                    (
                        &built.verdict,
                        built.mass_low,
                        built.mass_high,
                        built.budget_low,
                        built.budget_high
                    ),
                    "{hoppers} hoppers at grade {}: asked {asked:?}, built {built:?}",
                    grade.letter()
                );
                saw_a_band = saw_a_band
                    || asked.mass_low < asked.mass_high
                    || asked.budget_low < asked.budget_high;
                seen.push(asked.verdict);
            }
        }
        assert!(
            saw_a_band,
            "every design read exact, so swapping a band's ends is invisible here"
        );
        // THE PREMISE: an agreement over fifteen identical answers proves
        // nothing. The mass of a frame plus n hoppers is strictly increasing in
        // n and the budget does not move with it, so this population has to
        // hold more than one verdict or the fixture is degenerate.
        seen.sort();
        seen.dedup();
        assert!(
            seen.len() > 1,
            "every count and grade agreed, so this test cannot see a disagreement: {seen:?}"
        );
    }

    // -----------------------------------------------------------------------
    // ASSA-325: the whole readout, for a design made of the parts a pack holds.
    // -----------------------------------------------------------------------

    /// One item as the text `design_readout` takes.
    fn item_of(kind: ItemKind, species: sim::SpeciesId, grade: sim::Grade) -> String {
        serde_json::to_string(&Item::new(kind, species, grade)).expect("an item spells")
    }

    /// `(frame, mounted)` as texts, and the `Assembly` they stand for, so every
    /// test below can ask the binding and the sim the same question.
    fn design_of(
        parts: &[(sim::PartKind, sim::SpeciesId, sim::Grade)],
    ) -> (String, Vec<String>, Assembly) {
        let texts: Vec<String> = parts
            .iter()
            .map(|(k, s, g)| item_of(ItemKind::Part(*k), *s, *g))
            .collect();
        let as_part = |(k, s, g): &(sim::PartKind, sim::SpeciesId, sim::Grade)| {
            sim::Part::of(*k, Item::new(ItemKind::Refined, *s, *g))
        };
        let (frame, mounted) = parts.split_first().expect("a frame");
        let assembly = Assembly::new(as_part(frame), mounted.iter().map(as_part).collect());
        (texts[0].clone(), texts[1..].to_vec(), assembly)
    }

    /// **EVERY NUMBER IS `Assembly::stat_range`'S, not this crate's.** Driven
    /// over two species (one assayed, one rough), all three grades and every
    /// legal hopper count, because a roster that reads exact everywhere has
    /// `low == high` on every stat and cannot see a band's ends swapped.
    ///
    /// The two premises at the end are the test's own honesty: a population
    /// that held one verdict, or no band at all, would agree with anything.
    #[test]
    fn every_number_the_build_readout_crosses_is_the_sims_own() {
        let (mut sim, _me) = with_a_player("limpet");
        sim.world.species[0].assayed = true;
        sim.world.species[1].assayed = false;
        let mut verdicts: Vec<String> = Vec::new();
        let mut saw_a_band = false;
        for index in [0usize, 1] {
            let species = sim.world().species[index].id;
            for grade in [sim::Grade::C, sim::Grade::B, sim::Grade::A] {
                for hoppers in 0..=sim::tuning::MAX_HOPPER_SLOTS as usize {
                    let mut parts = vec![
                        (sim::PartKind::Frame(Mount::Planted), species, grade),
                        (sim::PartKind::Head, species, grade),
                    ];
                    parts.extend(std::iter::repeat_n(
                        (sim::PartKind::Hopper, species, grade),
                        hoppers,
                    ));
                    let (frame, mounted, assembly) = design_of(&parts);
                    let got = design_readout_facts(sim.world(), &frame, &mounted);
                    let range = assembly.stat_range(&sim.world().species);

                    assert!(
                        got.fault.is_empty(),
                        "{hoppers} hoppers was refused: {got:?}"
                    );
                    assert_eq!(
                        (
                            got.verdict.as_str(),
                            got.mass_low,
                            got.mass_high,
                            got.budget_low,
                            got.budget_high,
                            got.speed_low,
                            got.speed_high,
                            got.capacity_low,
                            got.capacity_high,
                            got.swings_low,
                            got.swings_high,
                            got.held,
                        ),
                        (
                            range.verdict().label(),
                            range.low.mass as i64,
                            range.high.mass as i64,
                            range.low.budget as i64,
                            range.high.budget as i64,
                            range.low.speed as i64,
                            range.high.speed as i64,
                            range.low.capacity as i64,
                            range.high.capacity as i64,
                            i64::from(sim::debug::swings_afforded(range.low.durability)),
                            i64::from(sim::debug::swings_afforded(range.high.durability)),
                            false,
                        ),
                        "species {index} grade {} with {hoppers} hoppers: {got:?} against {range:?}",
                        grade.letter()
                    );
                    saw_a_band = saw_a_band
                        || got.speed_low < got.speed_high
                        || got.swings_low < got.swings_high;
                    verdicts.push(got.verdict);
                }
            }
        }
        assert!(
            saw_a_band,
            "every design read exact, so swapping a band's ends is invisible here"
        );
        verdicts.sort();
        verdicts.dedup();
        assert!(
            verdicts.len() > 1,
            "every design agreed, so this fixture cannot see a disagreement: {verdicts:?}"
        );
    }

    /// **THE CASE THAT MADE THIS A SECOND ENTRY POINT RATHER THAN THREE FIELDS
    /// ON `design_if_built`.** A head a grade lower really does make a slower,
    /// shorter-lived machine, and a question that takes one grade for the whole
    /// design cannot say so -- while mass and budget, which is all
    /// `design_if_built` answers, genuinely do not move.
    ///
    /// Asserted in both directions: the two numbers that must NOT move, and the
    /// two that MUST. Without the second half this test would pass against a
    /// readout that ignored the mounted parts' grades entirely.
    #[test]
    fn a_pack_holding_two_grades_is_weighed_part_by_part() {
        let (mut sim, _me) = with_a_player("limpet");
        sim.world.species[0].assayed = true;
        let rock = sim.world().species[0].id;
        let ask = |head: sim::Grade| {
            let (frame, mounted, _) = design_of(&[
                (sim::PartKind::Frame(Mount::Held), rock, sim::Grade::A),
                (sim::PartKind::Head, rock, head),
            ]);
            design_readout_facts(sim.world(), &frame, &mounted)
        };
        let best = ask(sim::Grade::A);
        let worse = ask(sim::Grade::C);

        assert_eq!(
            (
                best.mass_low,
                best.mass_high,
                best.budget_low,
                best.budget_high
            ),
            (
                worse.mass_low,
                worse.mass_high,
                worse.budget_low,
                worse.budget_high
            ),
            "the head's grade must not move mass or budget -- that is the claim\n\
             `design_if_built`'s single grade rests on: {best:?} against {worse:?}"
        );
        assert!(
            worse.speed_high < best.speed_high && worse.swings_high < best.swings_high,
            "a grade-C head must give a slower, shorter-lived tool, or this\n\
             readout is ignoring the grades of the parts it was handed:\n\
             {worse:?} against {best:?}"
        );
        assert!(best.held, "a handle frame is held");
        assert_eq!(
            best.hand_speed,
            i64::from(sim::tuning::HAND_WORK_PER_TICK),
            "the baseline speed is only legible against is the sim's constant"
        );
    }

    /// **A DESIGN THE RULES THROW OUT CROSSES NO NUMBERS**, read field by field.
    ///
    /// Every number zero and `held` false. A client that drew a bar off a
    /// refused design would draw one for a machine that cannot exist, and the
    /// three refusals here are step's three, in step's order.
    #[test]
    fn a_refused_design_crosses_no_numbers_at_all() {
        let (mut sim, _me) = with_a_player("limpet");
        sim.world.species[0].assayed = true;
        let rock = sim.world().species[0].id;
        let head = item_of(ItemKind::Part(sim::PartKind::Head), rock, sim::Grade::A);
        let handle = item_of(
            ItemKind::Part(sim::PartKind::Frame(Mount::Held)),
            rock,
            sim::Grade::A,
        );
        let ore = item_of(ItemKind::Ore, rock, sim::Grade::A);

        for (what, frame, mounted) in [
            ("an ore in the frame slot", ore.clone(), vec![head.clone()]),
            ("an ore mounted", handle.clone(), vec![ore.clone()]),
            (
                "two heads on a handle",
                handle.clone(),
                vec![head.clone(), head.clone()],
            ),
            ("not an item at all", "{}".to_string(), vec![head.clone()]),
            // ADDED BY ASSA-324, AND IT PANICKED HERE UNTIL `plan` GATED IT.
            // This entry point's refusal chain was its own copy of `step`'s,
            // minus the first link: the species roster is checked in `step`'s
            // precheck, where a readout could not reach it, and
            // `stat_range` indexes `world.species` raw. Measured on main
            // `e27ef54`: `index out of bounds: the len is 6 but the index is
            // 200`, from `assembly.rs:684`. Nothing in `client/` calls
            // `design_readout` yet and `item_json` will spell species 200 for
            // anyone who asks, so this is the hole that was waiting rather
            // than the crash that happened. Kept in THIS loop rather than a
            // parallel test: a refused design says one thing, whatever
            // refused it.
            (
                "a species this world never rolled",
                item_of(
                    ItemKind::Part(sim::PartKind::Frame(Mount::Held)),
                    sim::SpeciesId(200),
                    sim::Grade::A,
                ),
                vec![head.clone()],
            ),
            (
                "a made-up species on a mounted part, not the frame",
                handle.clone(),
                vec![item_of(
                    ItemKind::Part(sim::PartKind::Head),
                    sim::SpeciesId(200),
                    sim::Grade::A,
                )],
            ),
        ] {
            let got = design_readout_facts(sim.world(), &frame, &mounted);
            assert!(!got.fault.is_empty(), "{what} should have a fault: {got:?}");
            // THE ZEROS ARE WRITTEN OUT HERE AND NOT TAKEN FROM
            // `DesignReadout::refused`, and a mutation is why. Comparing
            // against that constructor compared the function with itself: a
            // mutation putting 7 in one of its fields left this GREEN. A
            // struct literal also makes a new field a COMPILE error here,
            // which is stronger than a red -- whoever adds one has to decide
            // what a refused design says about it.
            assert_eq!(
                got,
                DesignReadout {
                    verdict: String::new(),
                    fault: got.fault.clone(),
                    mass_low: 0,
                    mass_high: 0,
                    budget_low: 0,
                    budget_high: 0,
                    speed_low: 0,
                    speed_high: 0,
                    hand_speed: 0,
                    swings_low: 0,
                    swings_high: 0,
                    capacity_low: 0,
                    capacity_high: 0,
                    held: false,
                    // ASSA-329 decided here, because this literal made it a
                    // compile error: **false, and that is a claim, not a
                    // zero.** None of the cases above is a design a later
                    // press could rescue — `TooFew` is the only recoverable
                    // fault and it is not in this loop, deliberately, because
                    // its numbers are REAL. See
                    // `a_design_being_placed_crosses_its_numbers_and_no_verdict`.
                    unfinished: false,
                },
                "{what}: a refusal must carry the fault and NOTHING else: {got:?}"
            );
        }

        // THE PREMISE, or the loop above would pass against a readout that
        // refused everything: the legal version of the same parts answers.
        let (frame, mounted, _) = design_of(&[
            (sim::PartKind::Frame(Mount::Held), rock, sim::Grade::A),
            (sim::PartKind::Head, rock, sim::Grade::A),
        ]);
        let fine = design_readout_facts(sim.world(), &frame, &mounted);
        assert!(fine.fault.is_empty() && fine.mass_low > 0, "{fine:?}");
    }

    /// **A DESIGN STILL BEING PLACED CROSSES ITS NUMBERS AND NO VERDICT**
    /// (ASSA-329). The third state, which this readout was built for: the
    /// build screen's bars have to move as parts go in, and before this a held
    /// frame's only two states were "empty" and "done".
    ///
    /// The sibling of `a_refused_design_crosses_no_numbers_at_all` and
    /// deliberately not a case inside it: a refusal's numbers are all zero and
    /// this one's are real, so one loop cannot ask both questions.
    #[test]
    fn a_design_being_placed_crosses_its_numbers_and_no_verdict() {
        let (mut sim, _me) = with_a_player("marlow");
        sim.world.species[0].assayed = true;
        let rock = sim.world().species[0].id;
        let handle = item_of(
            ItemKind::Part(sim::PartKind::Frame(Mount::Held)),
            rock,
            sim::Grade::A,
        );
        let head = item_of(ItemKind::Part(sim::PartKind::Head), rock, sim::Grade::A);

        let placing = design_readout_facts(sim.world(), &handle, &[]);
        assert!(
            placing.unfinished,
            "a handle with its one slot empty is a design you are still \
             placing, not one the rules threw out: {placing:?}"
        );
        assert!(
            placing.verdict.is_empty(),
            "SAFE is a sentence about a machine that exists: {placing:?}"
        );
        // THE SIM'S PHRASE, NOT THIS CRATE'S. Compared against the sim's own
        // function rather than a string spelled here, so a reworded slot fault
        // cannot drift between the log and the screen.
        assert_eq!(
            placing.fault,
            sim::debug::assembly_error_phrase(sim::AssemblyError::TooFew {
                kind: sim::PartKind::Head,
                have: 0,
                min: 1,
            }),
            "{placing:?}"
        );
        // AND THE NUMBERS ARE REAL, which is the entire difference from a
        // refusal. The frame's budget is what the mass is a fraction of, and
        // it exists before any head does.
        assert!(
            placing.budget_high > 0 && placing.mass_high > 0 && placing.hand_speed > 0,
            "a half-built design has a mass and a budget: {placing:?}"
        );
        assert!(placing.held, "a handle is a held frame: {placing:?}");

        // THE PREMISE: filling the slot turns the same design into a machine,
        // so `unfinished` is reporting the slot and not a constant.
        let done = design_readout_facts(sim.world(), &handle, &[head]);
        assert!(
            !done.unfinished && !done.verdict.is_empty() && done.fault.is_empty(),
            "a head finishes it: {done:?}"
        );
        // And the budget did not move: it is the FRAME's, so the bar the
        // player watches fill has a fixed end.
        assert_eq!(
            (placing.budget_low, placing.budget_high),
            (done.budget_low, done.budget_high),
            "the budget is the frame's, so it must not move as parts go in"
        );
        assert!(
            done.mass_high > placing.mass_high,
            "and the mass must have MOVED, or there was nothing live to watch: \
             {placing:?} then {done:?}"
        );
    }

    /// **DURABILITY CROSSES AS SWINGS AND THE POOL NEVER CROSSES AT ALL**
    /// (ADR 0003 amendment A10). The number here is the pool over
    /// `PICK_WEAR_PER_SWING`, which is what `durability_readout` has printed
    /// since ASSA-5, and the pool is what a bar drawn off it would leak:
    /// divided by 60 it IS the head's effective strength.
    ///
    /// The constant is 20, so a readout that crossed the pool by mistake would
    /// be twenty times this and the inequality below is not cosmetic.
    #[test]
    fn durability_crosses_as_swings_and_never_as_the_pool() {
        let (mut sim, _me) = with_a_player("limpet");
        sim.world.species[0].assayed = true;
        let rock = sim.world().species[0].id;
        let (frame, mounted, assembly) = design_of(&[
            (sim::PartKind::Frame(Mount::Held), rock, sim::Grade::A),
            (sim::PartKind::Head, rock, sim::Grade::A),
        ]);
        let got = design_readout_facts(sim.world(), &frame, &mounted);
        let pool = assembly.stat_range(&sim.world().species).high.durability;

        assert!(pool > 0, "the fixture needs a head that gives a pool");
        assert_eq!(
            got.swings_high,
            i64::from(sim::debug::swings_afforded(pool)),
            "swings must come from the sim's own division"
        );
        assert!(
            got.swings_high < i64::from(pool),
            "the pool itself ({pool}) must never be what crosses: {got:?}"
        );
        // And a planted design says it is not held, so a client cannot draw a
        // pool on a drill -- the Game Director's ruling, crossed as data.
        let (frame, mounted, _) = design_of(&[
            (sim::PartKind::Frame(Mount::Planted), rock, sim::Grade::A),
            (sim::PartKind::Head, rock, sim::Grade::A),
        ]);
        let drill = design_readout_facts(sim.world(), &frame, &mounted);
        assert!(!drill.held, "a planted frame is not held: {drill:?}");
        assert!(
            drill.capacity_high > 0,
            "a drill buffers something: {drill:?}"
        );
    }

    // -----------------------------------------------------------------------
    // ASSA-347: block 6 on the assembly path. What a design costs THIS pack,
    // and which one stack the sim says is in the way.
    // -----------------------------------------------------------------------

    /// One part as a pack holds it, for stocking a fixture.
    fn part_stack(kind: sim::PartKind, species: sim::SpeciesId, grade: sim::Grade) -> Item {
        Item::new(ItemKind::Part(kind), species, grade)
    }

    /// `(frame, mounted)` texts parsed back into the items `plan` takes, so a
    /// test can ask the sim the same question the binding was asked.
    fn items_of(frame: &str, mounted: &[String]) -> (Item, Vec<Item>) {
        let read = |t: &str| serde_json::from_str::<Item>(t).expect("the fixture spells items");
        (read(frame), mounted.iter().map(|t| read(t)).collect())
    }

    /// **THE BILL IS `plan`'S OWN TALLY AND THE PACK COLUMN IS
    /// `Inventory::count`** — asked of the sim separately and compared row for
    /// row, so this crate cannot grow a second opinion about what a press
    /// spends.
    ///
    /// The fixture is deliberately a tally AND a shortfall at once: two hoppers
    /// of one material must be ONE entry needing two (the spend is
    /// all-or-nothing, so two rows a player can half-afford would be a lie),
    /// and the pack holds one of them, which is the only row `blocks` may land
    /// on here.
    #[test]
    fn the_bill_is_plans_own_tally_and_the_pack_is_inventory_count() {
        let (mut sim, me) = with_a_player("limpet");
        let rock = sim.world().species[0].id;
        let grade = sim::Grade::B;
        let planted = sim::PartKind::Frame(Mount::Planted);
        let (frame, mounted, _) = design_of(&[
            (planted, rock, grade),
            (sim::PartKind::Head, rock, grade),
            (sim::PartKind::Hopper, rock, grade),
            (sim::PartKind::Hopper, rock, grade),
        ]);
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.inventory.add(part_stack(planted, rock, grade), 1);
            p.inventory
                .add(part_stack(sim::PartKind::Head, rock, grade), 1);
            p.inventory
                .add(part_stack(sim::PartKind::Hopper, rock, grade), 1);
        }
        let got = design_cost_facts(sim.world(), Some(me), &frame, &mounted);

        let (frame_item, mounted_items) = items_of(&frame, &mounted);
        let pack = &sim.world().player(me).expect("exists").inventory;
        let plan = sim::assembly::plan(frame_item, &mounted_items, &sim.world().species, pack);
        let sim::assembly::AssemblyPlan::Weighed { cost, missing, .. } = &plan else {
            panic!("a planted frame with a head and hoppers is a machine: {plan:?}");
        };
        assert_eq!(
            cost.len(),
            3,
            "the premise: two hoppers tally into one stack, so this is three \
             rows and not four: {cost:?}"
        );
        let billed: Vec<(String, i64, i64, bool)> = got
            .entries
            .iter()
            .map(|e| (e.name.clone(), e.need, e.have, e.blocks))
            .collect();
        let planned: Vec<(String, i64, i64, bool)> = cost
            .iter()
            .map(|s| {
                (
                    sim.world().item_name(s.item),
                    i64::from(s.count),
                    i64::from(pack.count(s.item)),
                    *missing == Some(s.item),
                )
            })
            .collect();
        assert_eq!(
            billed, planned,
            "the bill is the plan's, row for row and in `part_items` order: {got:?}"
        );
        let hopper = got
            .entries
            .iter()
            .find(|e| e.kind == "hopper")
            .unwrap_or_else(|| panic!("the hoppers are a row: {got:?}"));
        assert_eq!(
            (hopper.need, hopper.have, hopper.blocks),
            (2, 1, true),
            "the premise: this fixture has to hold a tally and a shortfall at \
             once, or it agrees with anything: {got:?}"
        );
        assert!(
            got.refusal.contains(&sim.world().item_name(part_stack(
                sim::PartKind::Hopper,
                rock,
                grade
            ))),
            "the sim's sentence names the stack it stopped at: {got:?}"
        );
    }

    /// **ONLY THE SIM'S BLOCKER IS MARKED, AND IT IS NOT THE LAST SHORT ROW.**
    ///
    /// The Game Director's second condition on ASSA-317 (A): `missing` is
    /// `Option<Item>` — the FIRST uncovered stack — so a screen marks ONE
    /// blocker and may not fake the rest. The obvious wrong client loops the
    /// bill and reds every row whose `have` is short, which looks identical
    /// until two rows are short; this pack holds the hoppers and neither the
    /// frame nor the head, so the right answer is the frame alone and the wrong
    /// one is two rows.
    ///
    /// It pins the SENTENCE the same way: it names the frame and must not name
    /// the head, which is what `cost.iter().find(…)` picked and what a client
    /// composing its own sentence off the last shortfall would get wrong.
    #[test]
    fn only_the_sims_own_blocker_is_marked_even_when_two_rows_are_short() {
        let (mut sim, me) = with_a_player("limpet");
        let rock = sim.world().species[0].id;
        let grade = sim::Grade::B;
        let planted = sim::PartKind::Frame(Mount::Planted);
        let (frame, mounted, _) = design_of(&[
            (planted, rock, grade),
            (sim::PartKind::Head, rock, grade),
            (sim::PartKind::Hopper, rock, grade),
            (sim::PartKind::Hopper, rock, grade),
        ]);
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.inventory
                .add(part_stack(sim::PartKind::Hopper, rock, grade), 2);
        }
        let got = design_cost_facts(sim.world(), Some(me), &frame, &mounted);

        let marked: Vec<&CostEntry> = got.entries.iter().filter(|e| e.blocks).collect();
        assert_eq!(
            marked.len(),
            1,
            "exactly one row may be marked, whatever the pack is short of: {got:?}"
        );
        assert_eq!(
            marked[0].kind, "frame",
            "the frame is the FIRST stack the pack cannot cover: {got:?}"
        );
        let head = got
            .entries
            .iter()
            .find(|e| e.kind == "head")
            .unwrap_or_else(|| panic!("the head is a row: {got:?}"));
        assert!(
            head.have < head.need && !head.blocks,
            "the premise AND the claim: the head is short too and is still not \
             the blocker, so reddening every short row is a different answer \
             from this one: {got:?}"
        );
        assert!(
            got.refusal
                .contains(&sim.world().item_name(part_stack(planted, rock, grade)))
                && !got.refusal.contains(&sim.world().item_name(part_stack(
                    sim::PartKind::Head,
                    rock,
                    grade
                ))),
            "the sentence blames `plan`'s choice, not the last short row: {got:?}"
        );
    }

    /// **A COST ROW SPELLS ITS ITEM EXACTLY AS A PACK ROW DOES** (ASSA-146).
    ///
    /// `item_of_stack` in GDScript builds a command's item out of a pack stack,
    /// and block 6's rows are the same items one layer over; a second spelling
    /// of grade or of the species name is how two surfaces stop agreeing about
    /// one item. Held against `inventory_facts` — the function `inventory_of`
    /// crosses — rather than against the keys I remember writing.
    #[test]
    fn an_entry_spells_its_item_the_way_the_pack_row_does() {
        let (mut sim, me) = with_a_player("limpet");
        let rock = sim.world().species[0].id;
        let grade = sim::Grade::C;
        let held = sim::PartKind::Frame(Mount::Held);
        let (frame, mounted, _) =
            design_of(&[(held, rock, grade), (sim::PartKind::Head, rock, grade)]);
        {
            let p = sim.world.player_mut(me).expect("the player exists");
            p.inventory.add(part_stack(held, rock, grade), 1);
            p.inventory
                .add(part_stack(sim::PartKind::Head, rock, grade), 1);
        }
        let got = design_cost_facts(sim.world(), Some(me), &frame, &mounted);
        let pack = sim.inventory_facts(Some(me));

        assert_eq!(got.entries.len(), 2, "a pick is two parts: {got:?}");
        assert_eq!(
            pack.len(),
            got.entries.len(),
            "the premise: the pack holds exactly this design's parts, so every \
             row has a twin to be compared with: {pack:?}"
        );
        for entry in &got.entries {
            let twin = pack
                .iter()
                .find(|s| s.name == entry.name)
                .unwrap_or_else(|| panic!("no pack row for {}: {pack:?}", entry.name));
            assert_eq!(
                (
                    entry.kind.as_str(),
                    entry.species,
                    entry.species_name.as_str(),
                    entry.grade.as_str(),
                ),
                (
                    twin.kind.as_str(),
                    twin.species,
                    twin.species_name.as_str(),
                    twin.grade.as_str(),
                ),
                "a cost row and a pack row spell one item two ways: {entry:?} \
                 against {twin:?}"
            );
        }
    }

    /// **A DESIGN STILL BEING PLACED IS BILLED FOR WHAT IS SELECTED SO FAR**,
    /// which is what makes block 6 move with every click instead of appearing
    /// on the last one (ASSA-329's rule, applied to the bill).
    ///
    /// And the two calls a build screen makes have to agree about the state:
    /// `design_readout` says `unfinished` for this same selection, so a screen
    /// cannot read "not a machine" beside a bill, or a bill beside nothing.
    #[test]
    fn a_design_still_being_placed_bills_what_is_selected_so_far() {
        let (sim, me) = with_a_player("limpet");
        let rock = sim.world().species[0].id;
        let grade = sim::Grade::A;
        let held = sim::PartKind::Frame(Mount::Held);
        let (frame, none, _) = design_of(&[(held, rock, grade)]);
        assert!(none.is_empty(), "a bare frame mounts nothing");

        let placing = design_cost_facts(sim.world(), Some(me), &frame, &none);
        assert!(
            design_readout_facts(sim.world(), &frame, &none).unfinished,
            "the premise: a handle with no head is the half-placed state"
        );
        assert_eq!(
            placing
                .entries
                .iter()
                .map(|e| (e.kind.as_str(), e.need, e.have, e.blocks))
                .collect::<Vec<_>>(),
            vec![("handle", 1, 0, true)],
            "a half-placed design bills the frame it already has: {placing:?}"
        );
        assert!(
            !placing.refusal.is_empty(),
            "an empty pack cannot pay for it, and that is the sim's sentence: {placing:?}"
        );

        // One more click, one more row: the bill grows with the selection.
        let (frame, mounted, _) =
            design_of(&[(held, rock, grade), (sim::PartKind::Head, rock, grade)]);
        let done = design_cost_facts(sim.world(), Some(me), &frame, &mounted);
        assert_eq!(
            done.entries.len(),
            2,
            "mounting the head adds its row: {done:?}"
        );
    }

    /// **A DESIGN THE RULES THROW OUT IS NOT BILLED AT ALL, and its sentence
    /// has one home.** `design_readout`'s `fault` words a slot fault; a
    /// have/need block that repeated it would be telling a player their pack is
    /// the problem when it is not.
    ///
    /// The three ways a caller can ask nothing — no player yet (the frame
    /// before a `Welcome`), a player this world does not have, and text that is
    /// not an item — are an empty answer rather than a panic, which is
    /// `inventory_facts`' rule and the one `design_readout` learned the
    /// expensive way (species 200 indexed the roster raw and panicked).
    #[test]
    fn a_design_the_rules_throw_out_is_not_billed_at_all() {
        let (sim, me) = with_a_player("limpet");
        let rock = sim.world().species[0].id;
        let grade = sim::Grade::B;
        // A handle has no hopper slot at all: nothing a later click can rescue.
        let (frame, mounted, _) = design_of(&[
            (sim::PartKind::Frame(Mount::Held), rock, grade),
            (sim::PartKind::Hopper, rock, grade),
        ]);
        let refused = design_cost_facts(sim.world(), Some(me), &frame, &mounted);
        assert_eq!(
            refused,
            DesignCost::default(),
            "a refused design has no bill and no pack sentence: {refused:?}"
        );
        assert!(
            !design_readout_facts(sim.world(), &frame, &mounted)
                .fault
                .is_empty(),
            "the premise: the sentence for this design lives on the readout, \
             which is why there is none here"
        );

        let (good, mounted, _) = design_of(&[
            (sim::PartKind::Frame(Mount::Held), rock, grade),
            (sim::PartKind::Head, rock, grade),
        ]);
        assert_eq!(
            design_cost_facts(sim.world(), None, &good, &mounted),
            DesignCost::default(),
            "a client with no player id yet asks for nothing"
        );
        assert_eq!(
            design_cost_facts(sim.world(), Some(PlayerId(9999)), &good, &mounted),
            DesignCost::default(),
            "a player this world does not have is an empty answer, not a panic"
        );
        assert_eq!(
            design_cost_facts(sim.world(), Some(me), "not an item", &mounted),
            DesignCost::default(),
            "text that is not an item is refused by serde, not guessed at"
        );
        assert!(
            !design_cost_facts(sim.world(), Some(me), &good, &mounted)
                .entries
                .is_empty(),
            "the premise: this same design DOES bill, so the empties above are \
             the refusals and not the fixture"
        );
    }

    /// **WHY ONE GRADE IS ENOUGH TO ASK WITH, even though the demo's pack can
    /// hold parts of two.** The frame's grade decides the whole answer: mass is
    /// size times density and density never scales with grade, and `Stat::Budget`
    /// is contributed by frame rows only. So a drill whose head and hoppers came
    /// out of the fire a grade lower weighs and carries exactly what the
    /// single-grade projection said it would.
    ///
    /// ASSERTED AND NOT ASSUMED, because `button_play.gd` asks with the grade of
    /// the stack it is about to press `Frame` on and nothing else: if a future
    /// part row ever reads grade for mass, this reddens and that call is wrong.
    ///
    /// **IT IS THE FOUR NUMBERS AND NOT THE WHOLE `StatRange`**, and I had this
    /// too wide first: the head contributes SPEED from hardness and DURABILITY
    /// from strength, both of which DO scale, so a grade-C head really does
    /// change the machine -- just not what it weighs or what carries it. The
    /// claim this projection rests on is only about mass and budget.
    #[test]
    fn only_the_frames_grade_moves_a_single_species_drill() {
        let (mut sim, _me) = with_a_player("marlow");
        sim.world.species[0].assayed = true;
        let id = sim.world().species[0].id;
        let mut moved = 0;
        for frame_grade in [sim::Grade::C, sim::Grade::B, sim::Grade::A] {
            let all_one = |g: sim::Grade| {
                let item = Item::new(ItemKind::Refined, id, g);
                Assembly::new(
                    sim::Part::new(sim::PartKind::Frame(Mount::Planted), item),
                    vec![
                        sim::Part::new(sim::PartKind::Head, item),
                        sim::Part::new(sim::PartKind::Hopper, item),
                    ],
                )
                .stat_range(&sim.world().species)
            };
            let mixed = {
                let frame = Item::new(ItemKind::Refined, id, frame_grade);
                let rest = Item::new(ItemKind::Refined, id, sim::Grade::C);
                Assembly::new(
                    sim::Part::new(sim::PartKind::Frame(Mount::Planted), frame),
                    vec![
                        sim::Part::new(sim::PartKind::Head, rest),
                        sim::Part::new(sim::PartKind::Hopper, rest),
                    ],
                )
                .stat_range(&sim.world().species)
            };
            let weighed = |r: sim::assembly::StatRange| {
                (r.low.mass, r.high.mass, r.low.budget, r.high.budget)
            };
            assert_eq!(
                weighed(all_one(frame_grade)),
                weighed(mixed),
                "a grade-C head and hopper changed a grade-{} frame's mass or budget",
                frame_grade.letter()
            );
            assert_eq!(
                all_one(frame_grade).verdict(),
                mixed.verdict(),
                "a grade-C head and hopper changed a grade-{} frame's verdict",
                frame_grade.letter()
            );
            if weighed(all_one(frame_grade)) != weighed(all_one(sim::Grade::C)) {
                moved += 1;
            }
        }
        // THE PREMISE: if grade moved nothing at all, the equality above is
        // trivially true and this test cannot fail. The frame's budget does
        // scale with grade, so two of the three must differ from grade C.
        assert_eq!(
            moved, 2,
            "the frame's grade moved no budget, so this test proves nothing"
        );
    }

    /// AN ILLEGAL DESIGN IS REFUSED IN THE SIM'S OWN WORDS, and refusing is not
    /// the same as weighing nothing: a caller that read `verdict` as "not SAFE"
    /// and planted anyway is the failure this shape exists to prevent.
    #[test]
    fn a_design_the_rules_refuse_comes_back_with_the_sims_phrase_and_no_verdict() {
        let (world, material) = assayed_world(SHOWCASE_SEED);
        let too_many: Vec<String> = std::iter::once("head".to_string())
            .chain(std::iter::repeat_n(
                "hopper".to_string(),
                sim::tuning::MAX_HOPPER_SLOTS as usize + 1,
            ))
            .collect();
        for (frame, mounted, expect) in [
            ("frame", too_many.clone(), "at most"),
            ("frame", vec!["hopper".to_string()], "at least"),
            (
                "handle",
                vec!["head".to_string(), "hopper".to_string()],
                "no hopper slot",
            ),
            ("head", vec!["head".to_string()], "must be a frame"),
            (
                "sprocket",
                vec!["head".to_string()],
                "is not a machine part",
            ),
        ] {
            let facts = design_if_built_facts(&world, frame, &mounted, material, "A");
            assert!(
                facts.verdict.is_empty() && facts.mass_high == 0 && facts.budget_low == 0,
                "{frame} + {mounted:?} was weighed anyway: {facts:?}"
            );
            assert!(
                facts.fault.contains(expect),
                "{frame} + {mounted:?}: wanted {expect:?} in {:?}",
                facts.fault
            );
        }
        // And a legal one still answers, so the assertions above are not just
        // "this function always refuses".
        let ok = design_if_built_facts(
            &world,
            "frame",
            &["head".to_string(), "hopper".to_string()],
            material,
            "A",
        );
        assert!(ok.fault.is_empty() && !ok.verdict.is_empty(), "{ok:?}");
    }

    /// **BOTH OF ASSA-140'S RUNS ARE RELIABLE ON THE PINNED SEED.** The
    /// showcase run needs a count the sim calls SAFE so its last beat can be a
    /// machine standing; the break run needs one the sim calls WILL BREAK so
    /// ASSA-37's box is exercised rather than satisfied by luck. On 14247 the
    /// demo's hard-coded 4 is WILL BREAK (1078 mass against a 705 budget) and
    /// 0 or 1 is SAFE, so this seed carries both.
    #[test]
    fn the_showcase_seed_carries_both_a_standing_drill_and_a_breaking_one() {
        let (world, material) = assayed_world(SHOWCASE_SEED);
        let v = verdicts(&world, material);
        assert!(
            v.iter().any(|x| x == "SAFE"),
            "seed {SHOWCASE_SEED} has no SAFE drill, so the showcase run cannot stand: {v:?}"
        );
        assert!(
            v.iter().any(|x| x == "WILL BREAK"),
            "seed {SHOWCASE_SEED} has no breaking drill, so the break run has nothing: {v:?}"
        );
        // The counts are ordered by mass, so SAFE can never come after WILL
        // BREAK. A policy picking "the largest SAFE" and "the smallest WILL
        // BREAK" relies on that and it is a property of the sim, not of a seed.
        let last_safe = v.iter().rposition(|x| x == "SAFE").expect("checked above");
        let first_break = v
            .iter()
            .position(|x| x == "WILL BREAK")
            .expect("checked above");
        assert!(last_safe < first_break, "{v:?}");
    }

    /// **HOW OFTEN THE SHOWCASE RUN CAN PAY OFF AT ALL**, over the population
    /// and not over the pinned seed, because Wren's bar is "a drill standing
    /// AND mining on a large majority of seeds".
    ///
    /// Through `design_if_built_facts`, which is the function the client calls,
    /// so this measures the shipped path rather than a copy of it.
    ///
    /// THE THRESHOLD IS A FLOOR UNDER A MEASURED NUMBER, NOT A TARGET: 81.2% of
    /// 2000 worlds hold at least one SAFE count for the starter material at
    /// grade A. The remaining 18.8% is ASSA-140's open box 6 -- the frame is
    /// made of the species `ladder::starter_species` picked for its HARDNESS,
    /// which is what a head reads, while the frame's budget is its STRENGTH.
    /// Letting the frame pick on strength out of rung zero raises this to
    /// 93.7%, measured the same way, and costs the demo a third mining stretch;
    /// that is the Game Director's call and it is asked on the item.
    #[test]
    fn a_large_majority_of_worlds_hold_a_drill_the_demo_can_stand_up() {
        const SEEDS: u64 = 2000;
        let mut has_safe = 0u32;
        let mut has_break = 0u32;
        let mut largest_safe = [0u32; sim::tuning::MAX_HOPPER_SLOTS as usize + 1];
        for seed in 0..SEEDS {
            let (world, material) = assayed_world(seed);
            let v = verdicts(&world, material);
            if let Some(n) = v.iter().rposition(|x| x == "SAFE") {
                has_safe += 1;
                largest_safe[n] += 1;
            }
            if v.iter().any(|x| x == "WILL BREAK") {
                has_break += 1;
            }
        }
        let pc = |n: u32| 100.0 * f64::from(n) / SEEDS as f64;
        assert!(
            pc(has_safe) >= 75.0,
            "only {:.1}% of {SEEDS} worlds hold a SAFE drill for the starter material \
             (largest-safe-count spread {largest_safe:?}); the showcase run's payoff is no \
             longer a large majority",
            pc(has_safe)
        );
        // THE BREAK RUN IS THE HALF THAT CANNOT BE MADE RELIABLE, and this
        // number is why, stated so nobody reads box 4 as closed: a WILL BREAK
        // drill is reachable in 44.9% of worlds from the starter material and
        // 64.7% if the frame may be any rung-zero species -- never all of
        // them. MAX_HOPPER_SLOTS is 4 and mass is the only dial, so in the rest
        // there is no over-budget design to plant. The break run is reliable on
        // the seeds the gate pins and honest about the population elsewhere.
        assert!(
            pc(has_break) < 100.0 && has_break > 0,
            "a breaking drill is reachable in {:.1}% of worlds; if that is now every world, \
             the break run can be made unconditional and box 4's note is stale",
            pc(has_break)
        );
    }
}
