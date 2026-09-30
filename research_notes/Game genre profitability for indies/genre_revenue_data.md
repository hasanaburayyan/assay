# PC/Steam (and briefly console/mobile) revenue and profitability by genre for small indie studios

Research date: 2026-09-29. All Steam revenue figures below are third-party ESTIMATES (Gamalytic, VG Insights/Sensor Tower, Alinea Analytics, GameDiscoverCo, Games-Stats), not Valve-audited. Unless stated, "revenue" = GROSS (before Valve's 30% cut, VAT, refunds, returns, regional pricing). A common rule of thumb in the sources: net to developer is roughly 35-57% of gross estimate (Immutable, 2026) or ~70% of gross after Valve cut only (HTMAG: $150k gross ~ $105k after Valve cut, before tax).

Important definitional caveat for the report writer: "genre" figures in all sources are computed per Steam TAG, and games carry many tags, so genre buckets overlap and are not additive. Also, "indie" is defined very differently: VG Insights counted Black Myth: Wukong and Palworld as "indie" in 2024 (self-published), whereas Alinea's 2025 figures use a narrower definition. This produces the apparent conflict of indie = 48% (VGI 2024) vs 25% (Alinea 2025) of Steam revenue.

---

## 1. Median and mean revenue by genre/tag for indie Steam games (2023-2026)

### Takeaway
Median outcomes are tiny across almost every genre (all-releases median ~$220-250 gross for 2024/2025 cohorts; lifetime tag medians mostly $1k-$10k), but the spread between genres is large: Open World Survival Craft, 4X, Colony Sim, Roguelike Deckbuilder, City Builder and Grand Strategy consistently post medians 5-20x higher than Action, Puzzle, Horror, Idle and 2D Platformer. Means are dominated by a handful of hits (top 1% of games take ~84.5% of revenue).

### Cited Findings

**Overall cohort medians/means (gross, Gamalytic-derived)**
- Median gross revenue per game released in 2025: $249; 2024 cohort: $222 (lowest of 2020-2025; 2025 second-lowest). Mean (average) 2025: $358,900, heavily skewed by AAA — [game-developers.org, "The Steam Paradox 2025" (Gamalytic data)](https://game-developers.org/steam-paradox-2025-revenue-volume)
- $249 gross median ~ $174 net after Valve's 30% cut (2025) — [WN Hub / SteamData summaries](https://wnhub.io/news/analytics/item-49645) (secondary; consistent with Gamalytic figure above)
- Revenue concentration: top 1% of Steam games earn 84.5% of estimated revenue — [GamesRadar+ (reporting a Steam revenue-distribution chart; date/source methodology not visible in fetched excerpt)](https://www.gamesradar.com/games/behold-the-whole-history-of-steams-economy-in-one-picture-the-top-1-percent-of-games-earn-84-5-percent-of-estimated-revenue-and-most-games-barely-make-anything/)
- Aggregator claim: "median indie game earns $5,000-$15,000 in lifetime gross revenue; top 5% earn over $1M" — [SteamPageAnalyzer blog (2026)](https://www.steampageanalyzer.com/blog/indie-game-revenue-data). CAUTION: low-quality aggregator, conflicts with the $222-$249 cohort median above; likely filters out hobby/shovelware titles. Treat as "median of games that are 'real' commercial indie releases," not all releases.

**Lifetime median gross revenue by tag — Immutable benchmark (licensed third-party estimation dataset, snapshot 10 Sept 2026, all games ever released with that tag; gross)** — [Immutable, "What does the median game in your genre earn on Steam?" (2026)](https://www.immutable.com/insights/steam-genre-revenue-benchmarks)

| Sub-genre tag | Games on Steam w/ tag | Median copies | Median gross revenue |
|---|---|---|---|
| Open World Survival Craft | 684 | 7,290 | $102,000 |
| 4X | 648 | 3,900 | $50,000 |
| JRPG | 4,359 | 1,490 | $21,000 |
| Colony Sim | 1,167 | 2,280 | $17,300 |
| RTS | 2,894 | 1,390 | $16,700 |
| Grand Strategy | 1,298 | 1,550 | $14,700 |
| Dating Sim | 5,541 | 1,780 | $14,400 |
| Visual Novel | 12,646 | 1,140 | $10,300 |
| RPG | 24,666 | 979 | $9,770 |
| Farming Sim | 1,494 | 1,080 | $8,690 |
| Souls-like | 2,044 | 1,040 | $8,460 |
| Adventure | 52,404 | 726 | $6,520 |
| Strategy | 27,804 | 578 | $4,040 |
| Idler | 4,358 | 574 | $2,870 |
| Horror | 15,142 | 867 | $2,590 |
| Action | 53,193 | 508 | $2,530 |
| Puzzle | 26,452 | 477 | $2,390 |
| Survival Horror | 5,430 | 683 | $2,050 |
| Match 3 | 1,673 | 298 | $1,830 |
| 2D Platformer | 11,366 | 209 | $1,040 |

- Same source: median across all 107 sub-genre tags = $4,837 gross; 56 of 107 tags have median < $5,000; 81 of 107 < $10,000; only 26 of 107 >= $10,000. Battle Royale excluded (F2P leaders skew). Net estimate ~$1,693-$2,757 for the $4,837 gross median (35-57% net band) — [Immutable (2026)](https://www.immutable.com/insights/steam-genre-revenue-benchmarks)
- Note: "games on Steam w/ tag" counts in Immutable table appear to count all tagged apps (Adventure 52k, Action 53k), so they measure tag prevalence, not unique genre membership.

**Median NET revenue by tag — GameDiscoverCo using Games-Stats.com data (publication date not confirmed in fetch; likely 2024 — flag as possibly older)** — [GameDiscoverCo, "Which genre should your next PC game be in?"](https://newsletter.gamediscover.co/p/which-genre-should-your-next-pc-game)

| Tag | Median net revenue |
|---|---|
| Colony Sim (292 games) | $44,000 |
| Roguelike Deckbuilder | $38,000 |
| 4X | $35,000 |
| City Builder | $22,000 |
| Grand Strategy | $19,000 |
| Driving | $4,500 |
| Action RPG | $4,300 |
| Baseline (all Steam) | ~$2,600; $5,000 described as "good" |

- Author caveats: all games carry multiple tags; broad tags contain many low-cost semi-pro titles that drag medians down — same source.
- Note the conflict with Immutable (Colony Sim $17.3k gross vs GameDiscoverCo $44k net): different datasets, filters (GameDiscoverCo likely filtered to more "serious" releases) and dates. Both agree on the ranking (colony sim / 4X / grand strategy / survival craft near the top).

**Mean revenue per game by subgenre (games earning > $1M only, all-time; GameDiscoverCo, July 2025)** — [Game World Observer, July 2025](https://gameworldobserver.com/2025/07/01/analytics-three-quarters-of-game-revenue-on-steam-comes-from-action-and-rpgs)
- Highest average: Arena shooters, $634.8M average across 29 games (F2P giants).
- Lowest averages among $1M+ games: Visual novels $4.2M; Roguelike deckbuilders $3.4M (i.e., these genres produce many modest $1M+ hits, few mega-hits).
- Genre share of Steam revenue (among $1M+ games): Action 58.37%, RPG 17.11%, Strategy 13.97%, Simulation 9.76%, Sports 1%.
- Subgenre totals: Arena shooters $9.52B (18.99% of Action); FPS $6.67B; Action RPG $3.89B (26.45% of RPG); MMORPG $3.69B; CRPG $2.69B; MOBA $2.31B (19.23% of Strategy); RTS $1.84B; Grand strategy $1.16B; General sim $3.74B (44.57% of Sim); Job sim $1.36B; Racing $942.89M.
- Gamalytic-based claim (2025): Sandbox is "the most reliably bankable genre on Steam, with both the highest median and top decile revenue" — [search summary of game-developers.org / 80.lv Gamalytic coverage](https://80.lv/articles/analysts-report-drop-in-game-revenue-on-steam-despite-growing-number-of-releases) (exact numbers not retrieved — see Gaps).

**Friendslop / co-op example revenues (HTMAG, July 2026, GameDiscoverCo/Alinea data)** — [How To Market A Game, "Is Friendslop saturated?" (2026)](https://howtomarketagame.com/2026/07/30/is-friendslop-saturated/)
- Mage Arena: ~624,000 copies in one week; ~$3,698,080 net.
- Comparable ~$4M outcomes in other genres: Dragon Sword Awakening (RPG) $4,584,900; SAND: Raiders of Sophie (battle royale) $4,822,700; Scritchy Scratchy (idle/clicker) $3,966,620.
- Friendslop market is winner-take-most in cycles: Content Warning took 47% of the friendslop player market then faded; Chained Together 48%; PEAK 50%; RV There Yet 50%; cycles last 3-9 months. Peak CCU records: Lethal Company 197k (Dec 2023), R.E.P.O. 281k (Mar 2025), MECCHA CHAMELEON launch pushed the category to 350k concurrent.

**Top indie releases 2025 (gross, Alinea Analytics)** — [Game World Observer, Dec 2025](https://gameworldobserver.com/2025/12/22/indie-projects-generated-a-quarter-of-the-total-game-revenue-on-steam-by-the-end-of-2025-analytics)
- Schedule I $151M; R.E.P.O. $147M; PEAK $87M; Hollow Knight: Silksong $75M; Escape from Duckov $53M. These five = ~3% of all Steam game revenue in 2025. Genres: co-op sim/crime-sim, co-op horror friendslop, co-op climbing friendslop, metroidvania, extraction shooter.
- Steam total game revenue Jan 1-Dec 19 2025: $17.7B; indie ~ $4.4B (25%) — same source.

### Inferences
- For chart purposes, the Immutable table (2026, gross, lifetime, all games) is the most complete consistent single-source genre median set; GameDiscoverCo net medians can be a second series with a "different methodology/likely 2024" flag.
- Strategy-depth genres (4X, colony sim, grand strategy, city builder, RTS) and survival-craft have the best MEDIAN outcomes, i.e. they are most forgiving for a competent but non-viral game. Action, horror, puzzle and 2D platformer have poor medians despite occasionally huge hits.
- Genres with low mean-per-$1M-hit (VN, roguelike deckbuilder) are "many small/medium successes" genres — reasonable for small teams since scope is low.

### Gaps
- Could not retrieve Gamalytic's per-genre median and top-decile numbers for the 2025 cohort (only the qualitative "Sandbox highest median and top decile" claim).
- No dataset found with per-genre median restricted specifically to 2-5 person teams.
- VG Insights 2024 Global Indie Games Market Report PDF could not be parsed (image-based); its genre tables were not extracted.
- No reliable per-genre medians found for: extraction shooters, MOBA, MMO, fighting, sports, auto-battlers, metroidvania (specific numbers), incremental (beyond "Idler" tag).

---

## 2. Over- vs under-supplied genres (revenue per release, hit rates, "opportunity")

### Takeaway
Using Chris Zukowski's (HTMAG) "% of releases reaching 1,000 Steam reviews (~$150k gross)" metric on VG Insights data, the most under-supplied genres in 2024-2025 were Open World Survival Craft (~21-24%), Job Simulator (~35%), Farming (8-21%), City Builder (6.4%) and Roguelike Deckbuilder (5-7%); the most over-supplied were 2D Platformer (~0.2%), Point & Click (0.13%), Puzzle (0.36%) and Adult (~1%). Horror and Narrative produce the most absolute hits but because they have huge release volumes their rate is only near average.

### Cited Findings

**Hit rate (share of releases reaching 1,000+ Steam reviews) — HTMAG using VGInsights, snapshot Jan 4 2026 for 2025 data** — [How To Market A Game, "What the hell happened in 2025?" (Jan 2026)](https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/); [HTMAG, "What the hell happened in 2024?" (Jan 2025)](https://howtomarketagame.com/2025/01/15/what-the-hell-happened-in-2024/); additional rows and release counts from [PokeIndie "Game Genre Study 2026" (secondary compilation of HTMAG data)](https://pokeindie.com/blog/game-genre-study-2026-which-genres-are-worth-building)

| Genre tag | 2025 releases | 2025 hits (1k+ reviews) | 2025 hit rate | 2024 hit rate |
|---|---|---|---|---|
| Job Simulator | n/a | n/a | 34.7% (PokeIndie) | n/a |
| Open World Survival Craft | 72 | 15 | 20.8% | 24.47% |
| Farming Sim | 60 | 5 | 8.3% | 20.83% |
| City Builder | n/a | n/a | 6.4% (PokeIndie) | n/a |
| Roguelike Deckbuilder | 212 | 11 | 5.1% | 6.71% |
| Simulation (all) | 1,048 | 43 | 4.1% | ~3.8% |
| Metroidvania | n/a | n/a | 4.0% (PokeIndie) | n/a |
| Management | 549 | 19 | 3.4% | ~5.4% |
| Horror | 1,208 | 39 | 3.2% | ~1.8% |
| ALL STEAM | 20,282 | 608 | 2.99% | 2.44% |
| Idle/Incremental | 965 | 27 | 2.79% | ~3.1% |
| Tower Defense | n/a | n/a | 2.6% (PokeIndie) | n/a |
| RPG | 1,158 | 28 | 2.4% | ~1.5% |
| Puzzle Platformer | n/a | n/a | 1.5% | n/a |
| 3D Platformer | n/a | n/a | 1.5% | n/a |
| Sexual content/Adult | 1,846 | 21 | 1.1% | ~1.3% |
| Puzzle | n/a | n/a | n/a | 0.36% |
| 2D Platformer | n/a | n/a | 0.18% (HTMAG) / 0.25% (PokeIndie, 2024) | 0.25% |
| Point & Click | n/a | n/a | n/a | 0.13% |

- 1,000 reviews ~ $150,000 gross (~$105k after Valve cut, before tax) — [HTMAG 2025 review via PokeIndie](https://pokeindie.com/blog/game-genre-study-2026-which-genres-are-worth-building); [HTMAG 2026](https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/)
- PokeIndie caveat: figures "accurate to roughly half a point." Minor discrepancy on 2D platformer (0.18% HTMAG 2025 vs 0.25% PokeIndie citing 2024).

**Absolute hit counts by genre (1,000+ reviews)**

| Rank | 2024 (HTMAG) | count | 2025 (HTMAG) | count |
|---|---|---|---|---|
| 1 | Horror | 47 | Narrative | 51 |
| 2 | Narrative | 30 | Simulation | 43 |
| 3 | Simulation | 27 | Horror | 39 |
| 4 | Shooter | 27 | RPG | 28 |
| 5 | Open World Survival Craft | 23 | Idle/Incremental | 27 |
| 6 | Sexual Content | 20 | Roguelike | 22 |
| 7 | Idle/Incremental | 20 | Sexual Content | 21 |
| 8 | Management | 19 | Multiplayer Shooter | 21 |
| 9 | RPG | 17 | Shooter | 21 |
| 10 | Roguelike | 16 | Management | 19 |

Sources: [HTMAG 2024](https://howtomarketagame.com/2025/01/15/what-the-hell-happened-in-2024/); [HTMAG 2025](https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/)
- 2025: Multiplayer Shooter displaced Open World Survival Craft from top 10 (though 15 survival crafts still hit 1k reviews). 19 of the 51 narrative hits were translated Chinese FMV visual novels; excluding them, narrative = 32 — [HTMAG 2025](https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/)
- 2024: 21% of hit games (51) were tagged co-op — [HTMAG 2024 via search summary](https://howtomarketagame.com/2025/01/15/what-the-hell-happened-in-2024/)
- Narrative hits: 17 (2022) -> 20 (2023) -> 30 (2024) -> 51 (2025) — HTMAG 2024 and 2025 posts above.
- Action roguelike / "bullet heaven" (Vampire Survivors-likes): 10 hits in 2022, 17 in 2023, only 1 in first half of 2024 ("the party is over") — [HTMAG via search summary (2024)](https://howtomarketagame.com/2025/01/15/what-the-hell-happened-in-2024/); but 2 Vampire-Survivor-likes hit 1k reviews in Q1 2026 alone (and Megabonk was a 2025 breakout) — [HTMAG Q1 2026](https://howtomarketagame.com/2026/05/14/2026-q1-games/)
- 2024 puzzle count inflated by one publisher ("100 Cozy Games") mass-releasing free hidden-object games — [HTMAG](https://howtomarketagame.com/2025/01/15/what-the-hell-happened-in-2024/)
- Roguelike deckbuilder supply grew only modestly vs puzzle and platformers, contrary to complaints of saturation — [PokeIndie/search summary of GameDiscoverCo commentary](https://pokeindie.com/blog/game-genre-study-2026-which-genres-are-worth-building)

**Friendslop saturation (2026)**
- 2026 year-to-date releases (by July): Idle/Clicker 1,087; RPG 785; Battle Royale 67 — [HTMAG "Is Friendslop saturated?" (Jul 2026)](https://howtomarketagame.com/2026/07/30/is-friendslop-saturated/)
- Friendslop hits rotate: a single title captures ~47-50% of the category's players for 3-9 months then fades — same source. Implication in source: the category is not saturated in demand terms (overall friendslop CCU keeps rising) but is winner-take-most.

### Inferences
- "Revenue per release" ranking (combine medians + hit rates): top tier = Open World Survival Craft, Job Sim, 4X, Colony Sim, City Builder, Farming, Roguelike Deckbuilder, Grand Strategy; middle = Simulation/Management, Metroidvania, Horror, RPG, Idle; bottom (over-supplied) = 2D Platformer, Puzzle, Point & Click, Match-3, Adult, generic Action.
- Caution for a 2-5 engineer team: highest-rate genres (survival craft, 4X, colony sim, city builder) are also the most scope- and systems-heavy; the survival-craft hit rate may partly reflect that only well-funded teams attempt it (selection effect). Farming's hit rate dropped sharply (20.8% -> 8.3%), suggesting supply catching up.
- Horror rate improved from ~1.8% to 3.2% (driven by co-op/friendslop horror), and Horror remains #1-3 by absolute hits three years running, but the Immutable median for Horror ($2,590) is poor: high variance genre.

### Gaps
- No hit-rate data found for: extraction shooters, MOBA, MMO, sports, racing, fighting, auto-battlers, visual novels (as separate tag), incremental beyond "Idle".
- HTMAG's full per-genre table (release counts for every tag) was only partially retrieved; City Builder, Job Sim, Metroidvania, Tower Defense release counts missing.

---

## 3. Fraction of indie Steam releases under $1k / over $100k / over $1M; release volume trend

### Takeaway
About two-thirds of Steam releases gross under $1,000 lifetime-to-date, ~40% never reach $100, roughly 8% gross over $100k and ~1.5% (~300 games/yr) over $1M. Release volume has risen from ~14.5k (2023) to ~18.2-18.5k (2024) to ~20.3-21.3k (2025) and is tracking ~24-26k for 2026, while hit rates for 2026 appear to be falling.

### Cited Findings

**Revenue thresholds (2025 cohort, gross, Gamalytic-derived; measured within the release year so these are early-life figures)**
- ~65.9% of 2025 releases earned under $1,000; ~40% had not reached $100 (Steam Direct fee); only ~8% grossed more than $100,000; roughly 300 crossed $1M gross — [game-developers.org, "2025 Steam Game Revenue Distribution" (Gamalytic, Alinea)](https://game-developers.org/2025-steam-game-revenue-distribution)
- 47.5% of 2025 games sold fewer than 100 copies; 2,200 titles had zero reviews; 7,100 had under 10 reviews; 6.2% of releases had 500+ reviews — [game-developers.org, "Steam Paradox 2025"](https://game-developers.org/steam-paradox-2025-revenue-volume)
- Nearly 50% of ~20,000 2025 Steam releases have fewer than 10 reviews — [GameDiscoverCo via GameDevReports (Jan 2026)](https://gamedevreports.substack.com/p/gamediscoverco-most-successful-new)
- 608 of 20,282 (2.99%) 2025 games reached 1,000 reviews (~$150k gross); ~300 (1.5%) over $1M gross — [HTMAG 2025](https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/); [PokeIndie (2026)](https://pokeindie.com/blog/game-genre-study-2026-which-genres-are-worth-building)
- Note on consistency: 8% > $100k (Gamalytic) vs 3% >= 1,000 reviews (~$150k) (HTMAG) are consistent given the different thresholds and the review-to-sales ratio variance.

**Chart-ready threshold distribution (2025 cohort, gross)**

| Bucket | Share of 2025 releases | Source |
|---|---|---|
| < $100 | ~40% | game-developers.org (Gamalytic) |
| < $1,000 | ~66% | game-developers.org (Gamalytic) |
| > $100,000 | ~8% | game-developers.org (Gamalytic) |
| >= 1,000 reviews (~$150k) | 2.99% | HTMAG (VGI) |
| > $1,000,000 | ~1.5% (~300 games) | game-developers.org / PokeIndie |

**Release volume**

| Year | Steam releases | Source |
|---|---|---|
| 2023 | ~14,000 (HTMAG implied: 2024's 18,234 was +31% YoY) | [HTMAG 2024](https://howtomarketagame.com/2025/01/15/what-the-hell-happened-in-2024/) |
| 2024 | 18,234 (HTMAG/VGI); 18,478 (SteamDB-type count) | [HTMAG 2024](https://howtomarketagame.com/2025/01/15/what-the-hell-happened-in-2024/); [search summary citing SteamDB/Statista](https://steamdb.info/stats/releases/) |
| 2025 | 20,282 (HTMAG/VGI); 21,344 (SteamDB-type count); 20,853 (HTMAG projection used in 2026 post) | [HTMAG 2025](https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/); [SteamDB](https://steamdb.info/stats/releases/) |
| 2026 | Q1: 5,971; full-year estimate 25,799 (+23.7%); 16,115 by Aug 20 (~69.5/day) | [HTMAG Q1 2026](https://howtomarketagame.com/2026/05/14/2026-q1-games/); [Notebookcheck (Aug 2026)](https://www.notebookcheck.net/Steam-averages-almost-70-new-games-a-day-in-2026.1374113.0.html) |

- Counts differ by source because of what's counted (e.g., SteamDB includes more app types). Use one source consistently in charts.
- Hit rate trend: 2.74% (2022) -> 2.56% (2023) -> 2.44% (2024) -> 2.99% (2025) -> 1.6% of Q1 2026 releases had 1,000+ reviews (early snapshot, will rise with time) — [HTMAG 2024](https://howtomarketagame.com/2025/01/15/what-the-hell-happened-in-2024/), [HTMAG 2025](https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/), [HTMAG Q1 2026](https://howtomarketagame.com/2026/05/14/2026-q1-games/)
- 2024: absolute hits +25% vs 2023 but releases +31% — [HTMAG 2024](https://howtomarketagame.com/2025/01/15/what-the-hell-happened-in-2024/)
- Q1 2026 review distribution: 0-9 reviews 63.2% (3,686); 10-50 23.4%; 51-100 5.4%; 101-399 6.6%; 400-999 2.1%; 1000+ 1.6% (96 games). Ratio of 0-9-review games to 1000+ games: 26:1 in 2024 vs 38:1 in 2026 — [HTMAG Q1 2026](https://howtomarketagame.com/2026/05/14/2026-q1-games/)

**Console release volume 2025 (GameDiscoverCo)** — [GameDevReports summary of GameDiscoverCo (Jan 2026)](https://gamedevreports.substack.com/p/gamediscoverco-most-successful-new)
- Nintendo Switch: 3,100+ games (+8% YoY); PlayStation: 1,300+ (+4%); Xbox: ~900 (-20% YoY).

**VG Insights indie segmentation (2024)** — [search summary of VGI Global Indie Games Market Report 2024](https://app.sensortower.com/vgi/assets/reports/VGI_Global_Indie_Games_Market_Report_2024.pdf) (secondary summary; PDF could not be parsed directly)
- "Hobbyists" (1-2 people): 2-20k copies, ~$50k revenue; "Small teams" (3-15 people): 20-200k copies, ~$1M revenue; "Middle market" (15-50): 200k-1M copies, ~$10M; "Triple-i" (50+): 1M+ copies, ~$50M. Triple-i captured 53% of indie revenue in 2024 — [PokeIndie citing VGI 2024](https://pokeindie.com/blog/game-genre-study-2026-which-genres-are-worth-building)
- VGI 2024: indie = 48% of Steam full-game revenue, ~$4B, 295M units (+~20%) — [80.lv (2024)](https://80.lv/articles/indie-games-market-reached-unprecedented-success-in-2024). Conflicts with Alinea's 25% for 2025 due to indie definition (VGI included Black Myth: Wukong, Palworld).

### Inferences
- A 2-5 person team (VGI "small team" segment) should treat ~$150k gross as a "hit" that ~3% of releases reach; the tail of shovelware drags medians so low that the relevant benchmark is "median of polished commercial releases" (likely low five figures), not the $249 all-release median.
- Supply is growing 10-25%/yr while the number of hits grows more slowly; 2026 looks tougher than 2025 on early data.

### Gaps
- No clean dataset for thresholds among "serious" indie releases only (e.g., excluding games under $5 or with < 10 reviews).
- Threshold shares for 2023 and 2024 cohorts (under $1k / over $100k) were not retrieved for trend comparison.

---

## 4. Price points by genre; F2P vs premium for indies

### Takeaway
Most successful indie titles price at $14.99-$19.99; median launch price of top new releases fell from ~$19.50 (early 2023) to ~$15.64, driven by cheap ($5-10) viral co-op/friendslop hits. Premium dominates Steam revenue (78% in 2025) and no new F2P launch would have made the 2025 top 20; F2P is a poor default for 2-5 person teams. Solid per-genre average-price data was not found.

### Cited Findings
- Among the top 1,000 games: $19.99 most common (147 titles), $14.99 second (124). Short/viral co-op effective range $7.99-$9.99 — [PokeIndie Game Genre Study 2026](https://pokeindie.com/blog/game-genre-study-2026-which-genres-are-worth-building)
- Median launch price of top new releases fell from ~$19.50 to $15.64 over three years, driven by viral co-op games rather than across-the-board discounting — [PokeIndie (2026)](https://pokeindie.com/blog/game-genre-study-2026-which-genres-are-worth-building); similar claim of $14-16 range, $9.99 most common indie price — [SteamPageAnalyzer pricing blog (2026, aggregator)](https://www.steampageanalyzer.com/blog/steam-pricing-strategy)
- Example 2025 hit prices: PEAK $7.99, Schedule I ~$20 — [SteamPageAnalyzer (2026)](https://www.steampageanalyzer.com/blog/indie-game-revenue-data)
- Premium games = 78% of Steam 2025 revenue, F2P = 22% (Alinea Analytics; excludes F2P games using their own launchers); 74% of developers working on premium vs 26% on F2P — [search summary of games.gg / Alinea (2025)](https://games.gg/news/indie-games-on-steam-make-4-billion/) (secondary; not fetched directly)
- "None of the new F2P games would have made the top 20 [by Steam revenue] in 2025"; closest were Umamusume: Pretty Derby and Where Winds Meet — [GameDiscoverCo via GameDevReports (Jan 2026)](https://gamedevreports.substack.com/p/gamediscoverco-most-successful-new)
- Battle Royale was excluded from Immutable's median table because F2P leaders skew it — [Immutable (2026)](https://www.immutable.com/insights/steam-genre-revenue-benchmarks)
- Wishlist math example: 7,000 wishlists x 12% day-one conversion x $14.99 = ~$12,600 gross — [PokeIndie (2026)](https://pokeindie.com/blog/game-genre-study-2026-which-genres-are-worth-building)
- Implied average price per copy from Immutable medians (gross revenue / copies; rough, includes discounts): OWSC ~$14; 4X ~$12.8; JRPG ~$14.1; Colony Sim ~$7.6; RTS ~$12; Grand Strategy ~$9.5; Visual Novel ~$9; RPG ~$10; Farming ~$8; Souls-like ~$8.1; Horror ~$3; Action ~$5; Puzzle ~$5; 2D Platformer ~$5; Idler ~$5; Match 3 ~$6.1 — derived from [Immutable (2026)](https://www.immutable.com/insights/steam-genre-revenue-benchmarks) (my calculation; average realized price per unit at median, not list price)

### Inferences
- Realized price per unit is roughly 2-3x higher in strategy/RPG/survival-craft tags than in horror/action/puzzle/platformer tags, compounding the unit-sales gap.
- For small teams, premium at $9.99-$19.99 is the evidence-backed default; sub-$10 works mainly for viral co-op games that rely on "buy for your friends" word-of-mouth.

### Gaps
- No reliable source found for list-price averages by genre on Steam (AppMagic "Steam Pricing Research" page did not render).
- No quantitative data found on indie F2P median outcomes on Steam (vs premium medians).

---

## 5. Genre trend direction 2024-2026; brief console/mobile context

### Takeaway
Rising: co-op/friendslop (incl. co-op horror), narrative/visual novels (incl. Chinese FMV), idle/incremental (in hit counts, but supply is exploding), multiplayer shooters/extraction, deckbuilders (rebound in 2026), bullet-heaven revival (Megabonk). Stable/strong but tightening: Open World Survival Craft, farming, management. Declining/saturated: 2D platformer, puzzle, point & click, adult content share, VR. Genre rankings are "quite stable" year to year per Zukowski.

### Cited Findings
- "The genres aren't moving. They are quite stable" — 9 of top 10 hit genres unchanged 2024->2025; Horror #1 three consecutive years through 2024 — [HTMAG 2024](https://howtomarketagame.com/2025/01/15/what-the-hell-happened-in-2024/); [HTMAG 2025](https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/)
- Friendslop was a defining 2025 trend: R.E.P.O., PEAK, Schedule I, RV There Yet?, Mage Arena in GameDiscoverCo's top 20; top-20 all >2M copies, top 7 >5M (vs only 4 >5M a year earlier) — [GameDiscoverCo via GameDevReports (Jan 2026)](https://gamedevreports.substack.com/p/gamediscoverco-most-successful-new); [Kotaku (2025)](https://kotaku.com/steam-top-selling-2025-friendslop-rpgs-sales-2000654157)
- Friendslop CCU keeps rising (197k Lethal Company 2023 -> 281k R.E.P.O. 2025 -> 350k category peak 2026) but individual titles fade in 3-9 months — [HTMAG Jul 2026](https://howtomarketagame.com/2026/07/30/is-friendslop-saturated/)
- Q1 2026 1,000+-review hits: Adventure ~5, Idle 4, Deckbuilders 3, Horror 3, Friendslop 3, Vampire-Survivor-likes 2; vs Q1 2025: Horror 7->3, Idle 5->4, Deckbuilders 1->3; puzzle declined sharply; zero VR and no 2D platformers among hits — [HTMAG Q1 2026](https://howtomarketagame.com/2026/05/14/2026-q1-games/)
- Horror hit rate rose ~1.8% (2024) -> 3.2% (2025); RPG 1.5% -> 2.4%; Farming fell 20.8% -> 8.3%; OWSC 24.5% -> 20.8%; Management 5.4% -> 3.4%; Roguelike deckbuilder 6.7% -> 5.1% — [PokeIndie compiling HTMAG (2026)](https://pokeindie.com/blog/game-genre-study-2026-which-genres-are-worth-building)
- Adult content: 1,846 releases in 2025 (9.1% of total), share lower than prior three years — [HTMAG 2025](https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/)
- Idle/Clicker: 1,087 releases in 2026 by July (vs 965 in all of 2025) — supply surging — [HTMAG Jul 2026](https://howtomarketagame.com/2026/07/30/is-friendslop-saturated/); [PokeIndie](https://pokeindie.com/blog/game-genre-study-2026-which-genres-are-worth-building)
- Large action RPGs strong on Steam in 2025 (Monster Hunter Wilds, Elden Ring Nightreign, KCD2, Oblivion Remastered) — AAA space, not indie-relevant — [GameDiscoverCo via GameDevReports](https://gamedevreports.substack.com/p/gamediscoverco-most-successful-new)

**Console / mobile (brief)**
- Newzoo 2025 forecast: global market $197B (+7.5%); PC $43B (+10.4%, fastest-growing); console $45B (+4.2%); mobile $108B (+7.7%) — [Outlook Respawn reporting Newzoo (2025)](https://respawn.outlookindia.com/gaming/gaming-news/newzoo-raises-global-games-market-2025-forecast-to-197-billion). PokeIndie cites Newzoo PC 2025 = $39.9B and global ~$205B for 2026 — [PokeIndie](https://pokeindie.com/blog/game-genre-study-2026-which-genres-are-worth-building) (conflicting PC figure; Newzoo revised forecasts mid-year).
- Console top-seller thresholds 2025: PlayStation top 20 all 1M+ copies; Xbox top 20 floor ~300k; Switch bottom third of top list ~250k. PlayStation top 20 includes 6 sports titles; Switch audience differs markedly — [GameDiscoverCo via GameDevReports](https://gamedevreports.substack.com/p/gamediscoverco-most-successful-new)
- Console storefronts are far less crowded than Steam (Switch 3,100+, PS 1,300+, Xbox ~900 releases in 2025 vs ~20k on Steam) — same source.

### Inferences
- For a new 2-5 engineer studio, the durable "above average median + above average hit rate" genres are systemic PC genres (colony sim, city builder, 4X-lite, management/job sim, roguelike deckbuilder, survival-craft if scope allows). Friendslop has the highest ceiling for cheap scope but is a hit-driven lottery with 3-9 month title lifecycles.
- Idle/incremental: low median ($2,870 Immutable), decent hit count, but release volume up sharply in 2026 — likely deteriorating.
- Console ports are best treated as a secondary revenue channel for already-proven Steam games; Switch is the most crowded console store.

### Gaps
- No reliable quantitative 2024-2026 trend data found for MOBA, MMO, fighting, racing, sports, auto-battlers or extraction shooters at indie scale (extraction has one indie mega-hit, Escape from Duckov $53M, but no cohort data).
- Mobile genre-level indie outcomes not researched in depth (Newzoo top-line only); premium mobile indie data not found.
- GDC State of the Industry 2025/2026 genre findings were not retrieved.
