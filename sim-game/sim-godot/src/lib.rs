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
use sim::assembly::{Assembly, Built, Mount};
use sim::building::Slot;
use sim::command::{Event, Input, StopReason};
use sim::hash::fnv64;
use sim::item::Item;
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
                vdict! {
                    "id" => species.id,
                    "name" => &gstring(&species.name).to_variant(),
                    "assayed" => species.assayed,
                    "readings" => &readings.to_variant(),
                    "hand_minable" => species.hand_minable,
                    "hand_lit_fuel" => species.hand_lit_fuel,
                }
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
    /// can only say "assay something", and half of all designs at grade B are
    /// UNCERTAIN.
    pub unassayed: Vec<String>,
    pub parts: Vec<PartFacts>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SpeciesFacts {
    pub id: i64,
    pub name: String,
    pub assayed: bool,
    /// Property name to reading: the exact value once assayed, the sim's band
    /// ("26-50") until then.
    pub readings: Vec<(String, String)>,
    pub hand_minable: bool,
    pub hand_lit_fuel: bool,
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

    /// One event as a sentence. `me` is written "you"; everyone else is named.
    pub fn describe(&self, me: Option<PlayerId>, event: &Event) -> String {
        let world = &self.world;
        let who = |player: PlayerId| match me {
            Some(mine) if mine == player => "you".to_string(),
            _ => world
                .player(player)
                .map_or(format!("player {}", player.0), |found| found.name.clone()),
        };
        let item = |item: &Item| world.item_name(*item);
        let species = |id: SpeciesId| world.species(id).name().to_string();
        match event {
            Event::PlayerJoined { player, name } => match me {
                Some(mine) if mine == *player => format!("you joined as {name}"),
                _ => format!("{name} joined"),
            },
            Event::MoveStarted { player, to, .. } => {
                format!("{} set off for ({}, {})", who(*player), to.x, to.y)
            }
            Event::PlayerArrived { player, pos } => {
                format!("{} arrived at ({}, {})", who(*player), pos.x, pos.y)
            }
            Event::PlayerStopped { player, pos } => {
                format!("{} stopped at ({}, {})", who(*player), pos.x, pos.y)
            }
            Event::MiningStarted {
                player,
                deposit,
                species: id,
            } => format!(
                "{} started mining {} at deposit {}",
                who(*player),
                species(*id),
                deposit.0
            ),
            Event::OreMined {
                player,
                deposit,
                item: mined,
                amount,
            } => format!(
                "{} mined {amount} {} ({} left in deposit {})",
                who(*player),
                item(mined),
                world.deposit(*deposit).map_or(0, |found| found.amount),
                deposit.0
            ),
            Event::MiningStopped {
                player,
                deposit,
                reason,
            } => format!(
                "{} stopped mining deposit {}: {}",
                who(*player),
                deposit.0,
                stop_reason(*reason)
            ),
            Event::DepositDepleted { deposit } => format!("deposit {} is mined out", deposit.0),
            Event::SpeciesDiscovered {
                player,
                species: id,
            } => {
                format!("{} discovered {}", who(*player), species(*id))
            }
            Event::AssayStarted {
                player,
                deposit,
                species: id,
            } => format!(
                "{} started assaying {} at deposit {} ({} ticks)",
                who(*player),
                species(*id),
                deposit.0,
                sim::tuning::ASSAY_TICKS
            ),
            Event::AssayStopped {
                player,
                deposit,
                reason,
            } => format!(
                "{} stopped assaying deposit {}: {}",
                who(*player),
                deposit.0,
                stop_reason(*reason)
            ),
            Event::SpeciesAssayed {
                player,
                species: id,
            } => format!(
                "{} assayed {}: its sheet is exact for everyone now",
                who(*player),
                species(*id)
            ),
            Event::SpeciesRenamed {
                player,
                species: id,
                name,
            } => format!("{} renamed species {} to {name}", who(*player), id.0),
            Event::RenameGranted {
                species: id,
                from,
                to,
            } => format!("{} let {} rename {}", who(*from), who(*to), species(*id)),
            Event::CraftStarted {
                player,
                recipe,
                item: made,
                count,
            } => format!(
                "{} started {} × {} ({})",
                who(*player),
                count,
                item(made),
                recipe.recipe().name
            ),
            Event::ItemCrafted {
                player,
                item: made,
                count,
                remaining,
                ..
            } => format!(
                "{} made {count} {}{}",
                who(*player),
                item(made),
                if *remaining > 0 {
                    format!(" ({remaining} batches to go)")
                } else {
                    String::new()
                }
            ),
            Event::CraftingStopped {
                player,
                recipe,
                reason,
            } => format!(
                "{} stopped making {}: {}",
                who(*player),
                recipe.recipe().name,
                stop_reason(*reason)
            ),
            Event::BuildingPlaced {
                player,
                building,
                item: built,
                pos,
            } => format!(
                "{} placed {} {} at ({}, {})",
                who(*player),
                item(built),
                building.0,
                pos.x,
                pos.y
            ),
            Event::BuildingRemoved {
                player,
                building,
                item: taken,
                pos,
            } => format!(
                "{} picked up {} {} at ({}, {})",
                who(*player),
                item(taken),
                building.0,
                pos.x,
                pos.y
            ),
            Event::ItemsInserted {
                player,
                building,
                slot,
                item: put,
                count,
            } => format!(
                "{} put {count} {} in building {}'s {} slot",
                who(*player),
                item(put),
                building.0,
                slot_name(*slot)
            ),
            Event::ItemsTaken {
                player,
                building,
                item: took,
                count,
            } => format!(
                "{} took {count} {} from building {}",
                who(*player),
                item(took),
                building.0
            ),
            Event::ItemSmelted {
                building,
                item: smelted,
                count,
            } => format!("building {} smelted {count} {}", building.0, item(smelted)),
            // The reason is the sim's own enum. A player reading "NotOnDeposit"
            // is reading a word, not a code, and a client that translated it
            // would be guessing which rule refused them.
            Event::CommandRejected { player, reason, .. } => {
                format!("{}: refused — {reason:?}", who(*player))
            }
            // AN EVENT THIS CLIENT HAS NO WORDING FOR YET, SHOWN RAW RATHER
            // THAN DROPPED OR REFUSED TO COMPILE. Unreachable today, which is
            // why the allow is here and why it is worth keeping anyway.
            //
            // This arm exists because of a measured collision, not in case:
            // ASSA-5 part 2 adds six `Event` variants, and an exhaustive match
            // here meant the sim could not grow an event without breaking the
            // client's BUILD. Rules lead and clients follow (repo CLAUDE.md), so
            // the client may not be a brake on `sim`. Debug text is ugly on
            // purpose: it is visibly a thing somebody should write a sentence
            // for, which a silent drop would not be.
            #[allow(unreachable_patterns)]
            other => format!("{other:?}"),
        }
    }
}

