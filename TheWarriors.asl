// The Warriors (PS2, USA SLUS-21215 v1.03) on PCSX2 -- one split per level.
//
// The Warriors auto splitter v1.0.0 by mostdak1ng - GPL-3.0-only
// Copyright (C) 2026 mostdak1ng. See LICENSE.
//
// Every segment of the run is bound to a level by its name, and a split closes
// the segment whose level the game just left. That is what lets the splitter
// survive a skipped level, an out-of-order flashback, and a split list that is
// not the 18 story missions.
//
// Where everything comes from (read only; the script never writes to the game):
//
//   0x0051489C            pointer to the game manager (0x01FD8400 during play)
//   manager + 0x124       token of the loaded level: "level99", "level80", ...
//   manager + 0x134       LEVELNAME[current level], e.g. "3:East Coney"
//   0x005DE240            path of the last requested asset
//   0x0065A68C            level clock, in milliseconds: it freezes at the
//                         value of the level being left, goes to 0 while the
//                         next one loads, and counts again once it is playable
//   0x0054B668            "cdrom0:\SLUS_212.15;1"   <- signature, identifies the game
//   0x00588560            "cdrom0:\WARRIORS.WAD;1"  <- signature, identifies the game
//
// For the boss splits, the actor array:
//   0x0063FEE0            array of Human, stride 0x6D0
//   actor + 0x00D0        char id (79 = Luther, 63 = Ghost of Cyrus)
//   actor + 0x00D4        pointer to stats
//   stats + 0x0144        current health (s16); +0x146 the maximum
//
// The level table is the game's own: MISSIONNAME and LEVELNAME, the gstring
// tables in Lua entry 3775 of WARRIORS.WAD. The token is the key because it
// does not depend on the language of the disc; the label is for display. The
// 18 story tokens are cross-checked against 147 save states: one token per
// mission, the same in every checkpoint.
//
// PCSX2 maps the 32 MB of EE RAM at a different address every time it starts,
// so the script walks the process pages and keeps the one that has both
// signatures in place.

state("pcsx2-qt")      { byte attach : 0x0; }
state("pcsx2-qtx64")   { byte attach : 0x0; }
state("pcsx2x64-avx2") { byte attach : 0x0; }
state("pcsx2x64")      { byte attach : 0x0; }
state("pcsx2")         { byte attach : 0x0; }

