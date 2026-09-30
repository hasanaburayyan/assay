# Engineers should build systems, not servers

For a 2-5 person studio of strong engineers with weak art, the best return on difficulty comes from **systems-driven PC genres: automation/factory, colony and management sims, roguelike deckbuilders, survivors-likes, and small co-op games on relay networking**. These genres combine above-average Steam medians and hit rates with art demands that programmer-made or asset-store visuals can meet. Solo engineers built many of the biggest hits of 2022-2026 in them, including Balatro, Vampire Survivors, Brotato, Schedule I and Lethal Company. Traditional MOBAs and MMOs are the worst fit on every axis that matters. Since 2014, every well-funded Western MOBA has died or gone into maintenance mode, including efforts by EA, Epic, Blizzard, NCSoft, a $19M-funded 40-person studio and a heavily funded ex-Riot team. The 2024-2026 MMO launches from Amazon, Intrepid and Mainframe collapsed or shrank despite teams of 43-123+. The stakes are high because the Steam market is brutal on average. **Two-thirds of 2025 releases grossed under $1,000**, releases are rising about 20% a year, and only about 3% of games reach the roughly $150k gross that marks a small-team hit. Genre choice is the biggest lever r2ts controls. The recommended path is a premium ($15-20) systems game with a constrained, engineer-executable art style as the flagship, plus optional jam-scale co-op side bets. The MOBA/MMO appeal can live on inside that plan in scoped forms that work with ten players online or none: hero-draft co-op roguelites, async-PvP auto-battlers, idle MMOs, and player-hosted co-op worlds. Every table below is structured so it can be charted directly.

## Two-thirds of Steam games gross under $1,000 while supply climbs 20% a year

