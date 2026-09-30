//! Interactive terminal client for the r2ts sim.
//!
//!     cargo run -p sim-cli                                      # single-player inspector
//!     cargo run -p sim-cli -- --name ada                        # single-player as "ada"
//!     cargo run -p sim-cli -- --connect localhost:7777 --name ada   # join a relay
//!     cargo run -p sim-cli -- --plain                           # old line-by-line prompt
//!
//! The sim stays pure. This host plays the part Godot will later. Alone, a
//! clock thread advances the world. Online, the relay's tick bundles do.
//! The inspector (default in a real terminal) draws the world live; the
//! plain prompt is kept for scripting and piping.

mod host;
mod net;
mod output;
mod tui;

use std::io::IsTerminal;
use std::process::exit;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use rustyline::error::ReadlineError;
use rustyline::{DefaultEditor, ExternalPrinter};

use host::{Flow, Host};

struct Options {
    connect: Option<String>,
    name: String,
    plain: bool,
}

fn main() {
    let opts = parse_args();
    let use_inspector = !opts.plain && std::io::stdin().is_terminal();

    // Lines from background threads (tick events, warnings) go through one
    // channel. The inspector shows them in its console; the plain prompt
    // prints them above the input line.
    let (print_tx, print_rx) = mpsc::channel::<String>();
    let host = Arc::new(Mutex::new(Host::new(opts.name.clone())));

    if !use_inspector {
        println!("r2ts sim · type `help` for commands");
    }
    if let Some(addr) = &opts.connect {
        let (stream, addr, me, world) = net::join(addr, &opts.name).unwrap_or_else(|e| {
            eprintln!("{e}");
            exit(1);
        });
        let reader = stream.try_clone().unwrap_or_else(|e| {
            eprintln!("Could not use the connection: {e}");
            exit(1);
        });
        let out = net::spawn_sender(stream);
        host.lock().unwrap().go_online(addr, world, me, out);
        net::spawn_receiver(reader, Arc::clone(&host), print_tx.clone());
    } else {
        println!("Saves go to {}", host::saves_dir().display());
        println!("Start with `new 42`, or `load 42` to continue a save.");
    }

    let clock = spawn_clock(Arc::clone(&host), print_tx.clone());

    if use_inspector {
        if let Err(e) = tui::run(Arc::clone(&host), print_rx) {
            eprintln!("Inspector error: {e}");
        }
    } else {
        plain_prompt(&host, print_rx);
    }

    host.lock().unwrap().quitting = true;
    let _ = clock.join();
    host.lock().unwrap().save_on_exit();
}

/// The line-by-line prompt, for scripts and terminals without a TTY.
fn plain_prompt(host: &Arc<Mutex<Host>>, print_rx: mpsc::Receiver<String>) {
    let mut editor = DefaultEditor::new().unwrap_or_else(|e| {
        eprintln!("Could not open the terminal: {e}");
        exit(1);
    });
    // Prints above the prompt without mangling what you're typing. Falls
    // back to plain printing when input is piped in.
    match editor.create_external_printer() {
        Ok(mut p) => thread::spawn(move || {
            for line in print_rx {
                let _ = p.print(line);
            }
        }),
        Err(_) => thread::spawn(move || {
            for line in print_rx {
                println!("{line}");
            }
        }),
    };

    loop {
        let prompt = host.lock().unwrap().prompt();
        let line = match editor.readline(&prompt) {
            Ok(line) => line,
            Err(ReadlineError::Interrupted) => {
                println!("(type `quit` or press Ctrl-D to exit)");
                continue;
            }
            Err(ReadlineError::Eof) => break,
            Err(e) => {
                eprintln!("Input error: {e}");
                break;
            }
        };

        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let _ = editor.add_history_entry(line);

        let args: Vec<&str> = line.split_whitespace().collect();
        let result = host.lock().unwrap().run(&args);
        match result {
            Ok(Flow::Continue) => {}
            Ok(Flow::Quit) => break,
            Err(msg) => println!("{msg}"),
        }
    }
}

/// The single-player clock: while a local world is running, step it once
/// per interval and print what happened. Online, the relay drives ticks.
fn spawn_clock(host: Arc<Mutex<Host>>, print: mpsc::Sender<String>) -> JoinHandle<()> {
    thread::spawn(move || {
        loop {
            let interval = {
                let mut h = host.lock().unwrap();
                if h.quitting {
                    break;
                }
                if h.is_running() {
                    for line in h.tick_once() {
                        let _ = print.send(format!("  {line}"));
                    }
                }
                Duration::from_secs_f64(1.0 / f64::from(h.tps))
            };
            thread::sleep(interval);
        }
    })
}

fn parse_args() -> Options {
    let usage = "Usage: sim-cli [--connect host:port] [--name name] [--plain]";
    let mut opts = Options {
        connect: None,
        plain: false,
        name: std::env::var("USER")
            .or_else(|_| std::env::var("USERNAME"))
            .unwrap_or_else(|_| "player".into()),
    };
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--connect" | "-c" => opts.connect = args.next(),
            "--name" | "-n" => {
                if let Some(name) = args.next() {
                    opts.name = name;
                }
            }
            "--plain" => opts.plain = true,
            "-h" | "--help" => {
                println!("{usage}");
                exit(0);
            }
            _ => {
                eprintln!("Didn't understand `{arg}`.\n{usage}");
                exit(1);
            }
        }
    }
    opts
}
