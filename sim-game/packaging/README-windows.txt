Assay multiplayer test (Windows 10/11, 64-bit)
==============================================

Two programs:
  sim-relay.exe   the host. One person runs it; it owns the world and the clock.
  sim-cli.exe     the game client (a text-mode inspector). Everyone runs this.

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
- Text only; there are no graphics yet.
- If your connection drops, restart sim-cli.exe to rejoin.
- Your own moves wait for the host, so there's a small delay.
