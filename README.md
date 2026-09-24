# The Warriors Auto Splitter (PS2 / PCSX2)

A LiveSplit auto splitter for the USA release of *The Warriors* running in
PCSX2. It splits once per level and works for Any% and 100%. By default it
times each level from control to control, which leaves out the loads and each
level's opening and closing cutscenes. It can also run a classic clock instead:
real time minus loads.

It is a single native `.asl` script. You do not need any other program, and it
does not use PINE. It only **reads** the game's memory and never writes to it.

When it hooks the emulator, it writes
`The Warriors auto splitter v1.0.0 by mostdak1ng` to the debug console, so a
bug report can say exactly which version was running.

## Requirements

- *The Warriors*, USA release: serial `SLUS-21215`, version `1.03`.
- Tested on PCSX2 2.9.80 and LiveSplit 1.8.37.

## Installing

1. Right-click LiveSplit → **Edit Layout** → **+** → **Control** →
   **Scriptable Auto Splitter**.
2. Double-click the new component → **Browse** → pick `TheWarriors.asl`.
3. Leave **Start**, **Split** and **Reset** ticked at the top, and choose the
   script's options below them (see [Settings](#settings)).

By default the script switches LiveSplit to **Game Time** the first time it
finds the game, because that is where it keeps its time. To go
back to Real Time, right-click → **Compare Against** → **Real Time**. LiveSplit
has no keyboard shortcut for this.

## Naming your splits

You do not need a particular split file. Each segment is **bound to a level by
its name**, and the rule is simple: *entering a level moves the timer to that
level's segment*. So the script always knows which level you are in, not just
how many loads you have been through. That is what makes these work: skipped
levels, flashbacks in any order, Armies of the Night stages, and boss splits
that close the right segment.

Names are compared in lower case, ignoring punctuation, spaces and subsplit
markers (`-`, `{Section}`). A segment matches if its name **contains** a level's
name, so prefixes are fine: `01. New Blood`, `A. Roots` and
`{Coney}-Real Live Bunch` all work.

| Level | Names that bind to it |
| --- | --- |
| The 18 story missions | their names: `New Blood`, `Real Live Bunch`, `Payback`, … `Come Out To Play` |
| One particular flashback | its name (`Roots`, `The Best`, `Heavy Muscle`, `Scout's Honor`, `Sharp Dressed Man`) or its letter (`Flashback A` … `Flashback E`) |
| Whichever flashback comes next | `Flashback`, or `Flashback 1` … `Flashback 5` |
| Armies of the Night | `Stage 1` … `Stage 5`, `Armies 1`, `AOTN 1`, `Armies of the Night Stage 1` |
| One particular visit to the hangout | `Hangout 1` … `Hangout 10`, or `Hub 1` … `Hub 10` |
| Any visit to the hangout | `Hangout`, `Hub`, `Coney Island` |

**The five flashbacks can be played in any order.** A segment named after one
flashback binds to that flashback only, and the script sticks to it: if you
list `A. Roots` but start with Heavy Muscle, the run jumps to Heavy Muscle's
segment and the ones in between are marked as skipped. Segments called
`Flashback 1` … `Flashback 5` make no such promise. Each one takes whichever
flashback you play next, so you never have to rename anything mid-run.

**The hangout is numbered by the story checkpoint**, which the game itself puts
in the name of the file it loads. `Hangout N` takes the visit that leads to:

| Hangout | Leads to | | Hangout | Leads to |
| ---: | --- | --- | ---: | --- |
| 1 | Blackout | | 6 | Payin' The Cost |
| 2 | Real Heavy Rep | | 7 | Boys In Blue |
| 3 | Writer's Block | | 8 | Set Up |
| 4 | Adios Amigo | | 9 | All-City |
| 5 | Encore | | 10 | Desperate Dudes |

There is no mandatory hangout visit before Destroyed or after Desperate Dudes.
Writer's Block's mural is painted inside the hangout, so it belongs to
`Hangout 3`. The checkpoint is also what keeps a bail-out from splitting: if
you quit a mission back to Coney, the checkpoint has not moved, so that visit
is one the run has already passed.

A plain `Hangout` segment can only close the segment right before it. Without
that limit, a list with one `Hangout` at the end would jump to it on the first
visit to Coney.

**Any other name binds to no level.** That is how you give the dead time
between two missions a segment of its own (`Load 4`, for example). Two
warnings:

- **They need IL timing**, which is on by default. With the classic clock, the
  run jumps from one mission to the next and marks the segment in between as
  skipped.