startup
{
    refreshRate = 120;

    settings.Add("start", true, "Start the timer when the run's first level loads");
    // Off by default: with the token, all the boundaries of the run are
    // measured with the same signal. On, it starts +0.77 s after
    // the X; off, +3.07 s, which is when the level actually starts loading.
    settings.Add("startEarly", false, "...as soon as the loading screen appears (+0.77 s after X) instead of with the level token (+3.07 s)", "start");

    settings.Add("split", true, "Split when the game commits to the next level");
    settings.Add("catchUp", true, "If levels were skipped, mark the segments that were never played as skipped", "split");
    // Matching segments to levels by name is what makes a skipped level, an
    // out-of-order flashback and a knife on the right segment possible. But
    // "one level, one segment, in the order I listed them" is a legitimate way
    // to keep splits, not a degraded mode, so it can be asked for outright.
    settings.Add("positionalMode", false, "Advance one segment per level and ignore the segment names", "split");

    settings.Add("final", true, "Split when the boss of a level dies (Luther, Ghost of Cyrus)");
    settings.Add("finalEndsRun", false, "...and end the run there even if segments remain after it", "final");
    settings.Add("finalUnload", false, "Alternative: split when the boss's level unloads instead", "final");

    settings.Add("gameTime", true, "Take the loading screens out of Game Time");
    // LiveSplit shows these with the TreeView's own tooltip, which pops after
    // 5 s and cannot be told otherwise from here: keep them readable in 5 s.
    settings.SetToolTip("gameTime",
        "Real time minus the loads the game makes you do: a level, a chapter.");
    // Its own setting because it is the one thing here that writes to
    // LiveSplit instead of reading the game, and the label has to say so: the
    // script is the one switching, not a note telling you to.
    settings.Add("gameTimeSwitch", true, "...and switch LiveSplit's timing method to Game Time", "gameTime");
    settings.SetToolTip("gameTimeSwitch",
        "LiveSplit shows one clock. Set when the emulator is hooked; right-click > Compare Against to change.");
    // A load the game HAD to do is not the same as one you caused. The level
    // transitions and the chapter loads come out of Game Time because every
    // run pays for them; reloading a checkpoint after dying is a mistake, and
    // a mistake that pauses the clock is free. The two are told apart by the
    // level bootstrap -- see the update block -- so this is a real choice and
    // not a wish: untick it and the clock behaves exactly as it did before.
    settings.Add("retryCounts", true, "...except a retry from checkpoint, which stays inside the time", "gameTime");
    settings.SetToolTip("retryCounts",
        "Dying and reloading costs you. A level load or a chapter load still does not.");
    // Same idea, other direction: the main menu is not a load the run waits
    // through, it is somewhere the run went. You get there from the hangout or
    // from a mission and you come back to the same place, so the whole trip --
    // both loading screens and the time spent picking the profile -- belongs to
    // the segment that was open. New Blood is the exception: that trip is the
    // start of the run, and the reset owns it.
    settings.Add("menuCounts", true, "...and the trip to the main menu and back, which belongs to the split you are on", "gameTime");
    settings.SetToolTip("menuCounts",
        "You went there; the run did not wait for it. Except into New Blood, which starts a run.");
    // IL timing, on by default. Unticked, the clock is the classic one -- real
    // time minus loads -- exactly as it always was.
    // A level's segment runs from the moment the level hands you the
    // character to the moment it takes it away for good, so the cutscene it
    // opens with and the one it closes with are not in it -- but every
    // cutscene in between is, because walking into one has to cost you.
    settings.Add("ilTime", true, "...and time each level from control to control (IL): its opening and closing cutscenes do not count", "gameTime");
    settings.SetToolTip("ilTime",
        "The clock never stops mid-level: a cutscene you walked into costs you.");
    // Bailing out of a mission already under way is a mistake and it is paid
    // for: that segment follows the classic clock until you have control back
    // in its level (update block, "detour"). The classic clock still takes out
    // the transition loads of that trip -- into the hangout, back into the
    // level -- and whether those should count too is a matter of taste, so
    // both are on offer. On by default: the whole detour is the mistake.
    settings.Add("detourLoadsCount", true, "...and if you bail out of a mission, count every loading screen of that detour, the one back into the level too", "ilTime");
    settings.SetToolTip("detourLoadsCount",
        "Off: loads into the hangout and back into the level come out. On: all counts.");

    // Not "when the game returns to the main menu": going to the main menu is
    // something a run can legitimately do and come back from, and it lands in
    // the hangout or in the mission you were on. The one trip that is really a
    // new attempt is the one that ends in New Blood, because the only way to
    // get there from the menu is the profile you just made.
    settings.Add("reset", true, "Reset when a profile drops you into New Blood from the main menu");
    settings.SetToolTip("reset",
        "That is a new profile: the run starts there. Any other menu trip keeps the run.");
    settings.Add("verbose", false, "Write every transition to the debug console");

    // Keep only letters and digits, and drop the subsplit markers first, so
    // "{Coney}-Real Live bunch" and "Real Live Bunch" land on the same key.
    vars.Normalize = (Func<string, string>)(raw =>
    {
        if (string.IsNullOrEmpty(raw)) return "";
        string s = raw;
        int brace = s.IndexOf('}');
        if (s.StartsWith("{") && brace > 0) s = s.Substring(brace + 1);
        s = s.TrimStart('-', ' ');
        var sb = new System.Text.StringBuilder();
        foreach (char c in s.ToLowerInvariant())
            if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) sb.Append(c);
        return sb.ToString();
    });

    // token -> { mission name, LEVELNAME label, category }
    vars.Levels = new Dictionary<string, string[]>
    {
        { "level99",  new[] { "New Blood",             "1:Coney",            "story"     } },
        { "level80",  new[] { "Real Live Bunch",       "2:Coney",            "story"     } },
        { "level87",  new[] { "Payback",               "3:East Coney",       "story"     } },
        { "level34",  new[] { "Blackout",              "4:Riverside",        "story"     } },
        { "level2",   new[] { "Real Heavy Rep",        "5:Tremont",          "story"     } },
        { "level3",   new[] { "Writer's Block",        "6:Soho",             "story"     } },
        { "level5",   new[] { "Adios Amigo",           "7:East Harlem",      "story"     } },
        { "level81",  new[] { "Encore",                "8:Coney",            "story"     } },
        { "level86",  new[] { "Payin' The Cost",       "9:Coney",            "story"     } },
        { "level93",  new[] { "Destroyed",             "10:East Coney",      "story"     } },
        { "level31",  new[] { "Boys In Blue",          "11:Pelham",          "story"     } },
        { "level14",  new[] { "Set Up",                "12:Bensonhurst",     "story"     } },
        { "level9",   new[] { "All-City",              "13:Trainyard",       "story"     } },
        { "level51",  new[] { "Desperate Dudes",       "14:Gunhill",         "story"     } },
        { "level52",  new[] { "No Permits, No Parley", "15:Tremont",         "story"     } },
        { "level54",  new[] { "Home Run",              "16:Riverside",       "story"     } },
        { "level55",  new[] { "Friendly Faces",        "17:Bowery",          "story"     } },
        { "level84",  new[] { "Come Out To Play",      "18:Coney",           "story"     } },
        { "level82",  new[] { "Roots",                 "A:East Coney",       "flashback" } },
        { "level92",  new[] { "The Best",              "B:Coney",            "flashback" } },
        { "level83",  new[] { "Heavy Muscle",          "C:East Coney",       "flashback" } },
        { "level20",  new[] { "Scout's Honor",         "D:Chinatown",        "flashback" } },
        { "level11",  new[] { "Sharp Dressed Man",     "E:Harlem",           "flashback" } },
        { "level60",  new[] { "Stage 1",               ":Brooklyn",          "armies"    } },
        { "level61",  new[] { "Stage 2",               ":Lower Manhattan",   "armies"    } },
        { "level62",  new[] { "Stage 3",               ":Harlem",            "armies"    } },
        { "level63",  new[] { "Stage 4",               ":The Bronx",         "armies"    } },
        { "level64",  new[] { "Stage 5",               ":Upper West Side",   "armies"    } },
        { "level95",  new[] { "Hangout",               ":Coney",             "hub"       } },
    };
    // level100 is the main menu. It is deliberately not a level: the reset rule
    // owns it, and nothing should ever bind a segment to it.
    vars.MENU = "level100";
    vars.HUB = "level95";
    // New Blood, which the reset rule owns. The game's settings are not in the
    // main menu: they are in the pause menu, during gameplay, and New Blood is
    // the first gameplay a new profile gets. So starting a run IS "make a
    // profile, get dropped into New Blood, set it up from the pause menu, go
    // back to the menu, pick the profile again". That second entry is the
    // start of the run, and it is the only way the main menu hands you New
    // Blood -- quitting to the menu from a mission returns you to the mission
    // only the FIRST time you play it, and every other trip lands in Coney.
    vars.FIRST = "level99";

    // The five flashbacks of a 100% can be played in any order -- the game
    // asks for no particular one -- so a segment can be bound to "whichever
    // flashback comes next" instead of to one of them. That is what a segment
    // called "Flashback", or "Flashback 1" ... "Flashback 5", binds to: this
    // token, which is not a level and can never collide with one.
    //
    // The name is what makes it honest. "Flashback 3" never promised to be
    // Roots, so holding Heavy Muscle is not a lie and nothing has to be
    // renamed while the run is going. Calling them "A. Roots" ... "E. Sharp
    // Dressed Man" is the opposite promise, and the script keeps it: those
    // bind to their own flashback and to no other.
    vars.ANYFLASH = "flashback*";

    // The hangout is not one level, it is twelve. Its Main reads the story
    // checkpoint and preloads "level95_chapter" .. that number, so the game
    // itself says which visit this is -- and that is the only thing telling the
    // mandatory stop before Blackout from the one before Set Up, or from simply
    // bailing out of a mission back to Coney. The destination of each is the
    // game's own fRunMission table: 1 Blackout, 2 Real Heavy Rep, 3 Writer's
    // Block, 4 Adios Amigo, 5 Encore, 6 Payin' The Cost, 7 Boys In Blue,
    // 8 Set Up, 9 All-City, 10 Desperate Dudes. 11 and 12 have no destination
    // there, which is why a route ends without them.
    //
    // The mural of Writer's Block lives inside chapter 3: you paint it in the
    // hub, before level3 ever loads, so it belongs to "Hangout 3" and not to
    // the mission. That is where the game puts it, not a choice made here.
    for (int n = 1; n <= 12; n++)
        vars.Levels[(string)vars.HUB + "#" + n] =
            new[] { "Hangout " + n, ":Coney", "hub" };

    // The boss whose death ends a level, as level token -> char id. Both die at
    // health exactly 1, not 0: that is how this engine marks a scripted boss
    // death, and the health sits there for a moment before the actor is
    // destroyed (0.49 s for Luther, 2.27 s for Cyrus).
    //
    // It has to be the PAIR. Char 79, "Luther", also exists and is fightable
    // inside AOTN Stage 5 -- one of the save states has him at 180/3000 -- so
    // watching the char id alone would end a 100% run halfway through.
    vars.Bosses = new Dictionary<string, int>
    {
        { "level84", 79 },  // Luther, the one with the bottles: ends an Any%
        { "level64", 63 },  // Ghost of Cyrus, AOTN Stage 5: ends a 100%
    };

    // The asset the closing cutscene of a level asks for. It is the only thing
    // that says, AT THE MOMENT IT HAPPENS, that the control you just lost was
    // the last one of the level: the capture of 2026-09-21 diffed the manager
    // (+0x100..+0x260) and the 44 bytes of the control block while a whole
    // level was played, and at that instant NOTHING else in either moved.
    //
    // It has to be per level because the closing chapter is not the last one by
    // number: Blackout closes with c2 and plays c3 and c4 in the middle. Each
    // entry is one capture, and it survives skipping: Blackout's was measured
    // on a run that skipped every cutscene, and the asset arrived anyway.
    //
    // The 18 story missions were captured on 2026-09-21, one save state near
    // the end of each. 14 of them ask for something; the delay is in the
    // comment, and 10 of the 14 are under 1.1 s.
    //
    // A level with no entry keeps the old cut, when the next level starts
    // loading. The time is the same either way -- the clock has already given
    // that stretch back -- so what an entry buys is WHERE the split is seen.
    vars.LevelOver = new Dictionary<string, string>
    {
        { "level80", "l80_c3aa.scn"  },   // Real Live Bunch,       0.75 s
        { "level87", "l87_c2_a.pak"  },   // Payback,               1.08 s
        { "level34", "l34_c2.pak"    },   // Blackout,              0.07 s
        { "level2",  "l2_c6_baa.scn" },   // Real Heavy Rep,        0.64 s
        { "level3",  "l3_c7aa.scn"   },   // Writer's Block,        4.44 s
        { "level5",  "l5_c3aa.scn"   },   // Adios Amigo,           2.27 s
        { "level81", "l81_out_sub.scn" }, // Encore,                2.57 s
        { "level31", "l31_c4.pak"    },   // Boys In Blue,          0.07 s
        { "level14", "l14_c2.pak"    },   // Set Up,                0.54 s
        { "level51", "l51_c2.pak"    },   // Desperate Dudes,       0.37 s
        { "level52", "l52_c2.pak"    },   // No Permits, No Parley, 2.51 s
        { "level54", "l54_c3_b.pak"  },   // Home Run,              0.10 s
        { "level55", "l55_c6.pak"    },   // Friendly Faces,        0.10 s
        { "level84", "l84_c7.pak"    },   // Come Out To Play,      0.10 s
        { "level82", "l82_c5.pak"    },   // Roots,                 0.10 s
        { "level83", "l83_c5.pak"    },   // Heavy Muscle,          0.10 s
        { "level20", "l20_c2.pak"    },   // Scout's Honor,         0.10 s
        { "level92", "l92_c4aa.scn"  },   // The Best,              1.52 s
        // No entry, because their closing cutscene asks for NOTHING -- it is
        // all resident already, and the next thing to load is the hangout,
        // 9 to 20 s later: New Blood, Payin' The Cost, Destroyed, All-City and
        // Sharp Dressed Man. The mission state closes them instead (update
        // block), with the same recorded time.
        //
        // Nor the five stages of Armies of the Night: none of them has a
        // closing cutscene. A stage ends and the next one loads.
    };

    // The scene of the chapter the closing cutscene belongs to. The game asks
    // for it when the level's LAST stretch begins -- before the last control,
    // not after -- so from that request on, the next time the character is
    // taken away is the end of the level.
    //
    // It only changes what the clock SHOWS. Without it the closing cutscene
    // runs on the clock until the level is known to be over and then the
    // clock jumps back -- 11 s in All-City, whose closing cutscene asks for
    // nothing. With it the clock stands still from the moment control goes.
    // No recorded time changes either way: what is held back is exactly what
    // the level gives back when it closes. And if a stretch ever had another
    // cutscene nobody captured, the clock would stand still through it and
    // then jump forward, with the same time as always.
    //
    // Only where it shows (1.5 s or more from the last control to the cut) and
    // where the capture has no other control loss after the scene. That is
    // what leaves Sharp Dressed Man out: its c8 has three more cutscenes.
    // The first figure is how long before the last control the scene arrived.
    vars.ClosingStretch = new Dictionary<string, string>
    {
        { "level9",  "l9_c4.scn"  },   // All-City,              202.65 s, hides 11.04 s
        { "level99", "l99_c9.scn" },   // New Blood,               8.54 s, hides  5.35 s
        { "level52", "l52_c2.scn" },   // No Permits, No Parley,   0.68 s, hides  2.51 s
        { "level93", "l93_c3.scn" },   // Destroyed,             119.05 s, hides  2.37 s
        { "level5",  "l5_c3.scn"  },   // Adios Amigo,             8.81 s, hides  2.27 s
        { "level86", "l86_c4.scn" },   // Payin' The Cost,         6.91 s, hides  2.24 s
        { "level92", "l92_c4.scn" },   // The Best,               63.19 s, hides  1.52 s
        // Real Live Bunch has a closing asset of its own, but how long it
        // takes to arrive changes from run to run: 0.75 s in its capture,
        // 2.07 s in the long run. Its scene came 44.9 s and 48.1 s before.
        { "level80", "l80_c3.scn" },   // Real Live Bunch,        44.90 s, hides  2.07 s
    };

    // A segment matches a level when its normalized name CONTAINS one of the
    // level's keys, longest key first so the most specific level wins. Contains
    // and not equals, because real split lists carry prefixes: "01. New Blood",
    // "A. Roots", "Armies of the Night Stage 1".
    var keys = new List<KeyValuePair<string, string>>();
    var flashbacks = new HashSet<string>();
    foreach (var pair in vars.Levels)
    {
        string token = pair.Key;
        string[] info = pair.Value;
        keys.Add(new KeyValuePair<string, string>((string)vars.Normalize(info[0]), token));
        if (info[2] == "flashback") flashbacks.Add(token);

        if (info[2] == "flashback")
        {
            // "Flashback A" carries no mission name at all.
            string letter = info[1].Substring(0, 1).ToLowerInvariant();
            keys.Add(new KeyValuePair<string, string>("flashback" + letter, token));
        }
        else if (info[2] == "armies")
        {
            // "Stage 3", "Armies 3", "AOTN 3", "Armies of the Night Stage 3".
            string n = info[0].Substring(info[0].Length - 1);
            keys.Add(new KeyValuePair<string, string>("armies" + n, token));
            keys.Add(new KeyValuePair<string, string>("aotn" + n, token));
            keys.Add(new KeyValuePair<string, string>("night" + n, token));
        }
        else if (info[2] == "hub")
        {
            int hash = token.IndexOf('#');
            if (hash < 0)
            {
                // Not bare "coney": that is a substring of "East Coney" and of
                // half the location labels in the game.
                keys.Add(new KeyValuePair<string, string>("hub", token));
                keys.Add(new KeyValuePair<string, string>("coneyisland", token));
            }
            else
            {
                // "Hangout 3", "Hub 3". The name key above already covers
                // "hangout3"; sorting by length is what keeps "hangout1" from
                // eating "Hangout 10".
                keys.Add(new KeyValuePair<string, string>(
                    "hub" + token.Substring(hash + 1), token));
            }
        }
    }
    // The wildcard, added once and not per level. It is the shortest of the
    // flashback keys, and sorting by length is what makes that work:
    // "flashbacka" wins over "flashback" on "Flashback A", so the letters keep
    // their exact binding and only "Flashback", "Flashback 1", ... fall
    // through to the wildcard.
    keys.Add(new KeyValuePair<string, string>("flashback", (string)vars.ANYFLASH));

    keys.Sort((a, b) => b.Key.Length.CompareTo(a.Key.Length));
    vars.Keys = keys;

    vars.TokenForName = (Func<string, string>)(name =>
    {
        string norm = vars.Normalize(name);
        if (norm.Length == 0) return null;
        foreach (var entry in (List<KeyValuePair<string, string>>)vars.Keys)
            if (norm.Contains(entry.Key)) return entry.Value;
        return null;
    });

    // A segment bound to a numbered hangout takes that hub checkpoint and no
    // other. One bound to the plain hangout takes any of them, which is what
    // keeps a list with a single "Hangout" segment working as it always did.
    // A wildcard segment takes any of the five flashbacks; which one it ends
    // up holding is decided in update, and only there.
    string hub = (string)vars.HUB;
    string anyFlash = (string)vars.ANYFLASH;
    vars.Matches = (Func<string, string, bool>)((segToken, levelId) =>
    {
        if (segToken == null || levelId == null) return false;
        if (segToken == levelId) return true;
        if (segToken == anyFlash) return flashbacks.Contains(levelId);
        return segToken == hub && levelId.StartsWith(hub);
    });

    // Is this level one of the five? Used by onStart, where there is no
    // matching to piggyback on.
    vars.IsFlashback = (Func<string, bool>)(levelId =>
        levelId != null && flashbacks.Contains(levelId));

    // "./ee_files/level95_chapter3.lua" -> 3, anything else -> 0.
    vars.HubChapterOf = (Func<string, int>)(path =>
    {
        const string mark = "level95_chapter";
        int at = path.IndexOf(mark);
        if (at < 0) return 0;
        int i = at + mark.Length, value = 0, digits = 0;
        while (i < path.Length && path[i] >= '0' && path[i] <= '9')
        {
            value = value * 10 + (path[i] - '0');
            i++; digits++;
        }
        return digits > 0 ? value : 0;
    });

    vars.LevelName = (Func<string, string>)(token =>
    {
        if (token != null && vars.Levels.ContainsKey(token))
            return ((string[])vars.Levels[token])[0] + " (" + ((string[])vars.Levels[token])[1] + ")";
        return token == (string)vars.MENU ? "main menu" : token;
    });
}

