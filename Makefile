# Shortcuts for the common commands. Run from the repo root.
#
#   make relay                 host world 42 on port 7777
#   make relay SEED=7          host a different world
#   make fresh                 host world 42 from scratch, ignoring its save
#   make join                  connect to localhost as $USER
#   make join NAME=ada HOST=192.168.1.48:7777
#   make play                  single-player inspector
#   make test                  run the test suite

NAME ?= $(USER)
HOST ?= localhost:7777
SEED ?= 42

.PHONY: relay fresh join play plain test

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