- **Keep level names out of them.** A segment is matched by what its name
  contains, so `Profile setup` binds to **Set Up**.

If fewer than half of the segments match a level, the script falls back to
positional mode: one level, one split, in list order. That way a split file
with segments called `1`, `2`, `3` still works. Positional mode also has its
own checkbox, for anyone who prefers it.

## What it does

| When | What happens |
| --- | --- |
| You pick your profile in the main menu | **Start**, when the run's first level starts loading |
| A level is over: its closing cutscene starts | **Split** |
| You enter a level whose segment is further down the list | **Split** the one you played, and mark the ones in between as skipped |
| Hangout, retry from checkpoint, re-entering the same mission | Nothing, unless the hangout has its own segment |
| The boss of a level dies | **Split** that level's segment |
| A level's opening or closing cutscene | Not counted in that level's time |
| A cutscene in the middle of a level | Counted: avoiding it is a time save |
| A loading screen between levels, or a chapter load inside one | Taken out of Game Time |
| The loading screen of a retry from checkpoint | Stays in Game Time: the mistake costs you |
| A trip to the main menu and back | Stays in Game Time |
| The main menu drops a new profile into New Blood | **Reset**, and the run starts again right there |

That is with the default IL timing. With the classic clock, cutscenes count
like everything else, and the split happens when the game commits to the next
level, so the hangout and the walk into the next mission belong to the split
before it.

### Starting and resetting a run

The game's settings are not in the main menu. They are in the pause menu,
during gameplay, and New Blood is the first gameplay a new profile gets. So
starting a run means: create the profile, set the game up from the pause menu
in New Blood, go back to the main menu and pick the profile again. That second
trip into New Blood is the real start.

The script handles this by itself. The timer starts on the first entry, and the
reset fires on the second one, in the same refresh that starts it again, so the
run begins from zero.

Going to the main menu in the middle of a run never resets it. Once a profile
is past New Blood, picking it in the menu leads to the hangout. The exception is
a few missions played for the first time, where it leads back into the mission
itself. Neither of those resets the run.

The timer starts with the first level of **your** list, not necessarily New
Blood. A split file whose first segment is `Blackout` starts when Blackout
loads.

### Bosses

Any% ends when Luther dies in Come Out To Play, and 100% ends when Ghost of
Cyrus dies in Armies of the Night Stage 5. The boss split closes the segment
bound to **that boss's level**, and only if the run is on it. That matters in
100%: Luther can also be fought inside Stage 5, and there he ends nothing.

## Settings

The labels are shortened here; each one starts the same way as in LiveSplit.
`↳` marks an option nested under the one above it.

