//! The sim inspector: a live map plus panels showing the world's state.
//!
//! Everything drawn here is read straight out of the `World` each frame, so
//! what you see is exactly what the sim holds. Keys and clicks turn into the
//! same commands the prompt uses.

use std::collections::VecDeque;
use std::io::stdout;
use std::sync::mpsc::Receiver;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use ratatui::buffer::Buffer;
use ratatui::crossterm::event::{
    self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind, KeyModifiers,
    MouseButton, MouseEventKind,
};
use ratatui::crossterm::execute;
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Clear, Paragraph};
use ratatui::{DefaultTerminal, Frame};
use sim::{
    Input, Player, PlayerCommand, PlayerId, Slot, SpeciesId, SystemCommand, TilePos, World, debug,
};

use crate::host::{Flow, Host, describe_inventory};
use crate::output;

const CONSOLE_LINES: usize = 300;
const HELP_TEXT: &str = "\
Type a command and press Enter. Everything from the prompt works:
  goto 10 10 · move ne 5 · mine · craft smelter · place smelter · stop
  insert 0 fuel ore:kel 5 · take 0 · assay · rename kel Kelvite · species
  new 42 · load 42 · save · pause · resume · speed 20 · help · quit

Walk        arrow keys (hold to keep walking), or click a tile
Clear line  Esc          Help  F1          Quit  quit, or Ctrl-C";

/// 256-color indexes: they work in every common terminal, unlike RGB.
mod palette {
    use ratatui::style::Color;
    pub const OFF_MAP: Color = Color::Indexed(16);
    pub const GROUND: Color = Color::Indexed(235);
    pub const SPAWN: Color = Color::Indexed(58);
    pub const TARGET: Color = Color::Indexed(28);
    pub const HOVER: Color = Color::Indexed(250);
    pub const BUILDING: Color = Color::Indexed(172);
    pub const ME: Color = Color::Indexed(231);
    pub const OTHERS: [Color; 5] = [
        Color::Indexed(201),
        Color::Indexed(51),
        Color::Indexed(226),
        Color::Indexed(46),
        Color::Indexed(208),
    ];
    pub const DIM: Color = Color::Indexed(245);
    pub const ACCENT: Color = Color::Indexed(214);
    pub const WARN: Color = Color::Indexed(203);
}

/// One (live, depleted) colour pair per species index.
const SPECIES_COLORS: [(u8, u8); 8] = [
    (67, 24),
    (166, 94),
    (246, 240),
    (180, 101),
    (141, 54),
    (78, 22),
    (213, 89),
    (221, 100),
];

fn ore_color(species: SpeciesId, depleted: bool) -> Color {
    let (live, dead) = SPECIES_COLORS[usize::from(species.0) % SPECIES_COLORS.len()];
    Color::Indexed(if depleted { dead } else { live })
}

fn player_color(id: PlayerId, me: Option<PlayerId>) -> Color {
    if Some(id) == me {
        palette::ME
    } else {
        palette::OTHERS[id.0 as usize % palette::OTHERS.len()]
    }
}

/// Measures how fast ticks actually arrive, from wall-clock samples.
struct RateMeter {
    samples: VecDeque<(Instant, u64)>,
}

impl RateMeter {
    fn sample(&mut self, tick: Option<u64>) {
        let now = Instant::now();
        if let Some(t) = tick {
            self.samples.push_back((now, t));
        }
        while self
            .samples
            .front()
            .is_some_and(|(at, _)| now - *at > Duration::from_secs(2))
        {
            self.samples.pop_front();
        }
    }

    fn tps(&self) -> Option<f64> {
        let (first, last) = (self.samples.front()?, self.samples.back()?);
        let secs = (last.0 - first.0).as_secs_f64();
        (secs > 0.25).then(|| (last.1.saturating_sub(first.1)) as f64 / secs)
    }
}

