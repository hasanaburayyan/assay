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
    /// `Welcome`. Wording lives here, in a host, because presentation is a
    /// host's job — the other one is `sim-cli`'s `describe_event`, which adds
    /// typed-command hints this client has no use for. If the two ever have to
    /// agree word for word, the fix is one describer in `sim::debug`, not a
    /// copy of this in GDScript.
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
        let who = player_id_of(me);
        self.last_events
            .iter()
            .filter(|event| sim::debug::event_needs_attention(who, event))
            .map(|event| gstring(&self.describe(who, event)))
            .collect()
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
            .map(|stack| {
                vdict! {
                    "kind" => &gstring(&stack.kind).to_variant(),
                    "species" => stack.species,
                    "species_name" => &gstring(&stack.species_name).to_variant(),
                    "grade" => &gstring(&stack.grade).to_variant(),
                    "count" => stack.count,
                    "name" => &gstring(&stack.name).to_variant(),
                }
            })
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
                let mut row = vdict! {
                    "id" => species.id,
                    "name" => &gstring(&species.name).to_variant(),
                    "symbol" => &gstring(&species.symbol).to_variant(),
                    "assayed" => species.assayed,
                    "readings" => &readings.to_variant(),
                    "hand_minable" => species.hand_minable,
                    "hand_lit_fuel" => species.hand_lit_fuel,
                };
                // ABSENT, not empty, when the sim does not call this rock fuel
                // (ASSA-93) -- the same shape `durability` and the design note
                // use, so a panel cannot print a blank tag for a rock that
                // simply is not fuel.
                if let Some(lighting) = &species.lighting {
                    row.set("lighting", &gstring(lighting).to_variant());
                }
                row
            })
            .collect()
    }

    /// EVERYTHING THIS PLAYER COULD MAKE BY HAND, as the crafting menu's rows:
    /// `line`, `dead_end`, `verb`, `tag`, and the input stack's own `kind` /
    /// `species` / `grade` / `count`.
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
                Some(vdict! {
                    "line" => &gstring(&offer.line).to_variant(),
                    "dead_end" => &gstring(&offer.dead_end).to_variant(),
                    "verb" => &gstring(verb).to_variant(),
                    "tag" => &tag,
                    "kind" => &gstring(offer.input.kind.name()).to_variant(),
                    "species" => offer.input.species.0 as i64,
                    "grade" => &gstring(&offer.input.grade.letter().to_string()).to_variant(),
                    "count" => offer.have as i64,
                })
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
    #[func]
    pub fn deposits(&self) -> Array<VarDictionary> {
        self.world
            .deposits
            .iter()
            .map(|deposit| {
                vdict! {
                    "id" => deposit.id.0 as i64,
                    "species" => deposit.species.0 as i64,
                    "center" => Vector2i::new(deposit.center.x, deposit.center.y),
                    "radius" => deposit.radius as i64,
                    "amount" => deposit.amount as i64,
                    "purity" => deposit.purity as i64,
                    "symbol" => &gstring(
                        &sim::debug::species_symbol(self.world.species(deposit.species))
                            .to_string(),
                    ).to_variant(),
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

    /// EVERY PART THE CATALOGUE HOLDS: `name`, `size`, `material` and `tag`.
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
    #[func]
    pub fn part_kinds() -> Array<VarDictionary> {
        PartKind::ALL
            .iter()
            .filter_map(|kind| {
                let tag = tag_variant(&serde_json::to_value(kind).ok()?)?;
                Some(vdict! {
                    "name" => &gstring(kind.name()).to_variant(),
                    "size" => &(sim::assembly::spec(*kind).size as i64).to_variant(),
                    "material" => &gstring(Self::PART_MATERIAL.name()).to_variant(),
                    "tag" => &tag,
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

fn building_dict(building: &BuildingFacts) -> VarDictionary {
    vdict! {
        "id" => building.id,
        "kind" => &gstring(&building.kind).to_variant(),
        "pos" => Vector2i::new(building.pos.0, building.pos.1),
        "status" => &gstring(&building.status).to_variant(),
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
    pub pos: (i32, i32),
    pub status: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TileFacts {
    pub in_bounds: bool,
    pub pos: (i32, i32),
    pub chunk: (i32, i32),
    pub chunks_from_spawn: i64,
    pub is_spawn: bool,
    pub deposit: Option<DepositFacts>,
    pub building: Option<BuildingFacts>,
    pub players_here: Vec<String>,
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
    pub hand_minable: bool,
    pub hand_lit_fuel: bool,
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
                self.world.building_at(at).map(|building| BuildingFacts {
                    id: building.id.0 as i64,
                    kind: building.kind.name().to_string(),
                    pos: (building.pos.x, building.pos.y),
                    status: sim::debug::building_status(&self.world, building),
                })
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
                hand_minable: sim::ladder::hand_minable(species),
                hand_lit_fuel: sim::ladder::hand_lit_fuel(species),
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
            parts: a
                .parts()
                .map(|part| {
                    let species = self.world.species(part.material.species);
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
                })
                .collect(),
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
    pub fn describe(&self, me: Option<PlayerId>, event: &Event) -> String {
        sim::debug::event_line(&self.world, me, event)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn with_a_player(name: &str) -> (AssaySim, PlayerId) {
        let mut sim = AssaySim::from_world(fresh());
        sim.step_with(&[Input::System(sim::SystemCommand::AddPlayer {
            name: name.to_string(),
        })]);
        let id = sim.world().players.first().expect("a player was added").id;
        (sim, id)
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
            press_refusal_text(&[handle.clone()], &hopper),
            sim::debug::assembly_error_phrase(sim::AssemblyError::NoSuchSlot(PartKind::Hopper)),
        );
        // A handle first is merely unfinished, so the press is confirmed.
        assert_eq!(press_refusal_text(&[], &handle), "");
        // And a head on it completes a tool.
        assert_eq!(press_refusal_text(&[handle], &head), "");
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
}
