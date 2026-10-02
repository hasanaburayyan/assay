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
use sim::command::Input;
use sim::hash::fnv64;
use sim::world::{World, WorldConfig};
use sim_net::TickBundle;

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
    last_events: Vec<String>,
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

    /// Apply one `Tick` bundle: its inputs, then one `step`.
    ///
    /// Returns false and changes nothing unless the bundle is numbered with the
    /// tick we are AT. Applying bundles out of order is precisely how a peer
    /// desyncs, so this refuses rather than guesses.
    #[func]
    pub fn apply_bundle_json(&mut self, text: GString) -> bool {
        let bundle: TickBundle = match serde_json::from_str(&text.to_string()) {
            Ok(b) => b,
            Err(why) => {
                godot_error!("sim-godot: could not read a tick bundle: {why}");
                return false;
            }
        };
        self.apply_bundle(&bundle)
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

    #[func]
    pub fn width_tiles(&self) -> i64 {
        self.world.width_chunks as i64 * 16
    }

    #[func]
    pub fn height_tiles(&self) -> i64 {
        self.world.height_chunks as i64 * 16
    }

    #[func]
    pub fn player_count(&self) -> i64 {
        self.world.players.len() as i64
    }

    /// What the last applied bundle caused, as lines a client can show.
    #[func]
    pub fn last_events(&self) -> PackedStringArray {
        self.world_events()
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
        self.last_events = events.iter().map(|event| format!("{event:?}")).collect();
    }

    pub fn hash_hex_string(&self) -> String {
        format!("{:016x}", fnv64(&self.world))
    }

    pub fn seed_hex_string(&self) -> String {
        format!("{:016x}", self.world.seed)
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
        self.last_events.iter().map(GString::from).collect()
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

    #[test]
    fn a_message_that_is_not_a_welcome_is_an_error() {
        assert!(AssaySim::world_from_welcome(r#"{"Refused":{"reason":"no"}}"#).is_err());
    }
}