struct Ui {
    console: VecDeque<String>,
    /// Lines scrolled up from the newest. 0 follows new output.
    console_scroll: usize,
    /// Where the console was drawn last frame, for the mouse wheel.
    console_area: Rect,
    /// The command line. Always active: typed characters land here.
    input: String,
    hover: Option<TilePos>,
    /// Where the map was drawn last frame, for turning mouse cells into tiles.
    map_area: Rect,
    map_origin: TilePos,
    rate: RateMeter,
    show_help: bool,
}

impl Ui {
    fn push(&mut self, line: impl Into<String>) {
        if self.console.len() == CONSOLE_LINES {
            self.console.pop_front();
        }
        self.console.push_back(line.into());
        // Keep the same lines in view when scrolled up while new ones arrive.
        if self.console_scroll > 0 {
            self.console_scroll += 1;
        }
    }

    fn scroll_console(&mut self, delta: i32) {
        let max = self.console.len().saturating_sub(1);
        self.console_scroll =
            (self.console_scroll as i64 + i64::from(delta)).clamp(0, max as i64) as usize;
    }

    fn take_output(&mut self) {
        for line in output::drain() {
            self.push(line);
        }
    }

    fn tile_at(&self, column: u16, row: u16) -> Option<TilePos> {
        let a = self.map_area;
        let inside = (a.x..a.x + a.width).contains(&column) && (a.y..a.y + a.height).contains(&row);
        inside.then(|| {
            TilePos::new(
                self.map_origin.x + i32::from(column - a.x),
                self.map_origin.y + 2 * i32::from(row - a.y),
            )
        })
    }
}

pub fn run(host: Arc<Mutex<Host>>, lines: Receiver<String>) -> std::io::Result<()> {
    output::capture(true);
    let mut terminal = ratatui::init();
    let _ = execute!(stdout(), EnableMouseCapture);
    let result = main_loop(&mut terminal, &host, &lines);
    let _ = execute!(stdout(), DisableMouseCapture);
    ratatui::restore();
    output::capture(false);
    result
}

fn main_loop(
    terminal: &mut DefaultTerminal,
    host: &Arc<Mutex<Host>>,
    lines: &Receiver<String>,
) -> std::io::Result<()> {
    let mut ui = Ui {
        console: VecDeque::new(),
        console_scroll: 0,
        console_area: Rect::default(),
        input: String::new(),
        hover: None,
        map_area: Rect::default(),
        map_origin: TilePos::new(0, 0),
        rate: RateMeter {
            samples: VecDeque::new(),
        },
        show_help: false,
    };
    ui.push("Inspector ready. Type a command and press Enter (help lists them). Arrows or clicks walk. F1 for keys.");
    ui.take_output();

    loop {
        for line in lines.try_iter() {
            ui.push(line.trim_start());
        }
        {
            let h = host.lock().unwrap();
            ui.rate.sample(h.world().map(|w| w.tick));
            terminal.draw(|f| draw(f, &h, &mut ui))?;
        }

        if !event::poll(Duration::from_millis(50))? {
            continue;
        }
        // Handle everything queued before drawing again.
        loop {
            let ev = event::read()?;
            let mut h = host.lock().unwrap();
            if let Flow::Quit = handle(ev, &mut h, &mut ui) {
                return Ok(());
            }
            drop(h);
            ui.take_output();
            if !event::poll(Duration::ZERO)? {
                break;
            }
        }
    }
}

