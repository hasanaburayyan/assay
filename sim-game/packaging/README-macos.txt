Assay multiplayer test (macOS, Apple Silicon and Intel)
======================================================

Three programs:
  sim-relay   the host. One person runs it; it owns the world and the clock.
  sim-cli     the text-mode client, and the one that can actually play:
              mine, craft, place, assay. Everyone can run this.
  Assay.app   the graphical client. Early: it joins, and it draws the world
              it joined. It cannot move or build yet (see "The graphical
              client" below for exactly why).

Everyone must use the files from this same zip.


1. First run on every Mac
-------------------------
Unzip, open Terminal, and go to the unzipped folder, for example:

    cd ~/Downloads/assay-macos

macOS blocks programs downloaded from the internet that aren't from the App
Store or an identified developer. Clear that once:

    xattr -dr com.apple.quarantine .


2. Host: start the relay
------------------------
    ./sim-relay

If macOS asks whether to accept incoming network connections, click Allow.

It prints the exact address to give your friends, like:

    same network:   sim-cli --connect 192.168.1.48:7777 --name <name>

Leave this window open. The world autosaves every 2 seconds into a "saves"
folder next to sim-relay. Ctrl-C stops hosting. Run ./sim-relay again later
to continue the same world.

Options: ./sim-relay 7         host world seed 7 instead of 42
         ./sim-relay --fresh   start world 42 over


3. Everyone (host included): join
---------------------------------
In a new Terminal window, in the same folder:

    ./sim-cli --connect <address from the relay> --name <your name>

The host can use:  ./sim-cli --connect localhost:7777 --name <your name>

Names: 1-20 letters, numbers, - or _. Use the same name next time to get
your character back.


4. Or join with the graphical client
------------------------------------
Double-click Assay.app. If macOS still refuses it, right-click it and pick
Open (step 1's xattr command covers this for the whole folder).

Type the relay's address in the "host" box -- the same address the relay
printed, e.g. 192.168.1.48:7777 -- put in a name, and click join. A bare
address uses port 7777.

It then draws the world it joined: the deposits, the players, spawn. The
status line says which tick it joined at and counts the updates arriving, so
you can see the link is live.

Nothing moves yet, and that is on purpose rather than a bug. The host sends
out the inputs players pressed, not the world itself, so turning those into a
newer world means running the simulation -- the Rust `sim` crate -- inside
this client. Until that is wired in, drawing a guessed position would just be
a second, disagreeing copy of the rules. Use sim-cli to play; use Assay.app
to confirm it joins and draws on your machine.

Worth reporting: it will not start, it will not connect to an address sim-cli
connects to fine, or what it draws does not match what sim-cli shows.


Playing over the internet (not on the same Wi-Fi)
-------------------------------------------------
The relay has to be reachable. Easiest: everyone installs Tailscale
(https://tailscale.com), joins the host's tailnet, and connects to the host's
Tailscale address (100.x.y.z:7777, shown in the Tailscale menu).
Alternative: the host forwards TCP port 7777 on their router to their Mac and
shares their public IP.


The inspector
-------------
sim-cli opens a live view: the map (you are white, other players are
colored, ore patches are colored by mineral species, smelters are
orange), players, every player's inventory, this world's minerals and
their property sheets, the tile under your mouse, placed buildings, nearest
deposits, the inputs applied each tick, and an event console.

Just type commands and press Enter, the same ones as before:
  goto 30 20 · move ne 5 · mine · craft smelter · place smelter · help
Arrow keys walk (hold to keep going). Click a tile to walk there.
Esc clears the line. F1 shows keys. Type quit (or Ctrl-C) to leave.

If the display looks garbled, run with --plain to get the old prompt.
Make the window at least 120 columns by 40 rows for the full layout.

Things to try
-------------
  help                     all commands
  players                  who's here and where
  map                      the world (P = players)
  goto 30 20               walk somewhere; everyone sees you move
  move ne 5                walk 5 tiles north-east
  deposits                 list ore deposits
  species                  this world's minerals: every world rolls its own
  mine                     stand on a deposit first; ore arrives while you stay
                           (only species with hardness 40 or less, by hand)
  craft smelter            5 ore of any species makes a smelter
  place smelter            put it down just east of you
  insert 0 fuel ore:kel 5  fuel it with a reactive ore (inv shows the names)
  insert 0 ore ore:dal 10  ore to refine; the fire must reach its heat tolerance
  take 0                   collect the refined material; craft gear needs hardness 20
  assay                    study the deposit you stand on: exact numbers instead of bands
  rename bok Starterite    name a species you were first to mine or assay
  craft sort ore:bok:c     3 ore become 1 ore a grade better; refined does the same in a smelter
  buildings                what every building holds and whether it's running
  events                   recent events
  quit                     leave (the host keeps running)


What to report
--------------
- Any "WARNING: desync" message in a client, or "DESYNC" in the relay
  window. That means two players' worlds disagreed, which should never
  happen. Note the tick number and what everyone was doing.
- Crashes, disconnects, or commands that did something unexpected.


Known limits
------------
- Playing is text only. The graphical client joins and draws, nothing more.
- Assay.app is ad-hoc signed, not notarised, so macOS warns on first open.
- If your connection drops, restart sim-cli to rejoin.
- Your own moves wait for the host, so there's about a tenth of a second
  of delay.