init
{
    vars.ee = IntPtr.Zero;
    vars.ticks = 0;
    vars.model = null;

    vars.token = "";      vars.prevToken = "";
    vars.levelId = "";    vars.prevLevelId = "";
    vars.hubChapter = 0;
    vars.asset = "";      vars.prevAsset = "";
    vars.bossHp = -1;     vars.prevBossHp = -1;
    vars.bossSlot = -1;
    vars.assetTick = 0;
    vars.menuTick = -1000000;   // "long ago": we do not know when the menu opened
    vars.loadScreenStart = false;

    // The load window. frozenClock is the value the clock has to move away
    // from for the load to be over.
    vars.clock = (uint)0;
    vars.frozenClock = (uint)0;
    vars.loading = false;
    vars.wasLoading = false;
    vars.loadStartMs = 0;
    // Is the load that is opening one the player caused? Decided before the
    // window opens, by the level bootstrap arriving with the token still put.
    vars.retryLoad = false;
    vars.tokenTick = -1000000;
    vars.pauseNow = false;
    // Is this load window a trip to the main menu? Known when it opens, like
    // the one above: the token says where you are going.
    vars.menuLoad = false;
    vars.timingSwitched = false;

    // Control of the character, for IL timing. It starts as "yes" and keeps
    // its last value whenever the chain cannot be read, so the worst a failed
    // read can do is let Game Time run.
    vars.control = true;
    vars.ownsGameplay = true;

    // IL timing keeps its own clock (the gameTime block below), because what
    // it has to do cannot be done by pausing: the time of the LAST cutscene of
    // a level is taken away once the level is over, and until then nobody
    // knows which cutscene that was.
    vars.realPrev = -1.0;      // timer.CurrentTime.RealTime, in seconds
    vars.counted = 0.0;        // what the clock shows
    vars.pending = 0.0;        // counted, but taken back if the level ends now
    vars.holdTime = 0.0;       // how long control has been held, uninterrupted
    vars.seenControl = false;  // has the level handed the character over yet
    vars.startedSeg = -1;      // the segment that has had control in its level
    vars.bailed = false;       // ...and that you bailed out of (see update)
    vars.levelOver = false;    // its closing cutscene has started
    vars.levelOverSplit = false;
    // The level's last stretch: its ClosingStretch scene was requested (seen)
    // and control was solid after that (armed). While armed, and once the
    // level is over, `pending` is kept off the clock that is shown.
    vars.stretchSeen = false;
    vars.stretchArmed = false;
    vars.hidePending = false;
    vars.prevMission = 0;      // manager + 0x14C, the mission state
    vars.deferred = -1;        // the segment waiting for the first control

    // Segment binding, rebuilt whenever the loaded run changes.
    vars.segToken = new List<string>();
    vars.bound = 0;
    vars.autoPositional = true;  // until a run with recognisable names is loaded
    vars.positional = true;      // autoPositional, or the setting asking for it
    vars.runSignature = "";

    // Where the timer is being driven to. splitPlayed is the one segment that
    // was really played; anything between it and splitTarget was skipped.
    vars.splitPlayed = -1;
    vars.splitTarget = -1;
    vars.endingRun = false;
    vars.enteredIdx = -1;
    vars.enteredFirst = false;
    vars.startAt = 0;          // the segment the run really starts on

    // Which wildcard segment is holding which flashback. One pair is enough:
    // only the segment the run is standing on can still be claimed, and every
    // one before it was closed by a split.
    vars.wildAt = -1;
    vars.wildToken = "";

    // Only used by the positional fallback, to keep its old guarantees.
    vars.lastLevel = "";
    vars.bestStory = 0;

    vars.FindBoss = (Func<IntPtr, int, int>)((ee, charId) =>
    {
        for (int slot = 0; slot < 64; slot++)
            if (game.ReadValue<int>(ee + 0x0063FEE0 + slot * 0x6D0 + 0xD0) == charId)
                return slot;
        return -1;
    });

    // The loading screen is three 263680-byte textures the game requests by
    // hash, so they arrive as an all-digits name. They show up ~2.1 s before
    // the level token is written, and they are the first thing that moves when
    // you confirm the profile.
    vars.IsLoadScreen = (Func<string, bool>)(path =>
    {
        int slash = path.LastIndexOf('/');
        string name = slash >= 0 ? path.Substring(slash + 1) : path;
        if (name.Length < 5) return false;
        foreach (char c in name)
            if (c < '0' || c > '9') return false;
        return true;
    });

    // Both signatures have to sit at their exact offset inside the region.
    vars.Valid = (Func<IntPtr, bool>)(b =>
           game.ReadString(b + 0x0054B668, ReadStringType.ASCII, 24, "") == "cdrom0:\\SLUS_212.15;1"
        && game.ReadString(b + 0x00588560, ReadStringType.ASCII, 24, "") == "cdrom0:\\WARRIORS.WAD;1");

    vars.Find = (Func<IntPtr>)(() =>
    {
        var seen = new HashSet<long>();
        foreach (var page in game.MemoryPages(true))
        {
            if (page.State != MemPageState.MEM_COMMIT) continue;
            if (page.Protect != MemPageProtect.PAGE_READWRITE) continue;
            if (page.Type == MemPageType.MEM_IMAGE) continue;
            if (page.RegionSize.ToUInt64() < 0x100000UL) continue;

            // PCSX2 reserves the 32 MB in one go but commits the pages with
            // different protections, so the region Windows enumerates usually
            // starts after byte 0 of the EE RAM. The real base is the one of
            // the reservation; try both.
            foreach (var candidate in new[] { page.AllocationBase, page.BaseAddress })
            {
                if (candidate == IntPtr.Zero) continue;
                if (!seen.Add(candidate.ToInt64())) continue;
                if (vars.Valid(candidate)) return candidate;
            }
        }
        return IntPtr.Zero;
    });

    // Bind every segment of the loaded run to a level, by name. Cheap enough
    // (a few dozen short strings) to just redo whenever the run changes.
    vars.Rebind = (Action)(() =>
    {
        var tokens = new List<string>();
        int bound = 0;
        for (int i = 0; i < timer.Run.Count; i++)
        {
            string token = vars.TokenForName(timer.Run[i].Name);
            tokens.Add(token);
            if (token != null) bound++;
        }
        vars.segToken = tokens;
        vars.bound = bound;

        // Safety net: somebody else's split file may have the segments called
        // "1", "2", "3". Unless most of the run is recognisable, fall back to
        // the positional behaviour, which is what the splitter did before
        // level identity existed.
        vars.autoPositional = !(bound >= 1 && bound * 2 >= timer.Run.Count);
        print("[TheWarriors] " + bound + "/" + timer.Run.Count
              + " segments match a level by name");
    });

    // Which PCSX2 this is, and whether it is the only one.
    //
    // LiveSplit picks the game process by name and keeps the one that started
    // LAST -- ASLScript.TryConnect does GetProcessesByName(name)
    // .OrderByDescending(p => p.StartTime).FirstOrDefault(p => !p.HasExited).
    // So a second PCSX2 opened afterwards silently wins the attachment, and if
    // that one also has the disc loaded, the EE RAM is found there and the
    // splitter quietly watches a session nobody is playing: no error anywhere,
    // the timer simply never starts. It cost a debugging session once, and the
    // script cannot choose for itself, so the least it can do is say so.
    //
    // These are the same names as the state() blocks at the top of the file:
    // if one is added there, add it here too.
    // Every process property here can throw on a process we are not allowed to
    // open, and this runs in init: an exception would take the whole script
    // down. A thing that only reports must never be able to break what it
    // reports on, so all of it is defensive.
    vars.Describe = (Func<Process, string>)(process =>
    {
        string detail = "pid " + process.Id;
        try { detail += "  started " + process.StartTime.ToString("HH:mm:ss"); }
        catch { }
        try { detail += "  " + process.MainModule.FileName; }
        catch { detail += "  (path unavailable)"; }
        return detail;
    });

    // The version goes in every log, so a bug report says which script it was.
    print("[TheWarriors] The Warriors auto splitter v1.0.0 by mostdak1ng");
    print("[TheWarriors] script loaded, attached to " + vars.Describe(game));

    try
    {
        var others = new List<Process>();
        foreach (string name in new[] { "pcsx2-qt", "pcsx2-qtx64", "pcsx2x64-avx2",
                                        "pcsx2x64", "pcsx2" })
            foreach (var candidate in Process.GetProcessesByName(name))
            {
                try { if (candidate.HasExited) continue; }
                catch { }              // cannot ask: assume it is alive
                others.Add(candidate);
            }

        if (others.Count > 1)
        {
            print("[TheWarriors] WARNING: " + others.Count + " PCSX2 processes"
                  + " are running and LiveSplit took the one that started LAST."
                  + " If that is not the one you are playing, close the others:"
                  + " the timer will never start, and nothing else will"
                  + " complain.");
            foreach (var candidate in others)
                print("[TheWarriors]   "
                      + (candidate.Id == game.Id ? "-> " : "   ")
                      + vars.Describe(candidate));
        }
    }
    catch (Exception error)
    {
        print("[TheWarriors] could not list the PCSX2 processes: " + error.Message);
    }

    print("[TheWarriors] looking for PCSX2's EE RAM");
}