fn handle(ev: Event, h: &mut Host, ui: &mut Ui) -> Flow {
    match ev {
        Event::Key(key) if matches!(key.kind, KeyEventKind::Press | KeyEventKind::Repeat) => {
            if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
                return Flow::Quit;
            }
            if ui.show_help {
                ui.show_help = false;
                return Flow::Continue;
            }
            let result = match key.code {
                KeyCode::F(1) => {
                    ui.show_help = true;
                    Ok(())
                }
                KeyCode::Esc => {
                    ui.input.clear();
                    ui.console_scroll = 0;
                    Ok(())
                }
                KeyCode::PageUp => {
                    let page = i32::from(ui.console_area.height.saturating_sub(2)).max(1);
                    ui.scroll_console(page);
                    Ok(())
                }
                KeyCode::PageDown => {
                    let page = i32::from(ui.console_area.height.saturating_sub(2)).max(1);
                    ui.scroll_console(-page);
                    Ok(())
                }
                KeyCode::End => {
                    ui.console_scroll = 0;
                    Ok(())
                }
                KeyCode::Backspace => {
                    ui.input.pop();
                    Ok(())
                }
                KeyCode::Char(c) => {
                    ui.input.push(c);
                    Ok(())
                }
                KeyCode::Enter => {
                    let line = std::mem::take(&mut ui.input);
                    let args: Vec<&str> = line.split_whitespace().collect();
                    if args.is_empty() {
                        Ok(())
                    } else {
                        ui.push(format!("> {line}"));
                        match h.run(&args) {
                            Ok(Flow::Quit) => return Flow::Quit,
                            Ok(Flow::Continue) => Ok(()),
                            Err(msg) => Err(msg),
                        }
                    }
                }
                KeyCode::Up => step(h, 0, -1),
                KeyCode::Down => step(h, 0, 1),
                KeyCode::Left => step(h, -1, 0),
                KeyCode::Right => step(h, 1, 0),
                _ => Ok(()),
            };
            if let Err(msg) = result {
                ui.push(msg);
            }
        }
        Event::Mouse(m) => match m.kind {
            MouseEventKind::Moved => ui.hover = ui.tile_at(m.column, m.row),
            MouseEventKind::ScrollUp => ui.scroll_console(3),
            MouseEventKind::ScrollDown => ui.scroll_console(-3),
            MouseEventKind::Down(MouseButton::Left) => {
                if let Some(target) = ui.tile_at(m.column, m.row)
                    && let Err(msg) = h.act(PlayerCommand::MoveTo { target })
                {
                    ui.push(msg);
                }
            }
            _ => {}
        },
        _ => {}
    }
    Flow::Continue
}

/// Walk one tile from where you're already headed, so holding a key keeps
/// you going.
fn step(h: &mut Host, dx: i32, dy: i32) -> Result<(), String> {
    let (w, me) = h
        .world()
        .zip(h.me_id())
        .ok_or("No world yet. Type `new 42` or restart with --connect.")?;
    let p = w.player(me).ok_or("You have no player yet.")?;
    let from = p.target.unwrap_or(p.pos);
    let target = TilePos::new(
        (from.x + dx).clamp(0, w.width() - 1),
        (from.y + dy).clamp(0, w.height() - 1),
    );
    h.act(PlayerCommand::MoveTo { target })
}

// ---------------------------------------------------------------- drawing

fn draw(f: &mut Frame, h: &Host, ui: &mut Ui) {
    let [top, console, bar] = Layout::vertical([
        Constraint::Min(12),
        Constraint::Length(12),
        Constraint::Length(1),
    ])
    .areas(f.area());
    let [map, side] = Layout::horizontal([Constraint::Min(40), Constraint::Length(46)]).areas(top);

    draw_map(f, map, h, ui);
    draw_side(f, side, h, ui);
    draw_console(f, console, ui);
    draw_bar(f, bar, ui);
    if ui.show_help {
        draw_help(f);
    }
}

fn panel(title: &str) -> Block<'static> {
    Block::bordered()
        .title(format!(" {title} "))
        .border_style(Style::default().fg(palette::DIM))
}

