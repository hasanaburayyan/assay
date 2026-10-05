use sim::world::{World, WorldConfig};

/// **FINDING A SEED THE ASSA-209 DEFECT CAN BE PHOTOGRAPHED ON, which box 3 requires.**
///
/// Seed 777042 -- the one every ASSA-187/199 picture was taken on -- has no purple and no M-blue dead
/// end at all, so the sample that judged the mark excluded exactly the two species where it vanishes
/// (Maren's finding). This prints the seeds that carry BOTH, ranked by how dim the dimmer of the two
/// is, because `deposit_color` dims the fill with purity and the worst pair is the bar she ruled.
#[test]
fn limpet_find_a_seed_with_a_dark_dead_end_pair() {
    let mut found: Vec<(u32, u32, u32, u32, usize)> = Vec::new();
    for seed in 1..=4000u64 {
        let w = World::new(WorldConfig {
            seed,
            width_chunks: 6,
            height_chunks: 4,
        });
        let mut purple: Option<u32> = None;
        let mut mblue: Option<u32> = None;
        for d in &w.deposits {
            if sim::debug::deposit_dead_end_note(&w, d).is_none() {
                continue;
            }
            let slot = (d.species.0 as usize) % 6;
            let p = d.purity as u32;
            if slot == 0 && purple.is_none_or(|q| p < q) {
                purple = Some(p);
            }
            if slot == 4 && mblue.is_none_or(|q| p < q) {
                mblue = Some(p);
            }
        }
        if let (Some(a), Some(b)) = (purple, mblue) {
            found.push((seed as u32, a, b, a.max(b), w.deposits.len()));
        }
    }
    found.sort_by_key(|r| r.3);
    println!(
        "seeds carrying BOTH a purple and an M-blue dead end: {} of 4000",
        found.len()
    );
    println!("seed    purple purity  M-blue purity  worse of the two  deposits");
    for r in found.iter().take(12) {
        println!("{:<7} {:>13} {:>14} {:>17} {:>9}", r.0, r.1, r.2, r.3, r.4);
    }
}