update
{
    vars.ticks = (int)vars.ticks + 1;

    if ((IntPtr)vars.ee == IntPtr.Zero)
    {
        // Walking the process pages costs ~100 ms and the game may not be
        // running yet: retry every 2 s, not on every refresh.
        if ((int)vars.ticks % 240 != 0) return false;
        vars.ee = vars.Find();
        if ((IntPtr)vars.ee == IntPtr.Zero) return false;
        print("[TheWarriors] EE RAM at 0x" + ((IntPtr)vars.ee).ToString("X"));

        // Once per attach, not every refresh: removing the loads is pointless
        // if the layout is showing Real Time, but flipping it back on every
        // tick would take the choice away from whoever wants Real Time up.
        if (!(bool)vars.timingSwitched)
        {
            vars.timingSwitched = true;
            // Fully qualified like the TimerModel below, for one convention.
            if (settings["gameTime"] && settings["gameTimeSwitch"]
                && timer.CurrentTimingMethod != LiveSplit.Model.TimingMethod.GameTime)
            {
                timer.CurrentTimingMethod = LiveSplit.Model.TimingMethod.GameTime;
                print("[TheWarriors] LiveSplit set to Game Time (loads removed)");
            }
        }
    }
    else if ((int)vars.ticks % 600 == 0 && !vars.Valid((IntPtr)vars.ee))
    {
        print("[TheWarriors] lost the EE RAM (emulator reset?), rescanning");
        vars.ee = IntPtr.Zero;
        return false;
    }

    IntPtr ee = (IntPtr)vars.ee;

    // Rebind when the loaded run changes. The signature is cheap and catches a
    // renamed segment as well as a different split file.
    if ((int)vars.ticks % 120 == 0 || (string)vars.runSignature == "")
    {
        string signature = timer.Run.Count.ToString();
        // Length-prefixed so that two different lists cannot build the same
        // signature, without needing a separator character that a segment name
        // could itself contain.
        for (int i = 0; i < timer.Run.Count; i++)
            signature += timer.Run[i].Name.Length + ":" + timer.Run[i].Name;
        if (signature != (string)vars.runSignature)
        {
            vars.runSignature = signature;
            vars.Rebind();
        }
    }

    // Recomputed every refresh, not at rebind, so that ticking the checkbox
    // takes effect without reloading the run.
    bool positional = settings["positionalMode"] || (bool)vars.autoPositional;
    if (positional != (bool)vars.positional)
    {
        vars.positional = positional;
        print("[TheWarriors] " + (positional
            ? (settings["positionalMode"]
                ? "positional mode: one level advances one segment, names ignored"
                : "positional mode: too few segment names match a level")
            : "level-bound mode: segments are matched to levels by name"));
    }

    vars.prevToken = vars.token;
    vars.prevAsset = vars.asset;

    int manager = game.ReadValue<int>(ee + 0x0051489C);
    bool live = manager >= 0x00080000 && manager < 0x02000000 && (manager & 3) == 0;

    string token = live ? game.ReadString(ee + manager + 0x124, ReadStringType.ASCII, 16, "") : "";
    vars.token = token;
    vars.asset = game.ReadString(ee + 0x005DE240, ReadStringType.ASCII, 48, "");
    uint clock = game.ReadValue<uint>(ee + 0x0065A68C);
    vars.clock = clock;

    bool tokenChanged = token != (string)vars.prevToken;

    // The menu also requests assets with a numeric name, but only during its
    // own map load: they arrive 1.3 s after the level100 token and glued to the
    // rest of the level100 files. The loading screen we care about arrives
    // after the menu has gone quiet. Two guards are enough, and both clear the
    // observed values by a wide margin:
    //   4 s since the menu appeared   (the menu's own arrive at 1.3-2.0 s)
    //   1 s with nothing loading      (the menu's own come 0.33 s after the pak)
    if (token == (string)vars.MENU && (string)vars.prevToken != (string)vars.MENU)
        vars.menuTick = (int)vars.ticks;

    bool assetChanged = (string)vars.asset != (string)vars.prevAsset;
    int quietTicks = (int)vars.ticks - (int)vars.assetTick;
    if (assetChanged) vars.assetTick = (int)vars.ticks;

    // --- which hangout is this ----------------------------------------------
    //
    // The hub's own Main does preLoadFile("level95_chapter" .. GetCheckPoint()),
    // so the asset path names the story checkpoint, and that is what separates
    // the mandatory stop that belongs to a segment from every other trip to
    // Coney -- bailing out of a mission looks exactly the same otherwise.
    //
    // It is forgotten when the hub starts loading and learned again ~2.3 s
    // later, inside the same loading screen, so it is never stale. Until then
    // the identity is the plain hub, which only a plain "Hangout" segment
    // takes: a numbered list simply waits, and the wait is inside the load, so
    // in Game Time it costs nothing.
    if (tokenChanged && token == (string)vars.HUB) vars.hubChapter = 0;
    if (token == (string)vars.HUB && assetChanged)
    {
        int chapter = (int)vars.HubChapterOf((string)vars.asset);
        if (chapter > 0 && chapter != (int)vars.hubChapter)
        {
            vars.hubChapter = chapter;
            if (settings["verbose"])
                print("[TheWarriors] hangout " + chapter + " (story checkpoint)");
        }
    }

    vars.prevLevelId = vars.levelId;
    string levelId = (token == (string)vars.HUB && (int)vars.hubChapter > 0)
        ? token + "#" + vars.hubChapter
        : token;
    vars.levelId = levelId;

    bool isLevel = levelId.Length > 0 && vars.Levels.ContainsKey(levelId);
    bool levelChanged = levelId != (string)vars.prevLevelId;

    vars.loadScreenStart = assetChanged
        && token == (string)vars.MENU
        && vars.IsLoadScreen((string)vars.asset)
        && quietTicks >= 120
        && ((int)vars.ticks - (int)vars.menuTick) >= 480;

    // --- which kind of load is this ------------------------------------------
    //
    // Three things put a loading screen on the television and only one of them
    // is the run's fault, so they cannot all cost the same:
    //
    //   a level transition   the token moves      unavoidable, comes out
    //   a chapter load       no loading screen    unavoidable, comes out
    //   a retry              the token stays      you died; it has to cost
    //
    // The clock alone cannot tell the last two apart at the time it matters:
    // in both of them it sits at 0 with the token untouched, and what separates
    // them -- a retry RESTARTS the clock, a chapter load RESUMES it where it
    // was -- is only known once the load is over, which is too late to decide
    // whether to pause.
    //
    // The asset path does tell them apart, and it tells them apart early. A
    // retry boots the level from scratch and asks for exactly what a level
    // transition asks for: levelNNs_sec.mem, levelNN.lev, global.lua,
    // config_<difficulty>.lua, levelNN.lua. A chapter load asks for none of
    // that, only its own .lua and .pak. So "global.lua was requested" is "the
    // game is booting a level", and whether the token moved says which level:
    // if it did not move, it is booting the one already loaded, which is a
    // retry from checkpoint -- by hand from the pause menu or after a death.
    //
    // Measured over the 33 captures that have a clock: global.lua is requested
    // 56 times. 53 with the token moving 0.34-1.35 s earlier, which are the
    // transitions, and 3 with the token never moving -- the two restarts of
    // Set Up in one capture and the retry of Payback in a 17 min run.
    // It never shows up on a chapter load. And it always arrives BEFORE the
    // clock reaches 0 -- by 0.71 s in the tightest -- so the kind of load is
    // known before the window it belongs to has opened. Nothing has to be
    // given back.
    bool bootstrap = assetChanged && ((string)vars.asset).EndsWith("/global.lua");
    if (tokenChanged)
    {
        vars.tokenTick = (int)vars.ticks;
        vars.retryLoad = false;       // it was a transition after all
    }
    // 3 s of margin on a gap measured at 0.34-1.35 s, and it is one-sided: the
    // cost of being wrong here is a retry paying nothing, never a transition
    // being charged to the run.
    // --- and is it a trip to the main menu -----------------------------------
    //
    // The menu is not a load the run waits through, it is somewhere the run
    // went: you leave from the hangout or from a mission and you come back to
    // the same place, so both loading screens and the minutes in between are
    // part of the segment that was open.
    //
    // Both halves are known the moment the token moves, so nothing has to be
    // given back. In the captures the whole round trip is a SINGLE window
    // -- the clock freezes when you leave and does not move again until the
    // destination is playable, 25.7 s leaving Real Live Bunch, 27.2 s leaving
    // the hangout -- but the second half is written so that it holds if the
    // window ever splits in two.
    //
    // The one trip that is not this is the one that ends in New Blood: that is
    // the profile you just made, the run starts there, and the reset block owns
    // it.
    if (tokenChanged && token == (string)vars.MENU)
        vars.menuLoad = true;
    else if (tokenChanged && (string)vars.prevToken == (string)vars.MENU)
        vars.menuLoad = token != (string)vars.FIRST;

    if (bootstrap && ((int)vars.ticks - (int)vars.tokenTick) > 360)
    {
        vars.retryLoad = true;
        // The level boots again, so what it said about its last stretch is
        // stale. If the reboot asks for the scene again, it re-arms.
        vars.stretchSeen = false;
        vars.stretchArmed = false;
        // A retry from the pause menu pulses the 3 with control too, like
        // bailing out, but it never leaves the level: not a detour.
        vars.bailed = false;
        if (settings["verbose"])
            print("[TheWarriors] retry from checkpoint in "
                  + vars.LevelName(token)
                  + (settings["retryCounts"] ? ": it counts" : ": it comes out"));
    }

    // --- the load window ----------------------------------------------------
    //
    // A load is bounded by two things that are both in memory, so no clock of
    // our own is needed: it opens when the game commits to the next level (the
    // token moves, or the loading screen shows up first), and it closes when
    // the level clock starts counting again.
    //
    // In between, the clock does something very particular, and that is what
    // makes this cheap: it sits FROZEN at the value of the level being left for
    // another 1.7-2.4 s, then goes to 0, and stays 0 until the level is
    // playable. So "the clock has not reset yet" is just "the clock still reads
    // what it read when the token moved", and the load is over the moment it
    // reads anything other than 0. No timeout is needed for that half: the
    // first different read closes it, and the first different read is the 0.
    // Six transitions measured, in the 17 min capture and in the Armies of the
    // Night one: between 10.8 s and 19.4 s each.
    //
    // Two things fall out of it for free, and both are real:
    //
    //   - A mission fail with retry from checkpoint does a full loading screen
    //     WITHOUT touching the token. The clock resets anyway, so the clock == 0
    //     half covers it with no rule of its own.
    //   - Loading a chapter inside a level (a .pak swap, no loading screen)
    //     also parks the clock at 0, for ~1 s, and then RESUMES counting from
    //     where it was instead of restarting. That is loading too, and it comes
    //     out of Game Time like any other.
    //
    // What does NOT fire: a long cutscene freezes the clock at a non-zero value
    // (80 s at 2145 in the capture), which is neither 0 nor a change, so it
    // stays inside the run time, where it belongs.
    //
    // prevToken empty is the first read after attaching, not a load: the script
    // has simply never seen the token before.
    if ((tokenChanged && ((string)vars.prevToken).Length > 0)
        || (bool)vars.loadScreenStart)
    {
        vars.loading = true;
        vars.frozenClock = clock;
    }
    else if ((bool)vars.loading && clock != (uint)vars.frozenClock)
    {
        vars.loading = false;
    }

    // Two booleans, and the difference between them is the whole point:
    // loadingNow is "the game is loading", which is what the console reports
    // and what cuts the control hold; pauseNow is "and the run does not pay
    // for it", which is what the clock obeys.
    bool loadingNow = (bool)vars.loading || clock == 0;
    bool pauseNow = loadingNow
        && !(settings["retryCounts"] && (bool)vars.retryLoad)
        && !(settings["menuCounts"] && (bool)vars.menuLoad);
    vars.pauseNow = pauseNow;

    // The IL clock does not follow the menu exception, on purpose: with IL
    // timing a mission's segment measures the control you had in ITS level,
    // and the main menu is not that. Leaving from the hangout it counts
    // anyway, because the hangout's segment is dead time and keeps it.
    bool pauseIL = loadingNow
        && !(settings["retryCounts"] && (bool)vars.retryLoad);
    if (loadingNow != (bool)vars.wasLoading)
    {
        vars.wasLoading = loadingNow;
        if (loadingNow) vars.loadStartMs = Environment.TickCount;
        else
        {
            if (settings["verbose"])
                print("[TheWarriors] " + vars.LevelName(token) + " loaded in "
                      + ((Environment.TickCount - (int)vars.loadStartMs) / 1000.0)
                        .ToString("0.00") + " s"
                      + ((bool)vars.retryLoad ? " (retry)" : "")
                      + ((bool)vars.menuLoad ? " (menu)" : ""));
            vars.retryLoad = false;
            vars.menuLoad = false;
        }
    }

    // --- does the player have control ---------------------------------------
    //
    // Byte +0x1B of the player's control block. The engine reads it in 134
    // places to ask "does this human take input", and it is the one signal
    // that matched a real run: in the capture of 2026-09-21 it dropped and
    // came back within 2 s of the nine moments marked by hand on that run,
    // three of them to the millisecond. It is NOT the pad lock of HuLockPad
    // (+0x1E), which came up once in a whole level.
    //
    // The chain is all fixed addresses, and it starts at the manager the
    // script already reads:
    //
    //   manager + 0x228      the player's handle: generation:u16, index:u16
    //   0x006EBD38 + i*8     handle table: { pointer:u32, ..., generation:u16 }
    //   human + 0x92         which control block is his
    //   0x00660F50 + n*44    the blocks, and +0x1B is the byte
    //
    // Re-resolved every refresh on purpose: the block index changes INSIDE a
    // level (0 -> 2 in New Blood), so caching it per level would read someone
    // else's byte.
    //
    // When a step does not resolve -- the human is destroyed during the end
    // cutscene, the game is between levels -- the last known value is kept.
    // That keeps the cutscene frozen, and it also means that a level where the
    // chain somehow failed would leave the clock RUNNING instead of stopping
    // the run's Game Time dead. Failing towards "counting" is the safe side.
    if (live)
    {
        int generation = game.ReadValue<short>(ee + manager + 0x228) & 0xFFFF;
        int slot = game.ReadValue<short>(ee + manager + 0x22A) & 0xFFFF;
        if (generation != 0xFFFF && slot < 0x4000)
        {
            int entry = 0x006EBD38 + slot * 8;
            int human = game.ReadValue<int>(ee + entry);
            if ((game.ReadValue<short>(ee + entry + 4) & 0xFFFF) == generation
                && human >= 0x00080000 && human < 0x02000000)
            {
                int block = game.ReadValue<short>(ee + human + 0x92);
                if (block >= 0 && block <= 512)
                {
                    bool control = game.ReadValue<byte>(
                        ee + 0x00660F50 + block * 0x2C + 0x1B) != 0;
                    if (control != (bool)vars.control && settings["verbose"])
                        print("[TheWarriors] " + (control
                            ? "player has control" : "no control (cutscene)"));
                    vars.control = control;
                }
            }
        }
    }

    // --- the IL clock -------------------------------------------------------
    //
    // What IL timing has to measure is "from the moment the level hands you
    // the character to the moment it takes it away for good", and the two ends
    // are not symmetric:
    //
    //   - The opening cutscene is known while it happens (control has not been
    //     given yet in this level), so it is simply not counted.
    //   - The LAST cutscene is only known to be the last one once the level is
    //     over. So it IS counted while it runs -- the clock never stops in the
    //     middle of a level, which is the point: dodging a cutscene has to pay
    //     off, and a cutscene you walked into has to cost -- and the moment the
    //     level ends the clock gives that last stretch back.
    //
    // That is why this is a clock of our own instead of the isLoading pause:
    // pausing can only stop time, never hand it back. LiveSplit applies the
    // gameTime block right before it asks about the split (verified by reading
    // the IL of ASLScript.DoUpdate), so the corrected value is the one the
    // split records.
    //
    // The 0.5 s hold is the one number here that is not exact, and it is what
    // makes the give-back survive the way this engine chains cutscenes: at the
    // end of a level control flickers back for an instant between scenes --
    // 0.03 s in New Blood, 0.30 and 0.27 s in Real Live Bunch. Without it, the
    // first flicker would cut the give-back short and leave most of the closing
    // cutscene inside the segment. Real gameplay in the same capture never came
    // back for less than 1.5 s, so the margin is threefold.
    //
    // Only a MISSION's segment measures from control to control. A hangout
    // segment, or one bound to no level -- call it "Load 4" -- is there to
    // show the dead time between two missions, which is closing cutscene +
    // load (+ hub + load) + opening cutscene, so it keeps all of it EXCEPT the
    // loads, which come out as they do in the classic clock.
    bool ownsGameplay = (bool)vars.positional;
    bool ownLevel = (bool)vars.positional;
    if (!(bool)vars.positional)
    {
        var bound = (List<string>)vars.segToken;
        int at = timer.CurrentSplitIndex;
        bool inRange = at >= 0 && at < bound.Count;
        ownsGameplay = inRange && bound[at] != null
                       && !bound[at].StartsWith((string)vars.HUB);
        // And it has to be ITS level. With no hangout segment in the list,
        // the next mission's segment is already open while you walk around
        // Coney, and without this the clock would charge that walk to it.
        ownLevel = inRange && vars.Matches(bound[at], levelId);
    }
    vars.ownsGameplay = ownsGameplay;

    double realNow = timer.CurrentTime.RealTime.HasValue
        ? timer.CurrentTime.RealTime.Value.TotalSeconds : -1.0;
    double delta = (realNow >= 0 && (double)vars.realPrev >= 0)
        ? realNow - (double)vars.realPrev : 0.0;
    vars.realPrev = realNow;
    if (delta < 0) delta = 0;            // the run was reset

    // The hold is control that is SUSTAINED and playable: a load cuts it, so
    // the credit below can never drag in time from before the level.
    if ((bool)vars.control && !loadingNow)
        vars.holdTime = (double)vars.holdTime + delta;
    else vars.holdTime = 0.0;
    bool solid = (double)vars.holdTime >= 0.5;

    // A detour: this mission's segment has already started -- it had control
    // in its level -- and has none now, because you left the mission without
    // finishing it, to the main menu, to the hangout or both, and have not got
    // the character back in its level yet. That is a mistake of the run, like
    // a retry, so it is paid for, consistently with the retry and with the
    // menu trip from the hangout: the segment follows the classic clock until
    // control returns in its level. "Already started" is what keeps apart the
    // NEXT mission's segment standing open while you walk around Coney, which
    // must not count (ownLevel, above).
    bool detour = !(bool)vars.positional && ownsGameplay
                  && !(bool)vars.seenControl
                  && (int)vars.startedSeg == timer.CurrentSplitIndex;

    if (delta > 0)
    {
        if (!ownsGameplay || detour)
        {
            // The dead time, minus the loading screens -- with the same
            // exceptions as the classic clock, so a trip to the main menu
            // from the hangout still counts. The loads are the classic
            // clock's business; this segment is for what in that stretch is
            // not a load: the cutscenes at both ends and the hub. A detour
            // runs on this same clock: the menu trip counts with both of its
            // loads, the load back into the level does not.
            if (!pauseNow || (detour && settings["detourLoadsCount"]))
                vars.counted = (double)vars.counted + delta;
            vars.pending = 0.0;
        }
        else if (!pauseIL && (bool)vars.seenControl)
        {
            // pauseIL, not loadingNow: a retry from checkpoint is time the
            // level's own segment pays for, the same as in the classic clock.
            // It lands in `pending` because control is down, and it leaves the
            // moment control comes back solid, which is always before the
            // level can end.
            vars.counted = (double)vars.counted + delta;
            if (solid) vars.pending = 0.0;
            else vars.pending = (double)vars.pending + delta;
        }
    }

    // The level has handed the character over: from here the segment counts.
    // The hold is added back so the segment starts at the instant control
    // returned and not half a second later.
    if (solid && !(bool)vars.seenControl && ownsGameplay && ownLevel)
    {
        vars.seenControl = true;
        // Back from a detour the hold has already been counted by it; the
        // credit is only for the segment's start.
        if ((int)vars.startedSeg != timer.CurrentSplitIndex)
        {
            vars.counted = (double)vars.counted + (double)vars.holdTime;
            vars.startedSeg = timer.CurrentSplitIndex;
        }
        vars.bailed = false;
        if (settings["verbose"])
            print("[TheWarriors] IL: starts " + vars.LevelName(levelId));
    }

    // The mission state, which is the net under the table above. It pulses to
    // 3 when the mission is over, and across the 23 captures that is always
    // AFTER the last control (2.2 to 13.3 s) and always BEFORE the next level
    // starts loading (9.9 to 21.5 s), so it can never fire early and it always
    // beats the old cut. In All-City it lands on 215.316, which is the very
    // instant marked by hand on that run as the alternative.
    //
    // It also pulses when you BAIL OUT of a mission and when you leave the hub
    // to start one, and both of those happen with the character still in your
    // hands, which the check right below already rejects. Asking for half a
    // second of no control on top is the belt to that pair of braces, and the
    // margin is measured on both sides: bailing out of Blackout pulsed with
    // control still on, and the tightest real ending -- Armies Stage 3 and 4,
    // which end by themselves instead of on a marker -- pulses at 1.25 s.
    //
    // And it pulses a THIRD time, which a capture of 2026-09-23 found:
    // dying and choosing "restart from checkpoint" from the game over screen
    // pulses it too. That one is not a mission ending and must not close the
    // level -- but it comes out of a 1, not out of a 0. State 1 is the death:
    // it is written the instant the player dies, six seconds before the game
    // over screen takes the pad away, and it goes back to 0 when the restart
    // is done. Over the 30 captures that carry it there are 47 pulses to 3,
    // 46 of them out of a 0 and exactly one -- the death in Set Up -- out of a
    // 1, so asking where the pulse came FROM costs nothing and is not a
    // margin.
    //
    // Without it the rule still held, but on luck: at the pulse the player's
    // human is already destroyed, so the control chain does not resolve and
    // the script keeps the last value it read, which was "in your hands" from
    // 1.22 s earlier. Half a second either way and the belt below would have
    // been the only thing left.
    int mission = live ? game.ReadValue<int>(ee + manager + 0x14C) : 0;
    bool missionOver = mission == 3 && (int)vars.prevMission != 3
                       && (int)vars.prevMission != 1;
    bool died = mission == 1 && (int)vars.prevMission != 1;
    // Bailing out of a mission pulses that same 3 with the character STILL IN
    // YOUR HANDS, 2 to 2.5 s before the level is left; finishing it pulses
    // with control gone. Every one of the five captures that leave a level
    // mid-mission shows it. That is what tells a detour apart from a finish
    // whose closing was somehow missed -- without it, that trip to Coney would
    // be charged to the mission you had just finished.
    if (missionOver && (bool)vars.control && ownLevel
        && (int)vars.startedSeg == timer.CurrentSplitIndex)
        vars.bailed = true;
    vars.prevMission = mission;

    // Has the level just closed? Two ways, and the earliest one wins: its
    // closing cutscene asks for an asset of its own -- the earliest instant
    // anything in memory says so, 0.07 to 4.44 s after the control went -- or,
    // for the five levels whose closing cutscene is already resident and asks
    // for nothing, the mission state.
    bool overByAsset = vars.LevelOver.ContainsKey(token)
        && ((string)vars.asset).Contains((string)vars.LevelOver[token]);
    bool overByMission = missionOver && (double)vars.pending >= 0.5;
    if (settings["ilTime"] && !(bool)vars.levelOver && !(bool)vars.control
        && (overByAsset || overByMission))
    {
        vars.levelOver = true;
        vars.levelOverSplit = true;
        if (settings["verbose"])
            print("[TheWarriors] IL: closes " + vars.LevelName(levelId)
                  + " (" + (overByAsset ? "asset" : "mission state")
                  + "), -" + ((double)vars.pending).ToString("0.00") + " s");
        vars.counted = (double)vars.counted - (double)vars.pending;
        vars.pending = 0.0;
        vars.startedSeg = -1;     // finished: leaving it is not a detour
        vars.bailed = false;
    }

    // The level is over, so whatever was still pending WAS its last cutscene:
    // the clock gives it back here, one refresh before the split is asked for.
    if (levelChanged)
    {
        if ((double)vars.pending > 0)
        {
            vars.counted = (double)vars.counted - (double)vars.pending;
            if (settings["verbose"])
                print("[TheWarriors] IL: -"
                      + ((double)vars.pending).ToString("0.00")
                      + " s, the closing cutscene of "
                      + vars.LevelName((string)vars.prevLevelId));
        }
        vars.pending = 0.0;
        vars.holdTime = 0.0;
        vars.seenControl = false;
        vars.levelOver = false;
        vars.levelOverSplit = false;
        vars.stretchSeen = false;
        vars.stretchArmed = false;
        // Leaving without having bailed out is not a detour.
        if (!(bool)vars.bailed) vars.startedSeg = -1;
        vars.deferred = -1;
    }

    // What the clock SHOWS, which is the only thing this changes. Once the
    // level is over, whatever is still pending is given back when the next
    // level starts loading -- in a list where the next segment is a mission,
    // that used to run on the clock after the split and then jump back. And
    // in the level's last stretch the next control loss is the closing
    // cutscene, which is given back too, so it is not shown running either.
    //
    // It arms on the scene AND on solid control after it, so arming never
    // hides anything that was already pending. Dying disarms it the same way
    // a reload does (above): the level boots again.
    if (assetChanged && vars.ClosingStretch.ContainsKey(token)
        && ((string)vars.asset).Contains((string)vars.ClosingStretch[token]))
        vars.stretchSeen = true;
    if (died)
    {
        vars.stretchSeen = false;
        vars.stretchArmed = false;
    }
    if ((bool)vars.stretchSeen && solid && !(bool)vars.stretchArmed)
    {
        vars.stretchArmed = true;
        if (settings["verbose"] && settings["ilTime"])
            print("[TheWarriors] IL: last stretch of " + vars.LevelName(levelId));
    }
    vars.hidePending = (bool)vars.levelOver || (bool)vars.stretchArmed;

    // --- level identity -----------------------------------------------------
    //
    // Entering a level advances the timer to that level's segment. Everything
    // else falls out of that one rule: the hub is not bound to a segment (in a
    // list without hangout splits) so it cannot split; re-entering the same
    // level lands on the segment already current, so it cannot split; replaying
    // an earlier level looks backwards, and the search only ever looks forward.
    //
    // "That level" is the identity, not the token: the hangout is twelve levels
    // that share one token, told apart by the story checkpoint.

    int splitIndex = timer.CurrentSplitIndex;
    vars.enteredIdx = -1;
    vars.enteredFirst = false;

    if (levelChanged && isLevel)
    {
        var segs = (List<string>)vars.segToken;

        if ((bool)vars.positional)
        {
            // No usable names, so reproduce exactly what the splitter
            // guaranteed before level identity existed: one segment per level,
            // never for the hub, never twice for the same level, and never
            // backwards through the story. The story number is the prefix of
            // the LEVELNAME label; flashbacks and Armies stages have none.
            string[] info = (string[])vars.Levels[levelId];
            int story = 0;
            int.TryParse(info[1].Split(':')[0], out story);

            bool forward = info[2] != "hub"
                && levelId != (string)vars.lastLevel
                && (story == 0 || story > (int)vars.bestStory);

            // enteredFirst is computed whether or not the timer is running,
            // because a reset can happen LATER in this same refresh and the
            // start block that follows it would otherwise find it false. See
            // the level-bound branch below for the whole story.
            vars.enteredFirst = forward && story == 1;
            if (splitIndex >= 0 && forward) vars.enteredIdx = splitIndex + 1;
            if (forward && story > 0) vars.bestStory = story;
        }
        else
        {
            // "Could this level start the run?" is asked on every entry, not
            // only when the timer is stopped, and that is what makes the reset
            // of a new profile work. LiveSplit runs reset and then start in the
            // same DoUpdate, but `update` -- this -- has already run by then,
            // so a value that depended on the timer being stopped would still
            // read "running" and the run would reset and never start. Nothing
            // else reads this: the start block is the only consumer, and
            // LiveSplit only asks it with the timer stopped.
            //
            // The run can start on a DEAD-TIME segment: a "Load 0" holding the
            // loading screen of the first level. So the segment to match is the
            // first one that is bound to a level, not segment 0 -- and with IL
            // timing that one opens with the first control, like every other
            // mission.
            int firstBound = 0;
            while (firstBound < segs.Count && segs[firstBound] == null)
                firstBound++;
            if (firstBound < segs.Count
                && vars.Matches(segs[firstBound], levelId))
            {
                vars.enteredFirst = true;
                vars.startAt = firstBound;
            }

            if (splitIndex >= 0)
            {
                for (int i = splitIndex; i < segs.Count; i++)
                {
                    if (!vars.Matches(segs[i], levelId)) continue;

                    // A wildcard segment that already took a DIFFERENT
                    // flashback is spent: this one belongs to the next
                    // wildcard. Without this, entering the second flashback
                    // would land on the segment the run is already standing on
                    // -- the wildcard matches it too -- and nothing would ever
                    // close it. Re-entering the same flashback after bailing
                    // out still lands here, and still splits nothing.
                    if (segs[i] == (string)vars.ANYFLASH
                        && i == (int)vars.wildAt
                        && levelId != (string)vars.wildToken) continue;

                    vars.enteredIdx = i;
                    break;
                }

                // A segment bound to the PLAIN hangout may only ever close the
                // segment immediately before it. It has no checkpoint to it, and
                // the game returns to Coney over and over, so without this guard
                // a list carrying a single trailing "Hangout" jumps to it on the
                // first visit and marks every level in between as never played.
                // A numbered hangout needs no guard: its checkpoint is proof of
                // which visit this is.
                if ((int)vars.enteredIdx > splitIndex + 1
                    && (int)vars.enteredIdx < segs.Count
                    && segs[(int)vars.enteredIdx] == (string)vars.HUB)
                    vars.enteredIdx = -1;

                // Whatever wildcard this landed on now holds this flashback,
                // and says so from here on.
                int landed = (int)vars.enteredIdx;
                if (landed >= 0 && segs[landed] == (string)vars.ANYFLASH
                    && ((int)vars.wildAt != landed
                        || (string)vars.wildToken != levelId))
                {
                    vars.wildAt = landed;
                    vars.wildToken = levelId;
                    if (settings["verbose"])
                        print("[TheWarriors] wildcard segment " + landed
                              + " takes " + vars.LevelName(levelId));
                }
            }
        }

        // The hub must not count as "the last level played": otherwise going
        // back to the hangout and re-entering the same mission would look like
        // a new level.
        if (((string[])vars.Levels[levelId])[2] != "hub")
            vars.lastLevel = levelId;

        if (settings["verbose"])
            print("[TheWarriors] entered " + vars.LevelName(levelId)
                  + "  [was " + vars.LevelName((string)vars.prevLevelId) + "]"
                  + "  segment " + splitIndex + " -> " + vars.enteredIdx);
    }

    // The second cut. With IL timing, a MISSION's segment opens when the level
    // hands you the character, not when it starts loading -- which is what
    // lets the segment before it ("Hangout 6", "Load 4") hold the whole dead
    // time instead of only the part before the loading screen. The hub and an
    // unnamed segment still open with the token: they ARE the dead time.
    int advanceTo = (int)vars.enteredIdx;
    if (settings["ilTime"] && !(bool)vars.positional
        && advanceTo > splitIndex && splitIndex >= 0)
    {
        var aheadSegs = (List<string>)vars.segToken;
        if (advanceTo < aheadSegs.Count && aheadSegs[advanceTo] != null
            && !aheadSegs[advanceTo].StartsWith((string)vars.HUB))
        {
            vars.deferred = advanceTo;
            advanceTo = -1;
            if (settings["verbose"])
                print("[TheWarriors] IL: segment " + (int)vars.deferred
                      + " waits for the first control");
        }
    }

    // The level handed the character over, so the deferred cut happens now.
    // The hold is taken off the clock because the dead-time segment has been
    // counting it since control came back; the credit below puts it back on
    // the mission's side, where it belongs. Only if it WAS counting it: a
    // skipped mission, or one whose closing was missed, counts nothing outside
    // its level, and taking the hold off it cost it half a second.
    if ((int)vars.deferred >= 0 && solid && splitIndex >= 0
        && (int)vars.deferred > splitIndex)
    {
        if (!ownsGameplay || detour)
            vars.counted = (double)vars.counted - (double)vars.holdTime;
        advanceTo = (int)vars.deferred;
        vars.deferred = -1;
    }

    if (advanceTo > splitIndex && splitIndex >= 0)
    {
        vars.splitPlayed = splitIndex;
        vars.splitTarget = advanceTo;
        if ((int)vars.splitTarget > splitIndex + 1 && settings["verbose"])
            print("[TheWarriors] " + ((int)vars.splitTarget - splitIndex - 1)
                  + " segment(s) were never played");
    }

    // Catch up to the target. The segment that was actually played is split by
    // the split block; everything between it and the target is marked skipped,
    // one per refresh.
    if (splitIndex > (int)vars.splitPlayed && splitIndex < (int)vars.splitTarget)
    {
        if (settings["split"] && settings["catchUp"])
        {
            if (vars.model == null)
                vars.model = new LiveSplit.Model.TimerModel { CurrentState = timer };
            vars.model.SkipSplit();
        }
        else
        {
            // Catch-up disabled: take the one split and stop chasing the run.
            vars.splitTarget = splitIndex;
        }
    }

    // A boss death asked to end a run that still has segments after it: skip
    // what is left and split the last one, which is what ends a run.
    if ((bool)vars.endingRun)
    {
        if (splitIndex < 0)
        {
            vars.endingRun = false;
        }
        else
        {
            if (vars.model == null)
                vars.model = new LiveSplit.Model.TimerModel { CurrentState = timer };
            if (splitIndex < timer.Run.Count - 1) vars.model.SkipSplit();
            else { vars.model.Split(); vars.endingRun = false; }
        }
    }

    // The health of the current level's boss, and only inside that level: that
    // level gate is what stops the Luther of AOTN Stage 5 from ending a 100%
    // run. The slot is found once and then reread; sweeping the 64 slots costs,
    // so it is only searched 4 times a second while the boss is not there.
    vars.prevBossHp = vars.bossHp;
    int hp = -1;
    if (vars.Bosses.ContainsKey(token))
    {
        int bossChar = (int)vars.Bosses[token];
        int slot = (int)vars.bossSlot;
        bool stillThere = slot >= 0
            && game.ReadValue<int>(ee + 0x0063FEE0 + slot * 0x6D0 + 0xD0) == bossChar;
        if (!stillThere)
        {
            slot = ((int)vars.ticks % 30 == 0) ? (int)vars.FindBoss(ee, bossChar) : -1;
            vars.bossSlot = slot;
            if (slot >= 0 && settings["verbose"])
                print("[TheWarriors] boss char " + bossChar + " of " + token
                      + " in slot " + slot);
        }
        if (slot >= 0)
        {
            int stats = game.ReadValue<int>(ee + 0x0063FEE0 + slot * 0x6D0 + 0xD4);
            if (stats >= 0x00080000 && stats < 0x02000000)
                hp = game.ReadValue<short>(ee + stats + 0x144);
        }
    }
    else
    {
        vars.bossSlot = -1;
    }
    vars.bossHp = hp;

    return true;
}