fn draw_map(f: &mut Frame, area: Rect, h: &Host, ui: &mut Ui) {
    let Some(world) = h.world() else {
        f.render_widget(
            Paragraph::new("No world.\n\nPress : and type  new 42  to create one,\nor restart with --connect <host> to join.")
                .block(panel("Map")),
            area,
        );
        return;
    };
    let me = h.me_id();
    let focus = me
        .and_then(|id| world.player(id))
        .map_or(world.spawn_tile(), |p| p.pos);
    let block = panel(&format!(
        "Map {}x{} · {} spawn · {} you · {} others · {} smelter · ore coloured by species",
        world.width(),
        world.height(),
        "▀",
        "▀",
        "▀",
        "▀"
    ));
    let inner = block.inner(area);
    f.render_widget(block, area);
    let (w, h_tiles) = (world.width(), world.height());
    let (vw, vh) = (i32::from(inner.width), i32::from(inner.height) * 2);
    let ox = if w <= vw {
        0
    } else {
        (focus.x - vw / 2).clamp(0, w - vw)
    };
    let oy = if h_tiles <= vh {
        0
    } else {
        (focus.y - vh / 2).clamp(0, h_tiles - vh) & !1
    };
    ui.map_area = inner;
    ui.map_origin = TilePos::new(ox, oy);

    let my_target = me.and_then(|id| world.player(id)).and_then(|p| p.target);
    let color_of = |pos: TilePos| -> Color {
        if !world.in_bounds(pos) {
            return palette::OFF_MAP;
        }
        if let Some(p) = world.players.iter().find(|p| p.pos == pos) {
            return player_color(p.id, me);
        }
        if ui.hover == Some(pos) {
            return palette::HOVER;
        }
        if my_target == Some(pos) {
            return palette::TARGET;
        }
        if world.building_at(pos).is_some() {
            return palette::BUILDING;
        }
        if let Some(d) = world.deposit_at(pos) {
            return ore_color(d.species, d.is_depleted());
        }
        if pos == world.spawn_tile() {
            return palette::SPAWN;
        }
        palette::GROUND
    };

    let buf: &mut Buffer = f.buffer_mut();
    for row in 0..inner.height {
        for col in 0..inner.width {
            let x = ox + i32::from(col);
            let y = oy + 2 * i32::from(row);
            let top = color_of(TilePos::new(x, y));
            let bottom = color_of(TilePos::new(x, y + 1));
            if let Some(cell) = buf.cell_mut((inner.x + col, inner.y + row)) {
                cell.set_char('▀').set_fg(top).set_bg(bottom);
            }
        }
    }
    // Recolor the legend swatches in the title now that the border is drawn.
    let legend = [
        palette::SPAWN,
        palette::ME,
        palette::OTHERS[0],
        palette::BUILDING,
    ];
    let mut found = 0;
    for x in area.x..area.x + area.width {
        if found == legend.len() {
            break;
        }
        if let Some(cell) = buf.cell_mut((x, area.y))
            && cell.symbol() == "▀"
        {
            cell.set_fg(legend[found]).set_bg(palette::GROUND);
            found += 1;
        }
    }
}