| Setting | Default | What it does |
| --- | :---: | --- |
| **Start the timer when the run's first level loads** | on | Starts the timer when the game writes the first level, 3.07 s after you confirm the profile. |
| ↳ …as soon as the loading screen appears | off | Starts 0.77 s after you confirm instead. It is off so that every boundary of the run is measured with the same signal. |
| **Split when the game commits to the next level** | on | The level splits. |
| ↳ If levels were skipped, mark the segments that were never played as skipped | on | When it is off, the script takes a single split and stops following the list. |
| ↳ Advance one segment per level and ignore the segment names | off | Positional mode, on request. |
| **Split when the boss of a level dies** | on | Luther and Ghost of Cyrus. |
| ↳ …and end the run there even if segments remain after it | off | For lists that put something after the final boss. |
| ↳ Alternative: split when the boss's level unloads instead | off | A later cut, as a fallback. |
| **Take the loading screens out of Game Time** | on | The switch for both of the script's clocks. Off, Game Time is just real time. See [Game Time](#game-time). |
| ↳ …and switch LiveSplit's timing method to Game Time | on | Switches LiveSplit to Game Time each time the script hooks the emulator. This is the only thing the script writes to LiveSplit. |
| ↳ …except a retry from checkpoint, which stays inside the time | on | A reload you caused, by dying or from the pause menu, costs you. |
| ↳ …and the trip to the main menu and back | on | That trip belongs to the split you are on. |
| ↳ …and time each level from control to control (IL) | on | See [IL timing](#il-timing). Off, the clock is the classic one. |
| ↳ ↳ …and if you bail out of a mission, count every loading screen of that detour | on | See [IL timing](#il-timing). |
| **Reset when a profile drops you into New Blood from the main menu** | on | See [Starting and resetting a run](#starting-and-resetting-a-run). |
| **Write every transition to the debug console** | off | For troubleshooting. |

## Game Time

The script times the run in LiveSplit's Game Time, with one of two clocks:

- **IL timing**, the default: each level counts from control to control. See
  [IL timing](#il-timing).
- **The classic clock**: real time minus loads. Untick **…and time each level
  from control to control (IL)** to use it.

Both take out the same loads, the ones every run has to go through:

- **The loading screen between two levels.**
- **Chapter loads inside a level.** These have no loading screen: a **W**
  blinks in the bottom-right corner for about a second, for example when New
  Blood switches characters. The timer pauses there too.

Two kinds of load stay in the time, because the run chose them. Each has its own
option:

- **A retry from checkpoint**, after dying or from the pause menu. The game
  reloads the whole level. The script tells this apart from a normal level load
  before the pause would start, so nothing has to be corrected afterwards.
- **A trip to the main menu and back**, both loading screens included. It is
  counted in the split that was open.

**Known limitation:** the loading screen is already up about **2.2 s** before
the script sees the game commit to the next level, so those seconds are not
taken out as a load. With the classic clock that adds up to about 45–50 s over
an Any%. With IL timing it only reaches a `Hangout N` or `Load` segment,
because the level's own segment has closed by then. The loading screen could
be detected earlier, but not reliably enough across every level.

## IL timing

On by default. A level's segment runs **from the moment the level hands you the
character to the moment it takes it away for good**:

| Part of the level | Counts? |
| --- | --- |
| Loading | no |
| Opening cutscene | **no**: you do not have control yet |
| Gameplay | yes |
| Cutscenes in the middle | **yes**: avoiding one is a time save, so walking into one costs you |
| Closing cutscene | **no**: the level is over |

A mission's segment opens on the **first control**, not when the level loads.
Whatever comes before it goes to the segment before: `Hangout N` if the game
goes through Coney, or a segment with a non-level name (`Load 4`) if two
missions follow each other directly. That segment keeps all of the dead time
**except the loads**: the closing cutscene, the hangout and the opening
cutscene. With neither kind of segment in the list, that time is not counted
anywhere, and the total is the sum of the levels. A mission only counts the
control you have **in its own level**, so walking around Coney never lands in
the next mission's segment.

The closing cutscene can only be known to be the last one once the level is
over. What you see on screen:

- On eight levels the game warns the script early, when the last stretch
  starts. There the clock simply **stands still** from the moment you lose
  control.
- On the others, the clock keeps running through the closing cutscene and then
  **steps back** to the moment you lost control. Depending on the level, that
  step is somewhere between a tenth of a second and about five seconds.

Either way the recorded split is the same.

Control has to hold for **0.5 s** before it counts. At the end of a level the
game hands control back for a split second between cutscene shots, and those
flickers must not count. The segment still starts at the instant control came
back.

**Bailing out of a mission you already started is paid for.** The segment
follows the classic clock until you have control back in that level, so the
trip to the menu or the hangout counts, and by default so do the loading
screens of that detour, into the hangout and back into the level. Untick
**…count every loading screen of that detour** to leave those two out.

## Troubleshooting

LiveSplit prints the script's messages as debug output. To read them, run
[DebugView](https://learn.microsoft.com/sysinternals/downloads/debugview) and
look for lines starting with `[TheWarriors]`. For much more detail, turn on
**Write every transition to the debug console**.

- **The timer never starts and nothing complains.** Check whether two PCSX2
  windows are open. LiveSplit hooks the PCSX2 that was started **last**, and
  if that one also has the game loaded, the script watches a session nobody is
  playing. When there is more than one PCSX2, the script lists them all in the
  debug output and marks the one it hooked.
- **Splits land on the wrong segments.** When the script hooks, it prints how
  many segments matched a level (`18/18 segments match a level by name`), and
  whether it fell back to positional mode. Check the names against
  [Naming your splits](#naming-your-splits).
- **The script's options are missing and Start/Split/Reset are greyed out.**
  LiveSplit could not compile the script, and it does not show the error
  anywhere. That only happens to an edited copy: download it again.
- **Loading a save state is a level change like any other.** If the state is in
  a later level, the run splits to it.

## How it works

Everything comes from a few fixed addresses in the game's memory: the token
of the loaded level, the path of the last file the game asked for, the level's
own clock, and the byte the engine checks before it lets the player's character
take input. PCSX2 maps the emulated RAM at a different address every time it
starts, so the script finds it by the two signature strings. The addresses,
and the reasoning behind every rule above, are documented in the comments of
`TheWarriors.asl`.

## License

Copyright (C) 2026 mostdak1ng.

Licensed under the GNU General Public License version 3 only. See `LICENSE`.
