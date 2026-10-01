Assay multiplayer test (Windows 10/11, 64-bit)
==============================================

Three programs:
  sim-relay.exe   the host. One person runs it; it owns the world and the clock.
  sim-cli.exe     the text-mode client, and the one that can actually play:
                  mine, craft, place, assay. Everyone can run this.
  Assay.exe       the graphical client. Early: it joins, and it draws the
                  world it joined. It cannot move or build yet (see "The
                  graphical client" below for exactly why).

Everyone must use builds made at the same time (Mac and Windows zips from the
same message). Mac and Windows players can share a world.


1. First run
------------
Unzip the folder somewhere (right-click the zip, Extract All).
Open the folder, click the address bar, type  cmd  and press Enter.
A command window opens in that folder.

These programs aren't signed, so Windows may show "Windows protected your
PC" the first time. Click "More info", then "Run anyway". Some antivirus
tools may also ask; allow it.


2. Joining someone else's world
-------------------------------
The host gives you an address. Then:

    sim-cli.exe --connect <address>:7777 --name <your name>

Names: 1-20 letters, numbers, - or _. Use the same name next time to get
your character back.

If the host is not on your Wi-Fi, the address only works if the host is
reachable. Easiest: both of you install Tailscale (https://tailscale.com),
the host shares their machine with you (or invites you to their tailnet),
and you connect to the host's Tailscale address (100.x.y.z).


3. Hosting yourself (optional)
------------------------------
    sim-relay.exe

If Windows Firewall asks, click Allow access. It prints the address to give
other players. Leave the window open; Ctrl-C stops hosting. The world
autosaves into a "saves" folder next to sim-relay.exe.


The graphical client
--------------------
Double-click Assay.exe. Windows may warn that the publisher is unknown (the
build is not code-signed): More info, then Run anyway.

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
a second, disagreeing copy of the rules. Use sim-cli.exe to play; use
Assay.exe to confirm it joins and draws on your machine.

Worth reporting: it will not start, it will not connect to an address
sim-cli.exe connects to fine, or what it draws does not match sim-cli.exe.


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
- Any "WARNING: desync" message in the client. That means two players'
  worlds disagreed, which should never happen. Note the tick number and what
  everyone was doing.
- Crashes, disconnects, odd characters on screen, or commands that did
  something unexpected.


Known limits
------------
- Playing is text only. The graphical client joins and draws, nothing more.
- Assay.exe is not code-signed, so Windows warns on first run.
- If your connection drops, restart sim-cli.exe to rejoin.
- Your own moves wait for the host, so there's a small delay.