fn draw_side(f: &mut Frame, area: Rect, h: &Host, ui: &Ui) {
    let Some(world) = h.world() else {
        let mut lines: Vec<Line> = h.link_lines().into_iter().map(Line::from).collect();
        lines.insert(0, Line::from("no world"));
        f.render_widget(Paragraph::new(lines).block(panel("World")), area);
        return;
    };
    let me = h.me_id();
    let n = world.players.len() as u16;
    let b = world.buildings.len() as u16;
    let sp = world.species.len() as u16;
    // One row per design in hand or on the built list, for me only: this panel
    // is about what I am deciding to spend parts on.
    let mine = world.player(me.unwrap_or(sim::PlayerId(u32::MAX)));
    let designs = mine.map_or(0, |p| {
        p.assemblies.len() as u16 + u16::from(p.tool.is_some())
    });
    let [
        w_area,
        p_area,
        inv_area,
        mach_area,
        sp_area,
        tile_area,
        bld_area,
        dep_area,
        in_area,
    ] = Layout::vertical([
        Constraint::Length(8),
        Constraint::Length((n + 2).clamp(3, 8)), // borders + one row per player
        Constraint::Length((n + 2).clamp(3, 8)), // borders + one row per player
        Constraint::Length((designs + 2).clamp(3, 7)), // borders + one row per design
        Constraint::Length((sp + 3).clamp(4, 11)), // borders + header + one row per species
        Constraint::Length(6),
        Constraint::Length((b + 2).clamp(3, 8)), // borders + one row per building
        Constraint::Min(4),
        Constraint::Length(5),
    ])
    .areas(area);

    // World
    let depleted = world.deposits.iter().filter(|d| d.is_depleted()).count();
    let tps = ui.rate.tps().map_or("–".to_string(), |t| format!("{t:.1}"));
    let mut lines = vec![
        kv("seed", world.seed.to_string()),
        kv("tick", format!("{} · {tps} tps measured", world.tick)),
        kv("hash", format!("{:016x}", world.state_hash())),
        kv(
            "deposits",
            format!("{} ({depleted} depleted)", world.deposits.len()),
        ),
    ];
    lines.extend(
        h.link_lines()
            .into_iter()
            .map(|l| Line::from(l).style(Style::default().fg(palette::DIM))),
    );
    f.render_widget(Paragraph::new(lines).block(panel("World")), w_area);

    // Players
    let lines: Vec<Line> = world
        .players
        .iter()
        .map(|p| {
            let walking = p
                .target
                .map(|t| format!(" → ({},{})", t.x, t.y))
                .unwrap_or_default();
            let mining = p
                .mining
                .map(|m| format!(" ⛏ dep {}", m.deposit.0))
                .unwrap_or_default();
            let crafting = p
                .crafting
                .map(|c| format!(" ⚒ {} ×{}", c.recipe.name(), c.remaining))
                .unwrap_or_default();
            let assaying = p
                .assaying
                .map(|a| format!(" 🔍 dep {}", a.deposit.0))
                .unwrap_or_default();
            Line::from(vec![
                Span::styled("█ ", Style::default().fg(player_color(p.id, me))),
                Span::raw(format!(
                    "{} {}{} ({},{}){walking}{mining}{crafting}{assaying}",
                    p.id.0,
                    p.name,
                    if Some(p.id) == me { "*" } else { "" },
                    p.pos.x,
                    p.pos.y
                )),
            ])
        })
        .collect();
    f.render_widget(
        Paragraph::new(lines).block(panel("Players (* you)")),
        p_area,
    );

    // Inventory: one line per player
    let width = usize::from(inv_area.width.saturating_sub(14));
    let lines: Vec<Line> = world
        .players
        .iter()
        .map(|p| {
            Line::from(vec![
                Span::styled(
                    format!("{:<10} ", truncate(&p.name, 10)),
                    Style::default().fg(palette::DIM),
                ),
                Span::raw(truncate(&describe_inventory(world, &p.inventory), width)),
            ])
        })
        .collect();
    f.render_widget(Paragraph::new(lines).block(panel("Inventory")), inv_area);

    // Machines: what I have built, and whether it will survive being used.
    //
    // The verdict and the numbers come from `sim` (`debug::assembly_readout`),
    // not from this file: a renderer reads rules, it does not own them, and two
    // clients computing this would eventually disagree. Amendment A5's point is
    // that the bad case has to be visible here rather than discovered when the
    // design breaks.
    let width = usize::from(mach_area.width.saturating_sub(10));
    let design_line = |label: &str, built: &sim::Built| {
        let verdict = built.assembly.stat_range(&world.species).verdict();
        let colour = match verdict {
            sim::BreakVerdict::Safe => palette::DIM,
            sim::BreakVerdict::Uncertain => palette::ACCENT,
            sim::BreakVerdict::WillBreak => palette::WARN,
        };
        Line::from(vec![
            Span::styled(format!("{label:<8} "), Style::default().fg(palette::DIM)),
            Span::styled(
                truncate(&debug::assembly_readout(world, built), width),
                Style::default().fg(colour),
            ),
        ])
    };
    let mut lines: Vec<Line> = Vec::new();
    if let Some(p) = mine {
        match &p.tool {
            Some(t) => lines.push(design_line("in hand", t)),
            None => lines
                .push(Line::from("in hand  bare hands").style(Style::default().fg(palette::DIM))),
        }
        for (i, built) in p.assemblies.iter().enumerate() {
            lines.push(design_line(&format!("built {i}"), built));
        }
    }
    if lines.is_empty() {
        lines.push(Line::from("no player").style(Style::default().fg(palette::DIM)));
    }
    f.render_widget(
        Paragraph::new(lines).block(panel("Machines (mass vs budget)")),
        mach_area,
    );

    // Species: the roster and its sheets
    let mut lines = vec![
        Line::from(format!(
            " {:<11}{:>4}{:>4}{:>4}{:>4}{:>4}{:>4}  ",
            "name", "den", "str", "hrd", "heat", "rea", "con"
        ))
        .style(Style::default().fg(palette::DIM)),
    ];
    for s in &world.species {
        let sh = &s.sheet;
        let mark = if sim::ladder::hand_lit_fuel(s) {
            "fuel"
        } else if sim::ladder::hand_minable(s) {
            "hand"
        } else {
            ""
        };
        let _ = sh;
        // Exact once assayed; the band's low end with a ~ until then.
        let read = |p| {
            if s.assayed {
                s.sheet.get(p).to_string()
            } else {
                format!("~{}", sim::Sheet::band(s.sheet.get(p)).0)
            }
        };
        lines.push(Line::from(vec![
            Span::styled("█", Style::default().fg(ore_color(s.id, false))),
            Span::raw(format!(
                "{:<11}{:>4}{:>4}{:>4}{:>4}{:>4}{:>4}  {mark}",
                truncate(s.name(), 11),
                read(sim::Property::Density),
                read(sim::Property::Strength),
                read(sim::Property::Hardness),
                read(sim::Property::HeatTolerance),
                read(sim::Property::Reactivity),
                read(sim::Property::Conductivity)
            )),
        ]));
    }
    f.render_widget(
        Paragraph::new(lines).block(panel("Species (~ = rough until assayed)")),
        sp_area,
    );

    // Tile under the mouse, or under you
    let (label, tile) = match ui.hover {
        Some(t) if world.in_bounds(t) => ("Tile (mouse)", Some(t)),
        _ => (
            "Tile (you)",
            me.and_then(|id| world.player(id)).map(|p| p.pos),
        ),
    };
    let lines = tile.map_or_else(
        || vec![Line::from("–")],
        |t| {
            let chunk = t.chunk();
            let mut lines = vec![Line::from(format!(
                "({},{}) chunk ({},{}) · {} from spawn",
                t.x,
                t.y,
                chunk.x,
                chunk.y,
                chunk.distance(world.spawn)
            ))];
            if let Some(b) = world.building_at(t) {
                lines.push(Line::from(format!(
                    "{} {} at ({},{})",
                    b.kind.name(),
                    b.id.0,
                    b.pos.x,
                    b.pos.y
                )));
                lines.push(Line::from(debug::building_status(world, b)));
            }
            match world.deposit_at(t) {
                Some(d) => {
                    lines.push(Line::from(format!(
                        "deposit {} · {} · r{} at ({},{})",
                        d.id.0,
                        world.species(d.species).name(),
                        d.radius,
                        d.center.x,
                        d.center.y
                    )));
                    lines.push(Line::from(format!(
                        "{} ore left · purity {} (grade {}){}",
                        d.amount,
                        d.purity,
                        d.grade().letter(),
                        if d.is_depleted() { " · DEPLETED" } else { "" }
                    )));
                    // Reach, on its own line and from the sim (ASSA-43). The
                    // panel named everything about the rock except whether
                    // anything in the game can break it.
                    if let Some(why) = debug::deposit_dead_end_note(world, d) {
                        lines.push(Line::from(why));
                    }
                }
                None if t == world.spawn_tile() => lines.push(Line::from("spawn")),
                None => lines.push(Line::from("empty ground")),
            }
            let here: Vec<&str> = world
                .players
                .iter()
                .filter(|p| p.pos == t)
                .map(|p| p.name.as_str())
                .collect();
            if !here.is_empty() {
                lines.push(Line::from(format!("players here: {}", here.join(", "))));
            }
            lines
        },
    );
    f.render_widget(Paragraph::new(lines).block(panel(label)), tile_area);

    // Buildings
    let width = usize::from(bld_area.width.saturating_sub(4));
    let lines: Vec<Line> = if world.buildings.is_empty() {
        vec![
            Line::from("none · craft smelter, then place smelter")
                .style(Style::default().fg(palette::DIM)),
        ]
    } else {
        world
            .buildings
            .iter()
            .map(|b| {
                Line::from(vec![
                    Span::styled("█", Style::default().fg(palette::BUILDING)),
                    Span::raw(truncate(
                        &format!(
                            "{:>2} {} ({},{}) {}",
                            b.id.0,
                            b.kind.name(),
                            b.pos.x,
                            b.pos.y,
                            debug::building_status(world, b)
                        ),
                        width,
                    )),
                ])
            })
            .collect()
    };
    f.render_widget(Paragraph::new(lines).block(panel("Buildings")), bld_area);

    // Deposits, nearest first
    let from = me
        .and_then(|id| world.player(id))
        .map_or(world.spawn_tile(), |p| p.pos);
    let mut deps: Vec<_> = world.deposits.iter().collect();
    deps.sort_by_key(|d| (d.center.x - from.x).abs().max((d.center.y - from.y).abs()));
    let mut lines = vec![
        Line::from(format!(
            "{:>3} {:<8} {:>9} {:>6} {:>3} {:>4}",
            "id", "species", "center", "left", "pur", "dist"
        ))
        .style(Style::default().fg(palette::DIM)),
    ];
    for d in deps {
        let dist = (d.center.x - from.x).abs().max((d.center.y - from.y).abs());
        lines.push(Line::from(vec![
            Span::styled(
                "█",
                Style::default().fg(ore_color(d.species, d.is_depleted())),
            ),
            Span::raw(format!(
                "{:>2} {:<8} {:>9} {:>6} {:>2}{} {:>4}",
                d.id.0,
                truncate(world.species(d.species).name(), 8),
                format!("({},{})", d.center.x, d.center.y),
                d.amount,
                d.purity,
                d.grade().letter(),
                dist
            )),
        ]));
    }
    f.render_widget(
        Paragraph::new(lines).block(panel("Deposits (nearest first)")),
        dep_area,
    );

    // Recent inputs: what the sim was actually fed, per tick
    let inputs = h.recent_inputs();
    let lines: Vec<Line> = inputs
        .iter()
        .rev()
        .take(usize::from(in_area.height.saturating_sub(2)))
        .map(|(tick, inputs)| {
            let text = inputs
                .iter()
                .map(|i| describe_input(i, world))
                .collect::<Vec<_>>()
                .join("; ");
            Line::from(vec![
                Span::styled(format!("{tick:>6} "), Style::default().fg(palette::DIM)),
                Span::raw(truncate(
                    &text,
                    usize::from(in_area.width.saturating_sub(10)),
                )),
            ])
        })
        .collect();
    let lines = if lines.is_empty() {
        vec![Line::from("none yet").style(Style::default().fg(palette::DIM))]
    } else {
        lines
    };
    f.render_widget(
        Paragraph::new(lines).block(panel("Inputs applied (newest first)")),
        in_area,
    );
}