fn stop_reason(reason: StopReason) -> &'static str {
    match reason {
        StopReason::Stopped => "stopped",
        StopReason::LeftDeposit => "walked off it",
        StopReason::Depleted => "mined it out",
        StopReason::OutOfInputs => "ran out of inputs",
    }
}

fn slot_name(slot: Slot) -> &'static str {
    match slot {
        Slot::Input => "ore",
        Slot::Fuel => "fuel",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh() -> World {
        World::new(WorldConfig {
            seed: 4242,
            width_chunks: 6,
            height_chunks: 4,
        })
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
        assert!(
            durability.starts_with("100% of "),
            "a design nobody has used yet is full: {durability}"
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
            !exact.contains('%') && exact.contains('/'),
            "an assayed design reads exact, got {exact}"
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

    /// EVENTS ARE SENTENCES, NOT DEBUG DUMPS, and the one about me says "you".
    /// `{event:?}` is still available as `last_events` for an engineer; what a
    /// player reads may not contain `PlayerId(0)`.
    #[test]
    fn an_event_about_me_says_you_and_never_leaks_debug_shapes() {
        let (sim, me) = with_a_player("limpet");
        let species = sim.world().species[0].id;
        let item = Item::new(sim::ItemKind::Ore, species, sim::Grade::C);
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
        ];
        for event in &events {
            let line = sim.describe(Some(me), event);
            assert!(!line.is_empty(), "{event:?} described as nothing");
            assert!(
                !line.contains("PlayerId(") && !line.contains("SpeciesId("),
                "{event:?} leaked a Debug shape: {line}"
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
}