start
{
    if (!settings["start"]) return false;

    // Preferred: sitting in the menu, the game requests the first loading
    // screen texture. That is the immediate reaction to confirming the profile.
    if (settings["startEarly"] && (bool)vars.loadScreenStart)
        return true;

    // Safety net: if that did not fire, the level token arrives 2.1 s later
    // anyway. It also covers starting from a save state.
    return (bool)vars.enteredFirst;
}

onStart
{
    // The run is on segment 0 and that segment's level is the one loading, so
    // there is nothing to close yet.
    vars.splitPlayed = 0;
    vars.splitTarget = 0;
    vars.endingRun = false;

    // The IL clock starts over with the run.
    vars.realPrev = -1.0;
    vars.counted = 0.0;
    vars.pending = 0.0;
    vars.holdTime = 0.0;
    vars.seenControl = false;
    vars.startedSeg = -1;
    vars.bailed = false;

    // If the run started on a "Load 0", the first mission's segment is waiting
    // for the first control, exactly like every other one.
    vars.deferred = (settings["ilTime"] && (int)vars.startAt > 0)
        ? (int)vars.startAt : -1;
    vars.startAt = 0;

    // A run can start on a flashback -- an IL, or a 100% routed that way -- so
    // if segment 0 is a wildcard it takes the level that started the timer.
    // Rebuilt here rather than carried over, because whatever a previous
    // attempt left behind points at a segment this run has not reached.
    vars.wildAt = -1;
    vars.wildToken = "";
    var startSegs = (List<string>)vars.segToken;
    if (startSegs.Count > 0 && startSegs[0] == (string)vars.ANYFLASH
        && vars.IsFlashback((string)vars.levelId))
    {
        vars.wildAt = 0;
        vars.wildToken = (string)vars.levelId;
    }
}