fn draw_console(f: &mut Frame, area: Rect, ui: &mut Ui) {
    ui.console_area = area;
    let visible = usize::from(area.height.saturating_sub(2));
    let total = ui.console.len();
    // Never scroll past the top; clamp in case the window shrank.
    ui.console_scroll = ui.console_scroll.min(total.saturating_sub(visible));
    let end = total - ui.console_scroll;
    let start = end.saturating_sub(visible);
    let title = if ui.console_scroll > 0 {
        format!(
            "Events & console · {} newer below · End to follow",
            ui.console_scroll
        )
    } else {
        "Events & console · wheel or PgUp/PgDn to scroll".to_string()
    };
    let lines: Vec<Line> = ui
        .console
        .iter()
        .skip(start)
        .take(end - start)
        .map(|l| {
            let style = if l.contains("rejected") || l.contains("WARNING") || l.contains("DESYNC") {
                Style::default().fg(palette::WARN)
            } else if l.starts_with("> ") {
                Style::default().fg(palette::ACCENT)
            } else {
                Style::default()
            };
            Line::from(l.as_str()).style(style)
        })
        .collect();
    f.render_widget(Paragraph::new(lines).block(panel(&title)), area);
}

fn draw_bar(f: &mut Frame, area: Rect, ui: &Ui) {
    let line = Line::from(vec![
        Span::styled("> ", Style::default().fg(palette::ACCENT)),
        Span::raw(ui.input.as_str()),
        Span::styled("█", Style::default().fg(palette::ACCENT)),
        Span::styled(
            "   Enter runs · arrows/click walk · wheel/PgUp scroll events · F1 keys · Ctrl-C quits",
            Style::default().fg(palette::DIM),
        ),
    ]);
    f.render_widget(Paragraph::new(line), area);
}

