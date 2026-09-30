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
use sim::{Input, OreKind, Player, PlayerCommand, PlayerId, SystemCommand, TilePos, World};

use crate::host::{Flow, Host};
use crate::output;

const CONSOLE_LINES: usize = 300;
const HELP_TEXT: &str = "\
Type a command and press Enter. Everything from the prompt works:
  goto 10 10 · move ne 5 · mine 10 · stop · players · inv · deposits
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

fn ore_color(kind: OreKind, depleted: bool) -> Color {
    Color::Indexed(match (kind, depleted) {
        (OreKind::Iron, false) => 67,
        (OreKind::Iron, true) => 24,
        (OreKind::Copper, false) => 166,
        (OreKind::Copper, true) => 94,
        (OreKind::Coal, false) => 246,
        (OreKind::Coal, true) => 240,
        (OreKind::Stone, false) => 180,
        (OreKind::Stone, true) => 101,
    })
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
        Constraint::Length(9),
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
        "Map {}x{} · {} spawn · {} you · {} others · ore: {} Fe {} Cu {} C {} St",
        world.width(),
        world.height(),
        "▀",
        "▀",
        "▀",
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
        if let Some(d) = world.deposit_at(pos) {
            return ore_color(d.kind, d.is_depleted());
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
        ore_color(OreKind::Iron, false),
        ore_color(OreKind::Copper, false),
        ore_color(OreKind::Coal, false),
        ore_color(OreKind::Stone, false),
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
    let [w_area, p_area, inv_area, tile_area, dep_area, in_area] = Layout::vertical([
        Constraint::Length(8),
        Constraint::Length((n + 2).clamp(3, 8)), // borders + one row per player
        Constraint::Length((n + 3).clamp(4, 9)), // borders + header + one row per player
        Constraint::Length(5),
        Constraint::Min(4),
        Constraint::Length(7),
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
            Line::from(vec![
                Span::styled("█ ", Style::default().fg(player_color(p.id, me))),
                Span::raw(format!(
                    "{} {}{} ({},{}){walking}",
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

    // Inventory table
    let mut lines = vec![
        Line::from(format!(
            "{:<10} {:>6} {:>6} {:>6} {:>6}",
            "", "iron", "copper", "coal", "stone"
        ))
        .style(Style::default().fg(palette::DIM)),
    ];
    for p in &world.players {
        let i = &p.inventory;
        lines.push(Line::from(format!(
            "{:<10} {:>6} {:>6} {:>6} {:>6}",
            truncate(&p.name, 10),
            i.iron,
            i.copper,
            i.coal,
            i.stone
        )));
    }
    f.render_widget(Paragraph::new(lines).block(panel("Inventory")), inv_area);

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
            match world.deposit_at(t) {
                Some(d) => {
                    lines.push(Line::from(format!(
                        "deposit {} · {:?} · r{} at ({},{})",
                        d.id.0, d.kind, d.radius, d.center.x, d.center.y
                    )));
                    lines.push(Line::from(format!(
                        "{} ore left · purity {}{}",
                        d.amount,
                        d.purity,
                        if d.is_depleted() { " · DEPLETED" } else { "" }
                    )));
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

    // Deposits, nearest first
    let from = me
        .and_then(|id| world.player(id))
        .map_or(world.spawn_tile(), |p| p.pos);
    let mut deps: Vec<_> = world.deposits.iter().collect();
    deps.sort_by_key(|d| (d.center.x - from.x).abs().max((d.center.y - from.y).abs()));
    let mut lines = vec![
        Line::from(format!(
            "{:>3} {:<7} {:>9} {:>6} {:>4} {:>4}",
            "id", "kind", "center", "left", "pur", "dist"
        ))
        .style(Style::default().fg(palette::DIM)),
    ];
    for d in deps {
        let dist = (d.center.x - from.x).abs().max((d.center.y - from.y).abs());
        lines.push(Line::from(vec![
            Span::styled("█", Style::default().fg(ore_color(d.kind, d.is_depleted()))),
            Span::raw(format!(
                "{:>2} {:<7} {:>9} {:>6} {:>4} {:>4}",
                d.id.0,
                format!("{:?}", d.kind),
                format!("({},{})", d.center.x, d.center.y),
                d.amount,
                d.purity,
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

fn draw_console(f: &mut Frame, area: Rect, ui: &Ui) {
    let visible = usize::from(area.height.saturating_sub(2));
    let lines: Vec<Line> = ui
        .console
        .iter()
        .skip(ui.console.len().saturating_sub(visible))
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
    f.render_widget(Paragraph::new(lines).block(panel("Events & console")), area);
}

fn draw_bar(f: &mut Frame, area: Rect, ui: &Ui) {
    let line = Line::from(vec![
        Span::styled("> ", Style::default().fg(palette::ACCENT)),
        Span::raw(ui.input.as_str()),
        Span::styled("█", Style::default().fg(palette::ACCENT)),
        Span::styled(
            "   Enter runs · arrows/click walk · Esc clears · F1 keys · Ctrl-C quits",
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
                PlayerCommand::Extract { deposit, amount } => {
                    format!("extract {} {amount}", deposit.0)
                }
                PlayerCommand::MoveTo { target } => format!("goto {},{}", target.x, target.y),
                PlayerCommand::Stop => "stop".into(),
            };
            format!("{who}: {what}")
        }
    }
}