onReset
{
    vars.splitPlayed = -1;
    vars.splitTarget = -1;
    vars.endingRun = false;
    vars.lastLevel = "";
    vars.bestStory = 0;
    vars.wildAt = -1;
    vars.wildToken = "";

    // The IL clock starts over with the run.
    vars.realPrev = -1.0;
    vars.counted = 0.0;
    vars.pending = 0.0;
    vars.holdTime = 0.0;
    vars.seenControl = false;
    vars.startedSeg = -1;
    vars.bailed = false;
    vars.deferred = -1;
}

split
{
    if (!settings["split"] && !settings["final"]) return false;

    // With IL timing on and the level's closing asset known, the level closes
    // HERE -- when its last cutscene starts -- instead of when the next level
    // begins to load. The recorded time is the same either way: update rewound
    // the clock one step before this runs, and LiveSplit applies gameTime
    // before it asks for the split.
    if (settings["split"] && settings["ilTime"] && (bool)vars.levelOverSplit)
    {
        vars.levelOverSplit = false;
        int closing = timer.CurrentSplitIndex;
        var closingSegs = (List<string>)vars.segToken;
        if (!(bool)vars.positional && closing >= 0 && closing < closingSegs.Count
            && vars.Matches(closingSegs[closing], (string)vars.levelId))
        {
            if (settings["verbose"])
                print("[TheWarriors] split on the closing cutscene, segment "
                      + closing);
            vars.splitPlayed = closing;
            vars.splitTarget = closing;
            return true;
        }
    }

    // The one real split: the segment that was actually played closes here.
    // Anything after it up to the target is skipped, in update.
    if (settings["split"]
        && (int)vars.splitTarget > (int)vars.splitPlayed
        && timer.CurrentSplitIndex == (int)vars.splitPlayed)
        return true;

    if (!settings["final"]) return false;

    // A boss death closes the segment bound to that boss's own level, and only
    // that one. If the run is not standing on it, this is not the split to
    // take -- which is the whole point: the knife used to close whatever
    // segment happened to be up.
    int splitIndex = timer.CurrentSplitIndex;
    if (splitIndex < 0) return false;

    // Normally the level we are in; with the unload alternative, the one we
    // just left, because by then the token has already moved on.
    string bossLevel = settings["finalUnload"] ? (string)vars.prevToken : (string)vars.token;
    if (!vars.Bosses.ContainsKey(bossLevel)) return false;

    if (!(bool)vars.positional)
    {
        var segs = (List<string>)vars.segToken;
        if (splitIndex >= segs.Count || segs[splitIndex] != bossLevel) return false;
    }
    else if (splitIndex != timer.Run.Count - 1)
    {
        // No names to go on: keep the old behaviour of only ending the run on
        // the last segment, rather than splitting whatever happens to be up.
        return false;
    }

    bool killed = !settings["finalUnload"]
        && (int)vars.prevBossHp > 1 && (int)vars.bossHp == 1;
    bool unloaded = settings["finalUnload"]
        && (string)vars.token != bossLevel;

    if (!killed && !unloaded) return false;

    if (settings["verbose"])
        print("[TheWarriors] boss of " + bossLevel + " died, closing segment "
              + splitIndex);

    vars.splitPlayed = splitIndex;
    vars.splitTarget = splitIndex;
    if (settings["finalEndsRun"] && splitIndex < timer.Run.Count - 1)
        vars.endingRun = true;
    return true;
}