fn draw_help(f: &mut Frame) {
    let area = f.area();
    let w = 72.min(area.width);
    let h = 11.min(area.height);
    let rect = Rect::new(
        area.x + (area.width - w) / 2,
        area.y + (area.height - h) / 2,
        w,
        h,
    );
    f.render_widget(Clear, rect);
    f.render_widget(
        Paragraph::new(HELP_TEXT).block(
            Block::bordered()
                .title(" Keys (any key closes) ")
                .border_style(Style::default().fg(palette::ACCENT)),
        ),
        rect,
    );
}

fn kv(key: &str, value: String) -> Line<'static> {
    Line::from(vec![
        Span::styled(
            format!("{key:<9}"),
            Style::default()
                .fg(palette::DIM)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(value),
    ])
}

fn truncate(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        s.to_string()
    } else {
        let cut: String = s.chars().take(max.saturating_sub(1)).collect();
        format!("{cut}…")
    }
}

fn describe_input(input: &Input, world: &World) -> String {
    match input {
        Input::System(SystemCommand::AddPlayer { name }) => format!("+player {name}"),
        Input::Player { player, command } => {
            let who = world
                .player(*player)
                .map_or_else(|| format!("p{}", player.0), |p: &Player| p.name.clone());
            let what = match command {
                PlayerCommand::Mine => "mine".into(),
                PlayerCommand::Craft {
                    recipe,
                    item,
                    count,
                } => format!("craft {} {} {count}", recipe.name(), item.code()),
                PlayerCommand::Place { item, pos } => {
                    format!("place {} {},{}", item.code(), pos.x, pos.y)
                }
                PlayerCommand::Insert {
                    building,
                    slot,
                    item,
                    count,
                } => format!(
                    "insert {} {} {} {count}",
                    building.0,
                    match slot {
                        Slot::Input => "ore",
                        Slot::Fuel => "fuel",
                    },
                    item.code()
                ),
                PlayerCommand::Take { building } => format!("take {}", building.0),
                PlayerCommand::Pickup { building } => format!("pickup {}", building.0),
                PlayerCommand::Assay => "assay".into(),
                PlayerCommand::Rename { species, name } => {
                    format!("rename #{} {name}", species.0)
                }
                PlayerCommand::GrantRename { species, to } => {
                    format!("grant #{} p{}", species.0, to.0)
                }
                PlayerCommand::MakePart {
                    kind,
                    material,
                    count,
                } => format!("make {} {} {count}", kind.name(), material.code()),
                PlayerCommand::Assemble { frame, mounted } => {
                    format!("assemble {} +{}", frame.code(), mounted.len())
                }
                PlayerCommand::Equip { assembly } => format!("equip {assembly}"),
                PlayerCommand::Unequip => "unequip".into(),
                PlayerCommand::PlaceAssembly { assembly, pos } => {
                    format!("plant {assembly} {},{}", pos.x, pos.y)
                }
                PlayerCommand::MoveTo { target } => format!("goto {},{}", target.x, target.y),
                PlayerCommand::Stop => "stop".into(),
            };
            format!("{who}: {what}")
        }
    }
}