The baseline sets the stakes for every genre decision. **The median game released on Steam in 2025 grossed $249**, and the 2024 cohort median was $222, the lowest of 2020-2025 ([game-developers.org, Gamalytic data](https://game-developers.org/steam-paradox-2025-revenue-volume)). The mean was $358,900, because hits dominate the distribution: **the top 1% of Steam games earn 84.5% of estimated revenue** ([GamesRadar+](https://www.gamesradar.com/games/behold-the-whole-history-of-steams-economy-in-one-picture-the-top-1-percent-of-games-earn-84-5-percent-of-estimated-revenue-and-most-games-barely-make-anything/)). All of these figures are third-party gross estimates. After Valve's cut, VAT, refunds and regional pricing, net to the developer is roughly **35-57% of gross** ([Immutable](https://www.immutable.com/insights/steam-genre-revenue-benchmarks)).

**Chart: 2025 Steam cohort revenue distribution (gross, first-year estimates)**

| Bucket | Share of 2025 releases | Source |
|---|---|---|
| Under $100 (never recouped the Steam Direct fee) | ~40% | [game-developers.org](https://game-developers.org/2025-steam-game-revenue-distribution) |
| Under $1,000 | ~66% | [game-developers.org](https://game-developers.org/2025-steam-game-revenue-distribution) |
| Over $100,000 | ~8% | [game-developers.org](https://game-developers.org/2025-steam-game-revenue-distribution) |
| 1,000+ reviews (~$150k gross, ~$105k after Valve) | 2.99% (608 of 20,282) | [How To Market A Game](https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/) |
| Over $1,000,000 | ~1.5% (~300 games) | [game-developers.org](https://game-developers.org/2025-steam-game-revenue-distribution) |

Much of the bottom of this distribution is hobby and shovelware releases. **47.5% of 2025 games sold fewer than 100 copies, and 2,200 had zero reviews** ([game-developers.org](https://game-developers.org/steam-paradox-2025-revenue-volume)). For a studio of salaried professionals, the $249 median matters less than the hit threshold. Chris Zukowski's benchmark of 1,000 reviews (about $150k gross) is a sensible "we survived" line, and the table shows that **about 1 release in 33** gets there. The competitive field is also growing faster than the pool of hits.

**Chart: Steam release volume and hit rate**

| Year | Steam releases | Share reaching 1,000+ reviews |
|---|---|---|
| 2022 | n/a | 2.74% |
| 2023 | ~14,000 | 2.56% |
| 2024 | 18,234 | 2.44% |
| 2025 | 20,282 | 2.99% |
| 2026 (est.) | 25,799 projected; 16,115 by Aug 20 | 1.6% for Q1 releases (early snapshot, will rise) |

Sources: [HTMAG 2024](https://howtomarketagame.com/2025/01/15/what-the-hell-happened-in-2024/), [HTMAG 2025](https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/), [HTMAG Q1 2026](https://howtomarketagame.com/2026/05/14/2026-q1-games/), [Notebookcheck](https://www.notebookcheck.net/Steam-averages-almost-70-new-games-a-day-in-2026.1374113.0.html). Counts differ by tracker; SteamDB counts 21,344 for 2025 ([SteamDB](https://steamdb.info/stats/releases/)), so a chart should use one source consistently.

In 2024, absolute hits grew 25% while releases grew 31% ([HTMAG 2024](https://howtomarketagame.com/2025/01/15/what-the-hell-happened-in-2024/)). In Q1 2026, the ratio of games with 0-9 reviews to games with 1,000+ reviews widened from 26:1 in 2024 to **38:1** ([HTMAG Q1 2026](https://howtomarketagame.com/2026/05/14/2026-q1-games/)). The market is not shrinking: Steam games grossed $17.7B in 2025 ([Game World Observer](https://gameworldobserver.com/2025/12/22/indie-projects-generated-a-quarter-of-the-total-game-revenue-on-steam-by-the-end-of-2025-analytics)), and Newzoo forecast PC as the fastest-growing platform at +10.4% ([Outlook Respawn](https://respawn.outlookindia.com/gaming/gaming-news/newzoo-raises-global-games-market-2025-forecast-to-197-billion)). But attention is getting more concentrated, which raises the cost of choosing a genre with weak structural odds.

## Strategy and survival-craft medians run 5-40x higher than action and platformers

The median by genre varies by more than an order of magnitude, and those gaps have held steady over time. Immutable's September 2026 benchmark covers every game ever released under each Steam tag (lifetime, gross). It puts **Open World Survival Craft at $102,000 and 4X at $50,000, against $2,530 for Action and $1,040 for 2D Platformer** ([Immutable](https://www.immutable.com/insights/steam-genre-revenue-benchmarks)). Across all 107 tags the median is $4,837, and only 26 tags clear $10,000.

**Chart: lifetime median gross revenue by Steam tag (Immutable, Sept 2026)**

| Tag | Median gross | Median copies | Implied realized price/unit |
|---|---|---|---|
| Open World Survival Craft | $102,000 | 7,290 | ~$14.0 |
| 4X | $50,000 | 3,900 | ~$12.8 |
| JRPG | $21,000 | 1,490 | ~$14.1 |
| Colony Sim | $17,300 | 2,280 | ~$7.6 |
| RTS | $16,700 | 1,390 | ~$12.0 |
| Grand Strategy | $14,700 | 1,550 | ~$9.5 |
| Dating Sim | $14,400 | 1,780 | ~$8.1 |
| Visual Novel | $10,300 | 1,140 | ~$9.0 |
| RPG | $9,770 | 979 | ~$10.0 |
| Farming Sim | $8,690 | 1,080 | ~$8.0 |
| Souls-like | $8,460 | 1,040 | ~$8.1 |
| Adventure | $6,520 | 726 | ~$9.0 |
| Strategy | $4,040 | 578 | ~$7.0 |
| Idler | $2,870 | 574 | ~$5.0 |
| Horror | $2,590 | 867 | ~$3.0 |
| Action | $2,530 | 508 | ~$5.0 |
| Puzzle | $2,390 | 477 | ~$5.0 |
| Survival Horror | $2,050 | 683 | ~$3.0 |
| Match 3 | $1,830 | 298 | ~$6.1 |
| 2D Platformer | $1,040 | 209 | ~$5.0 |

Source: [Immutable](https://www.immutable.com/insights/steam-genre-revenue-benchmarks). The price-per-unit column is derived as median revenue divided by median copies. It is not a list price.

GameDiscoverCo ran a separate analysis on Games-Stats data that filters toward more serious releases and reports net figures. It ranks the genres in the same order at higher levels: **Colony Sim $44,000 net, Roguelike Deckbuilder $38,000, 4X $35,000, City Builder $22,000, Grand Strategy $19,000**, against Action RPG at $4,300 and an all-Steam baseline near $2,600 ([GameDiscoverCo](https://newsletter.gamediscover.co/p/which-genre-should-your-next-pc-game)). The two datasets disagree on levels. For colony sims, Immutable reports $17.3k gross and GameDiscoverCo reports $44k net, a gap explained by different filters and dates (the GameDiscoverCo piece is likely from 2024). They agree on the ranking, and the ranking is what matters for a genre decision. The two effects compound: strategy, RPG and survival-craft tags sell more copies *and* realize 2-3x more per copy than horror, action, puzzle and platformer tags.

Hit rates tell the same story from the top of the distribution.

**Chart: share of releases reaching 1,000+ Steam reviews (~$150k gross), by genre**

| Genre | 2025 hit rate | 2024 hit rate | 2025 releases |
|---|---|---|---|
| Job Simulator | 34.7% | n/a | n/a |
| Open World Survival Craft | 20.8% | 24.5% | 72 |
| Farming Sim | 8.3% | 20.8% | 60 |
| City Builder | 6.4% | n/a | n/a |
| Roguelike Deckbuilder | 5.1% | 6.7% | 212 |
| Simulation (all) | 4.1% | ~3.8% | 1,048 |
| Metroidvania | 4.0% | n/a | n/a |
| Management | 3.4% | ~5.4% | 549 |
| Horror | 3.2% | ~1.8% | 1,208 |
| **All Steam** | **2.99%** | **2.44%** | **20,282** |
| Idle/Incremental | 2.79% | ~3.1% | 965 |
| Tower Defense | 2.6% | n/a | n/a |
| RPG | 2.4% | ~1.5% | 1,158 |
| Puzzle Platformer / 3D Platformer | 1.5% | n/a | n/a |
| Adult | 1.1% | ~1.3% | 1,846 |
| Puzzle | n/a | 0.36% | n/a |
| 2D Platformer | 0.18% | 0.25% | n/a |
| Point & Click | n/a | 0.13% | n/a |

Sources: [HTMAG 2025](https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/), [HTMAG 2024](https://howtomarketagame.com/2025/01/15/what-the-hell-happened-in-2024/), and [PokeIndie's compilation of HTMAG/VGI data](https://pokeindie.com/blog/game-genre-study-2026-which-genres-are-worth-building), which is accurate to about half a point.

Three details affect how these numbers should be read. First, survival-craft's 21-24% hit rate is partly a **selection effect**: only well-resourced teams attempt the genre, and it is among the most content-heavy. Second, farming's rate fell from 20.8% to 8.3% in one year, which is what a genre looks like when supply catches up with demand. Third, horror is volatile. It led absolute hit counts from 2022 through 2024 ([HTMAG 2024](https://howtomarketagame.com/2025/01/15/what-the-hell-happened-in-2024/)), yet its median is only $2,590, so it produces many hits and a vast number of failures.

Zukowski's summary is that genres "aren't moving": nine of the top ten hit genres were unchanged from 2024 to 2025 ([HTMAG 2025](https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/)). A few trends are shifting at the margins. Idle/clicker supply is surging, with 1,087 releases by July 2026 against 965 in all of 2025 ([HTMAG](https://howtomarketagame.com/2026/07/30/is-friendslop-saturated/)). Deckbuilder hits rebounded in Q1 2026. VR and 2D platformers produced no hits at all in Q1 2026 ([HTMAG Q1 2026](https://howtomarketagame.com/2026/05/14/2026-q1-games/)).

The data has two important gaps. **No source publishes median revenue or hit rates for MOBAs, MMOs, extraction shooters, fighting games, automation or survivors-likes as separate tags.** The judgments below on those genres rest on case evidence rather than cohort statistics.

## Engineering-heavy, art-light genres sit in the sweet spot

Revenue potential only matters relative to what it costs this team to build. The difficulty matrix below scores each genre from 1 to 5 on engineering complexity, art and content volume, and live-ops/server burden (5 = hardest), and on tolerance for minimal, procedural, pixel or asset-store art (5 = most tolerant). The researchers derived these scores from shipped-game evidence. They are analyst judgments, not an external dataset. The composite columns are my own derivation for charting. "Difficulty" is the mean of the three burden scores, using range midpoints. "Art dependency" is 6 minus art tolerance.

**Chart: difficulty and art dependency vs. market signal (scatter-ready)**

| Genre | Eng. complexity | Art/content volume | Live-ops/server | Art tolerance | Difficulty (derived) | Art dependency (derived) | Market signal (median gross / 2025 hit rate) | Fit for r2ts |
|---|---|---|---|---|---|---|---|---|
| Incremental/idle | 1.5 | 1 | 1 | 5 | 1.2 | 1 | $2,870 / 2.8% | Strong but crowded, low price |
| Puzzle | 2 | 1.5 | 1 | 5 | 1.5 | 1 | $2,390 / 0.36% | Only with strong design talent |
| Survivors-like | 2 | 2 | 1 | 5 | 1.7 | 1 | n/a (multiple 1M+ solo hits) | Strong, saturating |
| Roguelike/roguelite | 3 | 2.5 | 1 | 4.5 | 2.2 | 1.5 | n/a | Strong |
| Roguelike deckbuilder | 2.5 | 3 | 1 | 4 | 2.2 | 2 | $38k net (GDCo) / 5.1% | Strong |
| Colony/management sim | 4 | 2.5 | 1 | 5 | 2.5 | 1 | $17.3k gross, $44k net / 3.4% (mgmt) | **Very strong** |
| Tactics/strategy (incl. 4X-lite) | 3.5 | 3 | 1 | 4 | 2.5 | 2 | 4X $50k gross / n/a | Medium-strong |
| Automation/factory | 4 | 2.5 | 1.5 | 5 | 2.7 | 1 | n/a (shapez 2 700k+ EA sales) | **Very strong** |
| City builder | 3.5 | 3.5 | 1 | 3 | 2.7 | 3 | $22k net / 6.4% | Medium |
| Co-op party / friendslop | 3 | 3 | 2 | 4 | 2.7 | 2 | Horror proxy $2,590 / 3.2% | Strong but hit-driven |
| Survival-crafting | 4 | 4 | 2.5 | 3 | 3.5 | 3 | $102k / 20.8% | Medium (scope-heavy) |
| Fighting | 5 | 5 | 3.5 | 1.5 | 4.5 | 4.5 | n/a | Poor |
| Extraction shooter (PvP) | 5 | 4.5 | 5 | 2 | 4.8 | 4 | n/a | Poor |
| MMO | 5 | 5 | 5 | 2 | 5.0 | 4 | n/a | Very poor |
| MOBA | 5 | 5 | 5 | 1 | 5.0 | 5 | n/a | Very poor |

Scores come from the evidence compiled in the research notes. Market signal comes from [Immutable](https://www.immutable.com/insights/steam-genre-revenue-benchmarks), [GameDiscoverCo](https://newsletter.gamediscover.co/p/which-genre-should-your-next-pc-game), [HTMAG](https://howtomarketagame.com/2026/01/27/what-the-hell-happened-in-2025/) and [COGconnected](https://cogconnected.com/2026/04/shapez-2-1-0-launches-on-pc-following-an-impressive-700k-early-access-sales/).

The pattern in this table is the core of the recommendation. **Automation and colony sims are the only genres that combine high engineering difficulty with low art dependency.** For r2ts, that difficulty is a moat rather than a liability. Simulation performance, AI, determinism and procedural generation are hard for art-led teams and natural for strong engineers. The genre's history bears this out. Factorio started as "a garage company" of two programmers and one artist ([Factorio](https://www.factorio.com/game/about)). Mindustry's sole developer made all its art and music ([Mindustry wiki](https://mindustry-unofficial.fandom.com/wiki/Anuken)). shapez built a franchise on abstract geometric shapes ([tobspr.io](https://tobspr.io/)). RimWorld's first version was one person's work with no outside funding ([Wikipedia](https://en.wikipedia.org/wiki/RimWorld)). The programming-automation niche has its own proof points: The Farmer Was Replaced grossed more than $4.5M ([AppMagic](https://appmagic.rocks/research/idle-steam-games-2026)).

Networking cost is where the gap between genres gets widest. Co-op for 2-8 players runs on relay or peer-to-peer services at close to zero cost. Photon Fusion is **free up to 100 CCU, $125/month at 500 CCU, $500/month at 2,000 CCU, and $0.50/CCU beyond** ([Photon](https://www.photonengine.com/fusion/pricing)). Epic Online Services provides lobbies, matchmaking, voice and the free tier of Easy Anti-Cheat at no charge ([Epic](https://www.epicgames.com/site/en-US/news/epic-online-services-launches-free-in-game-voice-and-easy-anti-cheat)). R.E.P.O. scaled on Photon PUN "from 0 to hundreds of thousands of concurrent users" ([Photon](https://blog.photonengine.com/r-e-p-o-multiplayer-success-powered-by-photon/)). Competitive PvP is a different category. A 1 vCPU MOBA with 1,000 peak CCU across six regions costs roughly **$1,968-4,614 per month in hosting alone**, according to a vendor comparison that is itself a competitor source ([Gameye](https://gameye.com/cost-comparison/)). On top of hosting come anti-cheat, matchmaking and ongoing balance work. The hosting market has also proven fragile. Hathora shut down its game-server business in May 2026 after being acquired by an AI company, which forced Stormgate to rush out an offline mode ([Game Developer](https://www.gamedeveloper.com/business/stormgate-rushing-offline-mode-after-losing-server-access-to-an-ai-company)).

Weak art is a solvable problem, provided the style is chosen deliberately. Vampire Survivors reached Early Access on **about £1,100 of assets**, largely a purchased sprite pack ([Wikipedia](https://en.wikipedia.org/wiki/Vampire_Survivors)). Lethal Company's lo-fi "retro jank" 3D was an intentional texturing technique ([Push To Talk](https://www.pushtotalk.gg/p/how-lethal-company-sold-10-million-copies)). Kenney offers 30,000+ free CC0 assets ([Kenney](https://kenney.nl/assets)). Freelance animated pixel sprites run about $20-70 per character ([2D Will Never Die](https://2dwillneverdie.com/blog/how-much-do-sprites-cost/)). The one art spend that cannot be skipped is the capsule. Zukowski advises spending on it "before a trailer, ads, in-person conventions, or a PR company" ([Game World Observer](https://gameworldobserver.com/2022/07/18/why-eye-catching-capsule-art-is-essential-for-games-marketing-and-its-youtube-coverage)). Generative AI art is not a safe shortcut. Steam requires disclosure of player-facing AI content ([PC Gamer](https://www.pcgamer.com/software/ai/steam-updates-ai-disclosure-form-to-specify-that-its-focused-on-ai-generated-content-that-is-consumed-by-players-not-efficiency-tools-used-behind-the-scenes/)), and in a late-2025 survey **85% of gamers viewed generative AI in games negatively** ([Boing Boing summarizing Quantic Foundry](https://boingboing.net/2025/12/20/survey-finds-very-negative-attitude-toward-gen-ai-in-games.html)). AI coding tools need no disclosure.

On engine choice, Unity shipped 51% of 2024 Steam releases and most of the 3D co-op hits, helped by its asset store and Photon ecosystem. Godot's share is 5% of releases but 11% among newer indies, and it suits 2D systems games like Brotato ([GameDiscoverCo](https://newsletter.gamediscover.co/p/hows-pc-game-engine-usage-changing); [GDC 2026](https://gdconf.com/article/gdc-2026-state-of-the-game-industry-reveals-impact-of-layoffs-generative-ai-and-more); [Godot](https://godotengine.org/showcase/brotato/)). Bevy is still pre-1.0 and changes its API often ([StraySpark](https://www.strayspark.studio/blog/bevy-rust-game-engine-2026-indie-guide)), so it is a poor bet for a first commercial title.

## Every funded MOBA since 2014 has died, and MMOs fare little better

The founders' interest in MOBAs deserves a direct answer: **no 2-5 person team has shipped a commercially successful traditional MOBA in the period studied, and the base rate for well-funded challengers is close to zero.** The market belongs to incumbents that are more than ten years old. In mobile alone, Honor of Kings grossed about $1.6B in 2025 against $158M for Mobile Legends and $67M for Wild Rift ([Outlook Respawn](https://respawn.outlookindia.com/gaming/gaming-news/honor-of-kings-tops-highest-grossing-mobile-games-of-2025)). The challengers' record is below.

**Chart/timeline: MOBA challengers, 2014-2026**

| Game | Backer / team | Outcome |
|---|---|---|
| Dawngate | EA / Waystone | Cancelled Nov 2014 in beta ([GameSpot](https://www.gamespot.com/articles/ea-shutting-down-its-league-of-legends-dota-2-comp/1100-6423370/)) |
| Paragon | Epic | Dropped 2018; Netmarble's Overprime revival shut Apr 2024 ([Kotaku](https://kotaku.com/paragon-overprime-shutting-down-epic-moba-netmarble-1851279821)) |
| Gigantic | Motiga / Perfect World | Servers shut Jul 2018; 2024 relaunch hit by server failures ([Wikipedia](https://en.wikipedia.org/wiki/Gigantic_(video_game)); [Massively OP](https://massivelyop.com/2024/04/10/gigantics-buy-to-play-relaunch-is-being-tripped-up-by-ongoing-server-connection-issues/)) |
| Master X Master | NCSoft | Launched 2017, later shut down ([Wikipedia](https://en.wikipedia.org/wiki/Master_X_Master)) |
| Heroes of the Storm | Blizzard | Permanent maintenance mode ([GamesRadar+](https://www.gamesradar.com/heroes-of-the-storm-is-officially-dead-as-blizzard-shifts-into-permanent-maintenance-mode/)) |
| Battlerite | Stunlock | Content ended; retention "the biggest challenge" ([Stunlock](https://blog.stunlock.com/the-future-of-battlerite/)) |
| Omega Strikers | Odyssey, 40 devs, $19M Series A | Content ended 8 months after launch; ~50% layoffs ([TechRaptor](https://techraptor.net/gaming/news/omega-strikers-will-cease-content-development-8-months-after-release-as-studio-moves-on)) |
| Smite 2 | Hi-Rez | ~2k peak CCU (Oct 2024); ~70 layoffs, other games halted ([PC Gamer](https://www.pcgamer.com/games/moba/hi-rez-will-only-be-giving-minor-updates-to-smite-and-paladins-now-its-laying-off-around-70-employees-but-dont-worry-smite-2-is-the-primary-focus-of-the-newly-streamlined-operations/)) |
| Supervive | Theorycraft (ex-Riot/Bungie) | 47.9k test peak, ~100 players by late 2025; shut Feb 2026, 5 months after 1.0 ([KitGuru](https://www.kitguru.net/gaming/joao-silva/theorycraft-games-shutting-down-supervive-just-five-months-after-1-0-launch/)) |
| Deadlock | Valve | Only newcomer with traction: 171k peak, ~64k mid-2026, with Valve's distribution ([Notebookcheck](https://www.notebookcheck.net/Invite-only-Valve-shooter-Deadlock-hits-125-000-concurrent-players-after-Old-Gods-New-Blood-update.1235444.0.html)) |

These failures are not about art or code quality. The underlying mechanism is **player liquidity**. A team PvP game needs enough concurrent players in every region and skill band to fill fair matches quickly. When CCU falls, queues lengthen and match quality drops, which drives more players away. Stunlock reported "diminishing returns on gameplay changes and marketing campaigns," and Odyssey cited "high player turnover and an inability to grow" ([Stunlock](https://blog.stunlock.com/the-future-of-battlerite/); [TechRaptor](https://techraptor.net/gaming/news/omega-strikers-will-cease-content-development-8-months-after-release-as-studio-moves-on)). Changing the format to 3v3 "MOBA-lite" play (Omega Strikers, Battlerite, Supervive) did not help, because the game still needed strangers online at the same time. Games with 1-2k CCU and full-size teams behind them were fragile, so the few hundred CCU a small studio could realistically draw would mean near-certain death. No source publishes a minimum CCU threshold, so that last point is an inference from the collapse data. Engineering skill does not change the verdict. **A traditional MOBA is the single worst genre choice available to r2ts.**

MMOs are slightly less bleak but still wrong as a first project. The durable winners are old and low-fidelity. Old School RuneScape set a record of about 240,756 CCU in August 2025 ([TheGamer](https://www.thegamer.com/old-schoolrunescape-concurrent-player-count-high-record-240000-august-2025/)). Tibia, launched in 1997, earned **€14.5M net profit on €24.5M turnover in 2023** ([MMOBomb](https://www.mmobomb.com/news/tibia-oldest-active-mmo-reported-profits-of-14-5-million-euros-last-year)). Albion Online booked 389 MSEK in 2025 ([Stillfront](https://www.stillfront.com/en/wp-content/uploads/sites/2/2021/10/stillfront-annual-report-2025-260422.pdf)). That evidence shows demand for the fantasy, and it shows that art fidelity is not the barrier. But each of those games reached success with around 100 staff over 10-25 years.

Recent entrants collapsed regardless of budget. New World's servers close in January 2027 ([PC Gamer](https://www.pcgamer.com/games/mmo/new-world-is-dead-amazon-ends-new-content-updates-following-massive-layoffs-says-servers-will-be-live-through-2026/)). Throne and Liberty lost about 95% of its Steam CCU ([MMOBomb](https://www.mmobomb.com/how-heck-did-throne-liberty-lose-95-of-players)). Ashes of Creation's studio closed about seven weeks after early access, with WARN notices covering 123 people ([Game Informer](https://gameinformer.com/2026/02/02/report-ashes-of-creation-developer-intrepid-studios-shuts-down-weeks-after-the-mmos)). Pax Dei's studio cut from about 60 to 43 staff and said that building an MMO with 60 people was already hard ([Massively OP](https://massivelyop.com/2025/05/06/pax-dei-studio-lays-off-nearly-30-of-its-team-but-says-the-mmorpg-is-still-on-track/)).

Small-team MMOs follow a consistent spike-then-collapse curve. RuneScape co-creator Andrew Gower's Brighter Shores went from 17-20k CCU to about 250, a **97% decline** within a year ([MMOBomb](https://www.mmobomb.com/from-launch-to-life-support-brighter-shores-lost-97-of-players)). Solo-built Dreadmyst drew 6k+ CCU and was pulled within about seven weeks ([Massively OP](https://massivelyop.com/2026/02/27/dreadmysts-solo-dev-apparently-halted-work-on-the-mmorpg-and-yanked-it-off-steam-again/)). The husband-and-wife team behind Project Gorgon ran out of money in 2023 and dropped to part-time work ([Massively OP](https://massivelyop.com/2023/11/11/were-out-of-money-project-gorgon-moves-to-part-time-development-to-keep-its-server-lights-on/)). Server bills do not kill these games. The content treadmill, community load and runway do. Chronicles of Elyria shows the extra danger of pre-selling an MMO: it raised nearly $8M, laid off all staff in 2020, and then faced a backer lawsuit ([Wikipedia](https://en.wikipedia.org/wiki/Chronicles_of_Elyria)).

The one clear small-team MMO success, solo-developed Legends of IdleOn, is the exception that shows the way forward. Its two apps each have 1M+ installs ([AppBrain](https://www.appbrain.com/dev/LavaFlame2/)). It removed every expensive part of an MMO: real-time combat netcode, a dense shared world, and concurrency. What remained was an idle game with MMO-style social features. Its revenue figures are only low-quality estimates, so treat the scale of its success as uncertain.

## Tiny teams win when the game works with ten players online or none

The case studies show the same split that the genre data does. **Every small-team hit below stays fun alone or with a few friends, and every failure needed thousands of strangers online at once.** Team size has almost no predictive power on its own. Solo developers sit at both ends of the outcome range, and 40-123-person teams sit at the bottom.

**Chart: team size at launch vs. outcome (scatter-ready)**

| Game | Team at launch | Dev time | Price | Outcome | Genre / net model |
|---|---|---|---|---|---|
| Schedule I | 1 | ~3 yrs | $19.99 | ~8.9M units, ~$151-153M gross [EST] ([Gamalytic](https://gamalytic.com/game/3164500)) | Co-op management sim / P2P |
| Lethal Company | 1 | >6 months planned, ran long | ~$10 | ~10M units, ~$113.9M [EST] ([Game Developer](https://www.gamedeveloper.com/business/lethal-company-sold-an-estimated-10-million-copies)) | Co-op horror / relay |
| Brotato | 1 | n/a | ~$5 | 10M+ units ([Wikipedia](https://en.wikipedia.org/wiki/Brotato)) | Survivors-like / single-player |
| Buckshot Roulette | 1 | ~2 months | $2.99 | 8M+ units ([TechRaptor](https://techraptor.net/gaming/news/buckshot-roulette-sales-8m)) | Gambling horror / single-player |
| Vampire Survivors | 1 | ~1 yr to EA | $3-5 | ~6.5M units, ~$26.1M [EST] ([Raijin](https://raijin.gg/app/1794680/Vampire_Survivors)) | Survivors-like / single-player |
| Balatro | 1 | ~2 yrs 2 mo | $14.99 | 5M+ units ([Playstack](https://www.playstack.com/news/balatro-5-million-copies-sold/)) | Roguelike deckbuilder |
| Megabonk | 1 | n/a | $9.99 | 1M in 2 weeks ([Game Developer](https://www.gamedeveloper.com/business/indie-hit-megabonk-moves-over-a-million-copies-in-two-weeks)) | 3D survivors-like |
| Animal Well | 1 | ~7 yrs | n/a | ~650k units ([Wikipedia](https://en.wikipedia.org/wiki/Animal_Well)) | Art-heavy metroidvania |
| Dreadmyst | 1 | n/a | Free | 6k CCU, pulled in ~7 weeks ([Massively OP](https://massivelyop.com/2026/02/27/dreadmysts-solo-dev-apparently-halted-work-on-the-mmorpg-and-yanked-it-off-steam-again/)) | MMO |
| Dome Keeper | 2 | ~14 months | n/a | $1M+ launch week ([HTMAG](https://howtomarketagame.com/2022/10/17/how-dome-keeper-achieved-a-million-dollar-launch/)) | Mining roguelite |
| Super Auto Pets | 2 | n/a | F2P | 1M+ Google Play installs ([Wikipedia](https://en.wikipedia.org/wiki/Super_Auto_Pets)) | Async-PvP auto-battler |
| Project Gorgon | ~3 | 8 yrs in EA | n/a | ~$2.2M lifetime [EST]; ran out of money ([Massively OP](https://massivelyop.com/2023/11/11/were-out-of-money-project-gorgon-moves-to-part-time-development-to-keep-its-server-lights-on/)) | MMO |
| Hollow Knight: Silksong | 3 core | ~7 yrs | $19.99 | 7M+ in 3 months ([PC Gamer](https://www.pcgamer.com/games/action/silksong-has-sold-more-than-7-million-copies-in-3-months-and-no-thats-not-counting-game-pass/)) | Art-heavy sequel with a huge fanbase |
| Valheim | 5 | n/a | Premium | 12M+ units ([GameDev Reports](https://gamedevreports.substack.com/p/valheim-sales-have-exceeded-12m-copies)) | Co-op survival / player-hosted |
| Against the Storm | 6 founders | ~1 yr EA to 1.0 | n/a | 2M units ([Worthplaying](https://worthplaying.com/article/2026/8/12/news/150690-against-the-storm-surpasses-2-million-copies-sold-across-all-platforms/)) | Roguelite city builder |
| R.E.P.O. | ~6-10 (unconfirmed) | n/a | $8 | ~18.4M units, ~$147M in 2025 [EST] ([IndieGames.eu](https://www.indie-games.eu/gamediscoverco-reveals-2025s-best-selling-games-across-all-platforms/)) | Co-op horror / Photon |
| PEAK | 7 | ~4 weeks + polish | $7.99 | 10M+ units on <$200k budget ([Game Developer](https://www.gamedeveloper.com/production/how-co-op-climbing-hit-peak-achieved-2-million-sales-for-less-than-200-000-); [TweakTown](https://www.tweaktown.com/news/107179/peak-confirmed-to-have-sold-more-than-10-million-copies/index.html)) | Co-op climbing / relay |
| Omega Strikers | 40 | n/a | F2P | Content ended after 8 months ([TechRaptor](https://techraptor.net/gaming/news/omega-strikers-will-cease-content-development-8-months-after-release-as-studio-moves-on)) | MOBA-lite PvP |
| Pax Dei | ~60, cut to 43 | n/a | Premium | ~1.2k Steam players at snapshot ([SteamPlayerStats](https://www.steamplayerstats.com/games/pax-dei/1995520)) | MMO |
| Albion Online | Small in 2012, now 100-120+ | ~5 yrs to launch | F2P | 389 MSEK in 2025; sold for €100M+ ([Stillfront](https://www.stillfront.com/en/wp-content/uploads/sites/2/2021/10/stillfront-annual-report-2025-260422.pdf)) | MMO |
| Ashes of Creation | 123 (WARN) | Years | Pre-sold | Studio closed ~7 weeks after EA ([Game Informer](https://gameinformer.com/2026/02/02/report-ashes-of-creation-developer-intrepid-studios-shuts-down-weeks-after-the-mmos)) | MMO |

Figures marked [EST] are third-party estimates that often differ by 2x. The catalog has severe survivorship bias: it samples hits, and nobody publishes the thousands of small-team failures in the same genres.

Three lessons for r2ts come out of this table. First, **fast bets beat epics on return per dev-month.** PEAK took about four weeks, Buckshot Roulette about two months, and Supermarket Simulator about four months of initial development ([Game World Observer](https://gameworldobserver.com/2024/03/05/supermarket-simulator-viral-success-40k-ccu-turkish-devs)). semiwork built R.E.P.O. to "fail quickly" after its six-year debut flopped ([PC Gamer](https://www.pcgamer.com/games/horror/lets-just-fail-quickly-this-time-semiwork-took-a-big-risk-on-repo-after-its-first-game-took-6-years-to-make-and-didnt-sell-very-well/)).

Second, **overnight hits are usually the Nth attempt.** Lethal Company was Zeekerss's roughly 20th game ([Push To Talk](https://www.pushtotalk.gg/p/how-lethal-company-sold-10-million-copies)). Bippinbits had shipped 14 itch.io games before Dome Keeper ([HTMAG](https://howtomarketagame.com/2022/10/17/how-dome-keeper-achieved-a-million-dollar-launch/)).

Third, **the long, art-heavy successes are not a template for r2ts.** Animal Well, Silksong and Blue Prince succeeded on craft or an existing fanbase, which engineers without an artist cannot copy.

Friendslop needs one caveat. Aggregate demand keeps rising, from 197k to 281k to 350k peak CCU across 2023-2026. But each leading title captures about half the category and then fades within **3-9 months** ([HTMAG](https://howtomarketagame.com/2026/07/30/is-friendslop-saturated/)). It works as a lottery ticket that is cheap to buy if kept small, not as a business plan.

## Recommendation: build a systems game first, and fold the MOBA/MMO fantasy into it

**The primary recommendation is a premium, single-player-first systems game in automation, colony/management sim, or roguelike deckbuilder, priced at $14.99-19.99.** These genres rank high on median and hit rate and low on art dependency. They reward engineering depth, and they sustain the higher price point: $19.99 and $14.99 are the most common prices among the top 1,000 games ([PokeIndie](https://pokeindie.com/blog/game-genre-study-2026-which-genres-are-worth-building)). Premium also fits the market. Premium games took 78% of Steam revenue in 2025 ([games.gg summarizing Alinea](https://games.gg/news/indie-games-on-steam-make-4-billion/)), and no new F2P launch would have made the 2025 top 20 ([GameDiscoverCo via GameDev Reports](https://gamedevreports.substack.com/p/gamediscoverco-most-successful-new)).

The go-to-market model should be the classic wishlist funnel, which is more controllable for a studio with no audience. Zukowski recommends **7,000-10,000 wishlists minimum at launch** ([HTMAG](https://howtomarketagame.com/2022/09/26/how-many-wishlists-should-i-have-when-i-launch-my-game/)). Median wishlist conversion is 0.15x, falling to 0.10x above $10 ([GameDev Reports](https://gamedevreports.substack.com/p/gamediscoverco-the-state-of-steam)). A median Next Fest gains only 806 wishlists, and demos released months before the fest earn about 2.5x more ([Ziva summarizing HTMAG](https://ziva.sh/blogs/steam-next-fest-2026)). Dome Keeper is the template for a demo-led launch: about 1k wishlists before its demo, 40k in the demo's first month, and 189k by launch ([HTMAG](https://howtomarketagame.com/2022/10/17/how-dome-keeper-achieved-a-million-dollar-launch/)). As an unsourced planning estimate, 2-5 salaried engineers over two years cost roughly $300k-$1M+. At a $15 price and 0.10-0.15x conversion, breaking even takes on the order of 100k+ wishlists or strong post-launch discovery. That math favors genres whose medians sit in five figures.

**The secondary track is optional jam-scale co-op bets.** A 1-4 month friendslop prototype on Photon or Steam relay networking, built around proximity voice and a one-sentence streamable premise, costs little and doubles as a netcode learning project. PEAK's under-$200k budget and 29x wishlist conversion show how high the ceiling is ([Game Developer](https://www.gamedeveloper.com/production/how-co-op-climbing-hit-peak-achieved-2-million-sales-for-less-than-200-000-); [GameDev Reports](https://gamedevreports.substack.com/p/gamediscoverco-the-state-of-steam)). The 3-9 month dominance window means this track should never be the whole plan.

The founders' MOBA and MMO interests can survive the pivot. Each of those genres appeals through a specific fantasy, and each fantasy has a scoped format that removes the liquidity, live-ops and art burden while keeping the hook.

**Scoped alternatives that keep the MOBA/MMO appeal**

| Appeal the founders want | Scoped format | What it removes | Evidence it works |
|---|---|---|---|
| MOBA hero kits, item builds, drafting | **Co-op PvE "hero-draft" roguelite or survivors-like**: 1-4 players pick MOBA-style hero kits and push lanes and towers against AI waves, on relay networking | Matchmaking liquidity, anti-cheat, dedicated servers, skin economy | Survivors-likes produced repeated 1M+ solo hits ([Wikipedia](https://en.wikipedia.org/wiki/Vampire_Survivors%E2%80%93like)); relay co-op is free to 100 CCU ([Photon](https://www.photonengine.com/fusion/pricing)) |
| MOBA competitive depth and ranked play | **Async-PvP auto-battler or ghost-data matchmaking** (fight stored snapshots of other players' builds) | Real-time concurrency and netcode | Super Auto Pets, 2 devs, 1M+ installs ([Wikipedia](https://en.wikipedia.org/wiki/Super_Auto_Pets)) |
| MOBA real-time PvP, if it is non-negotiable | 1v1 or 2v2 with bot backfill, one region first, **premium rather than F2P** | Most of the liquidity requirement and whale-dependent monetization | Inference from the MOBA failure pattern; no small-team proof exists |
| MMO persistent progression, skilling, economy | **Idle/incremental MMO** with leaderboards, trading and async guilds | Combat netcode, shared world, concurrency | IdleOn (solo, 1M+ installs per app) ([AppBrain](https://www.appbrain.com/dev/LavaFlame2/)); Melvor Idle ~$6.7M gross [EST] ([Steam Revenue Calculator](https://steam-revenue-calculator.com/app/1267910/melvor-idle)) |
| MMO shared world with friends | **Player-hosted co-op survival or colony world** (1-10 players per world) | 24/7 ops, content treadmill, population risk | Valheim, 5 people, 12M+ ([GameDev Reports](https://gamedevreports.substack.com/p/valheim-sales-have-exceeded-12m-copies)) |
| MMO loot, gear and risk | **PvE extraction** | PvP population, anti-cheat | Escape from Duckov, 3M in ~3 weeks ([Game Developer](https://www.gamedeveloper.com/business/escape-from-duckov-has-sold-2-million-copies-in-two-weeks)) |
| MMO "living world" simulation | **Colony/automation sim with optional co-op**, where the world is simulated rather than populated | Everything that requires strangers online | RimWorld, Factorio, Mindustry trajectories (see above) |

Two combinations fit this team best. The first is a **co-op hero-draft roguelite** that turns MOBA builds and lane pressure into a 1-4 player PvE loop. It uses the engineers' netcode skills while avoiding a real-time PvP population. The second is a **colony or automation sim with a persistent, player-hosted world**, which delivers the MMO "living world" through simulation depth instead of headcount. Both work with a constrained art style (flat low-poly or pixel with shader work) and a commissioned capsule. Both also leave a path to the founders' larger ambition. If the game finds an audience, async leaderboards, trading or small-shard servers can be added later, after demand is proven. That order is the reverse of Brighter Shores and Ashes of Creation, which paid for the whole infrastructure before proving demand.

## Conclusion

The core finding is that strong engineering is an advantage only in genres where the simulation itself is the product. It becomes a liability in genres where the product is a live population of strangers. MOBAs and MMOs look like engineering showcases, but money, headcount and experience did not save them, because they fail on liquidity, retention and the content treadmill rather than on technology. Genres where r2ts's skills compound are the ones where a better simulation, a smarter AI or a faster renderer is itself what players buy. Those are automation, colony sims and systemic roguelites.

Several facts in the research remain uncertain. No source publishes cohort medians for automation, survivors-likes, MOBAs or MMOs. Revenue estimates for individual games vary by 2x. The difficulty scores are analyst judgment. The data does show consistently that the first title should be scoped for 12-24 months and a premium price, and built to be fun for one player. The MOBA/MMO appeal should enter as a design layer on a working game, not as the foundation. If the studio gains traction, the network, community and cash flow from a successful systems game are what could someday support a small-shard persistent world. Starting there reverses the order that every failed challenger in this report followed.
