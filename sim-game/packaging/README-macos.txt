Assay multiplayer test (macOS, Apple Silicon and Intel)
======================================================

Three programs:
  Assay.app   the graphical client, and the quickest way in: press Play solo
              and it starts a world on this machine and joins it, with
              nothing to type. It can also join someone else's world. You can
              walk, mine, assay, craft, place machines and design parts in it.
  sim-relay   the host, for co-op. One person runs it; it owns the world and
              the clock. Play solo starts one of these for you.
  sim-cli     the text-mode client. Plays the same world through a terminal,
              and shows far more about it (see "The inspector").

Everyone must use the files from this same zip.


1. First run on every Mac
-------------------------
Unzip, open Terminal, and go to the unzipped folder, for example:

    cd ~/Downloads/assay-macos

macOS blocks programs downloaded from the internet that aren't from the App
Store or an identified developer. Clear that once, for the WHOLE FOLDER:

    xattr -dr com.apple.quarantine .

Do this even if you only intend to double-click Assay.app. Right-clicking
the app and picking Open approves that one item, and Play solo has to start
the sim-relay file sitting beside it -- which is still blocked, and the app
cannot tell you that precisely yet. The command above covers all of them.


2. Play on your own
-------------------
Double-click Assay.app and press Play solo (it is the first button, and
Enter presses it). Nothing to type and no terminal needed: it starts the
sim-relay from this folder on your own machine and joins it.

It is world 14247, and pressing Play solo again later RESUMES it rather than
starting over. Solo worlds are saved in your user data folder, not in this
one, so they survive replacing this zip with a newer build.


3. Co-op: host the world
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


4. Everyone (host included): join in text mode
----------------------------------------------
In a new Terminal window, in the same folder:

    ./sim-cli --connect <address from the relay> --name <your name>

The host can use:  ./sim-cli --connect localhost:7777 --name <your name>

Names: 1-20 letters, numbers, - or _. Use the same name next time to get
your character back.


5. Or join someone else with the graphical client
-------------------------------------------------
Double-click Assay.app. If macOS still refuses it, see step 1 -- run the
xattr command on the whole folder rather than approving the app on its own,
or Play solo will fail later when it tries to start sim-relay.

Type the relay's address in the "host" box -- the same address the relay
printed, e.g. 192.168.1.48:7777 -- put in a name, and click join. A bare
address uses port 7777. (To play by yourself instead, press Play solo and
ignore the box entirely.)


The graphical client
--------------------
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
an address sim-cli connects to fine, or what it draws does not match what
sim-cli shows.


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
- The world view is a map of shapes and colours, not finished art.
- Assay.app is ad-hoc signed, not notarised, so macOS warns on first open.
- If Play solo says it could not start your own world, step 1's xattr
  command on the whole folder is the usual reason and the usual fix.
- If your connection drops, restart sim-cli to rejoin.
- Your own moves wait for the host, so there's about a tenth of a second
  of delay.
