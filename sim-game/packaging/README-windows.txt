Assay multiplayer test (Windows 10/11, 64-bit)
==============================================

Three programs:
  Assay.exe       the graphical client, and the quickest way in: press Play
                  solo and it starts a world on this machine and joins it,
                  with nothing to type. It can also join someone else's
                  world. You can walk, mine, assay, craft, place machines and
                  design parts in it.
  sim-relay.exe   the host, for co-op. One person runs it; it owns the world
                  and the clock. Play solo starts one of these for you.
  sim-cli.exe     the text-mode client. Plays the same world through a
                  terminal, and shows far more about it (see "The inspector").

Everyone must use builds made at the same time (Mac and Windows zips from the
same message). Mac and Windows players can share a world.


1. First run
------------
Unzip the folder somewhere (right-click the zip, Extract All). Extract it
properly rather than opening the zip and running from inside it -- the
programs have to sit together in a real folder to find each other.

These programs aren't signed, so Windows may show "Windows protected your
PC" the first time. Click "More info", then "Run anyway". Some antivirus
tools may also ask; allow it.

For the text-mode client you also want a command window: open the folder,
click the address bar, type  cmd  and press Enter.


2. Play on your own
-------------------
Double-click Assay.exe and press Play solo (it is the first button, and
Enter presses it). Nothing to type and no command window needed: it starts
sim-relay.exe from this folder on your own machine and joins it.

It is world 14247, and pressing Play solo again later RESUMES it rather than
starting over. Solo worlds are saved in your user data folder, not in this
one, so they survive replacing this zip with a newer build.


3. Joining someone else's world
-------------------------------
The host gives you an address. Then:

    sim-cli.exe --connect <address>:7777 --name <your name>

Names: 1-20 letters, numbers, - or _. Use the same name next time to get
your character back.

If the host is not on your Wi-Fi, the address only works if the host is
reachable. Easiest: both of you install Tailscale (https://tailscale.com),
the host shares their machine with you (or invites you to their tailnet),
and you connect to the host's Tailscale address (100.x.y.z).


4. Hosting for co-op (optional)
-------------------------------
    sim-relay.exe

If Windows Firewall asks, click Allow access. It prints the address to give
other players. Leave the window open; Ctrl-C stops hosting. The world
autosaves into a "saves" folder next to sim-relay.exe.


The graphical client
--------------------
Double-click Assay.exe. Windows may warn that the publisher is unknown (the
build is not code-signed): More info, then Run anyway.

To play by yourself, press Play solo. To join someone, type the relay's
address in the "host" box -- the same address the relay printed, e.g.
192.168.1.48:7777 -- put in a name, and click join. A bare address uses
port 7777.

It runs the real rules: the same Rust `sim` crate the relay and sim-cli run,
inside the client. Your presses go to the host as commands, and every peer
steps the same simulation, so what you see is the world and not a guess.

What you can do in it:
  click a tile          walk there
  Mine / Stop / Assay   mine the deposit under you, stop, or study it until
                        its property sheet reads exact instead of in bands
  Take / Pick up        empty a building's output into your pack, or take
                        the building back with whatever is inside
  your pack             Fuel and Smelt put ore into a building; Place stands
                        a machine down; Frame and Mount choose the parts of
                        the next machine you design
  the crafting menu     what you can make from what you are carrying

The world view is still a map -- deposits, players, spawn, drawn as shapes
and colours rather than art. Proper art for it is being built now; this is
the part to be rude about.

Worth reporting: it will not start, Play solo fails, it will not connect to
an address sim-cli.exe connects to fine, or what it draws does not match
sim-cli.exe.


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


If a host refuses you
----------------------
A relay refusal names a build by its rules id, a hex string with nothing to
click. That id is not a download link -- it's in VERSION.txt, right beside
this file, which also names the commit it came from. If you're refused: ask
whoever is hosting for their run link and download the same one. Both halves
-- the relay and your zip -- must come from a single CI run.


What to report
--------------
- Any "WARNING: desync" message in the client. That means two players'
  worlds disagreed, which should never happen. Note the tick number and what
  everyone was doing.
- Crashes, disconnects, odd characters on screen, or commands that did
  something unexpected.


Known limits
------------
- The world view is a map of shapes and colours, not finished art.
- Assay.exe is not code-signed, so Windows warns on first run.
- If your connection drops, restart sim-cli.exe to rejoin.
- Your own moves wait for the host, so there's a small delay.
