# Shortcuts for the common commands. Run from the repo root.
#
#   make relay                 host world 42 on port 7777
#   make relay SEED=7          host a different world
#   make fresh                 host world 42 from scratch, ignoring its save
#   make join                  connect to a relay on this machine, as $USER
#   make join HOST=192.168.1.48 NAME=ada
#                              connect to a relay on another machine (port
#                              defaults to 7777; use HOST=ip:port to change)
#   make ip                    print this machine's address to give players
#   make play                  single-player inspector
#   make test                  run the test suite
#   make client-lib            build the sim binding the Godot client loads
#
# BEFORE YOU OPEN sim-game/client IN GODOT, RUN `make client-lib`. The client
# loads the real sim through a GDExtension, and Godot ABORTS (exit 134, a C++
# stack trace, no usable message) when a `.gdextension` points at a library
# that is not there -- measured 2026-10-01. CI builds it per platform before
# every export; from a checkout it is yours to build.
#   make talk                  spoken design conversation (make talk-text to type)
#
# Over the internet, HOST is the host's Tailscale address (100.x.y.z) or
# their public IP with TCP 7777 forwarded.

NAME ?= $(USER)
HOST ?= localhost:7777
SEED ?= 42

.PHONY: relay fresh join play plain test client-lib ip talk talk-text

relay:
	cd sim-game && cargo run -p sim-relay -- $(SEED)

fresh:
	cd sim-game && cargo run -p sim-relay -- $(SEED) --fresh

join:
	cd sim-game && cargo run -p sim-cli -- --connect $(HOST) --name $(NAME)

play:
	cd sim-game && cargo run -p sim-cli -- --name $(NAME)

plain:
	cd sim-game && cargo run -p sim-cli -- --plain --connect $(HOST) --name $(NAME)

test:
	cd sim-game && cargo test

# The library name differs per platform and `sim.gdextension` names all three,
# so copy whichever one cargo just wrote rather than guessing.
client-lib:
	cd sim-game && cargo build -p sim-godot --release
	mkdir -p sim-game/client/bin
	cd sim-game && cp target/release/libsim_godot.dylib \
		target/release/libsim_godot.so \
		target/release/sim_godot.dll client/bin/ 2>/dev/null || true
	@ls sim-game/client/bin/*sim_godot* >/dev/null 2>&1 \
		|| { echo "cargo built no sim-godot library; nothing copied into client/bin/"; exit 1; }
	@echo "client/bin: $$(ls sim-game/client/bin)"

ip:
	@ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | cut -d' ' -f1 || echo "Could not find a network address; start the relay and read it there."

talk:
	tools/voice/design_chat.py

talk-text:
	tools/voice/design_chat.py --text