reset
{
    if (!settings["reset"]) return false;

    // The main menu hands you New Blood, and that is a new profile: making a
    // profile drops you into New Blood, where the pause menu is the first
    // chance to set the game up, and picking that profile afterwards drops you
    // in again -- and THAT second entry is the start of the run. The first one
    // starts the timer too, and this is what throws that attempt away.
    //
    // Everything else the main menu does keeps the run: it hands you the
    // hangout, or the mission you were on if you had never finished it. Both
    // are places a run can come back from, so neither resets, and the trip
    // stays inside Game Time (the load window block owns that half).
    //
    // Safe for 100% as well: Armies of the Night is entered from the hangout,
    // and replaying New Blood cannot reach this rule, because the menu only
    // returns you to a mission the first time you play it.
    //
    // Reset and start land on the same refresh, and LiveSplit does that by
    // itself: DoUpdate calls Reset(), skips the split, re-reads the phase --
    // now NotRunning -- and asks `start` five instructions later, with the
    // enteredFirst that `update` already computed. Read from the IL of
    // ASLScript.DoUpdate.
    return (string)vars.token == (string)vars.FIRST
        && (string)vars.prevToken == (string)vars.MENU;
}

isLoading
{
    // Game Time = real time minus everything this returns true for. LiveSplit
    // does the subtracting; all the script owes it is the "I am loading" bit.
    if (!settings["gameTime"]) return false;
    // With IL timing on the clock is the gameTime block's, which sets the
    // whole value every refresh; pausing on top of that would only fight it.
    if (settings["ilTime"]) return false;

    return (bool)vars.pauseNow;
}

gameTime
{
    // Returning null leaves LiveSplit's own Game Time alone, which is what
    // keeps the classic behaviour exactly as it was.
    if (!settings["gameTime"] || !settings["ilTime"]) return null;

    // SetGameTime stores RealTime - this, so handing back the same value on
    // every refresh holds the clock still, and handing back a smaller one than
    // last time rewinds it. It holds through a load and through the opening
    // cutscene. It rewinds once, when a level ends, by the length of that
    // level's closing cutscene -- except where the update block already knew
    // it was the closing one and kept it off the clock, which is where the
    // rewind is not seen.
    //
    // Every split records this value, and a level split is always taken with
    // `pending` just given back or already 0, so hiding it changes nothing
    // recorded. The one split that could land with something hidden is the
    // boss's, with level splits turned off, after Come Out To Play's closing
    // asset -- and what is hidden there is closing cutscene, which IL timing
    // leaves out anyway.
    double shown = (double)vars.counted;
    if ((bool)vars.hidePending) shown -= (double)vars.pending;
    return TimeSpan.FromSeconds(shown);
}

exit
{
    vars.ee = IntPtr.Zero;
    vars.model = null;
}
