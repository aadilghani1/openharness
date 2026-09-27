// Generated from daemons/roster.json by daemons/tools/generate.mjs. Do not edit.
// ignore_for_file: prefer_single_quotes
const daemonRosterJson = r'''
{
  "version": 1,
  "rules": {
    "moods": [
      "idle",
      "work",
      "need",
      "done",
      "fail",
      "back",
      "nap",
      "boop"
    ],
    "eyes": {
      "idle": "o",
      "work": "=",
      "need": "?",
      "done": "^",
      "fail": "x",
      "back": "^",
      "nap": "-",
      "boop": "O"
    },
    "blinks": {
      "ack": [
        [
          "-",
          120
        ]
      ],
      "look": [
        [
          "-",
          120
        ]
      ],
      "slow": [
        [
          "_",
          180
        ],
        [
          "-",
          520
        ],
        [
          "_",
          180
        ]
      ]
    },
    "noBlinkMoods": [
      "work",
      "nap",
      "boop"
    ],
    "holdMs": {
      "done": 3000,
      "back": 1300,
      "fail": 4200,
      "boop": 900
    },
    "backFrameMs": 110,
    "versions": [
      "0.1",
      "1.0",
      "2.0"
    ],
    "bondForVersion": {
      "0.1": 0,
      "1.0": 2,
      "2.0": 4
    },
    "bond": {
      "xpPerTurn": 1,
      "xpPerDay": 5,
      "levels": [
        0,
        50,
        150,
        300,
        600
      ]
    },
    "statusCells": 8,
    "portraitMaxCols": 28,
    "portraitMaxRows": 8,
    "ligatureUnsafe": [
      "==",
      "??",
      "!=",
      "::",
      "~~",
      "->",
      "=>",
      "<=",
      ">=",
      "<>",
      "||",
      "&&",
      "++",
      "//",
      "^=",
      "~=",
      ":="
    ],
    "rarities": [
      "common",
      "rare",
      "legendary",
      "secret"
    ],
    "shinyOneIn": 256,
    "pityPerMiss": 1,
    "secretGuaranteeAt": 8,
    "duplicateXp": 150,
    "overflowXp": 50,
    "lessonXp": 25,
    "firstEgg": {
      "need": 3,
      "require": [
        "turn"
      ],
      "habits": [
        {
          "key": "turn",
          "label": "Finish a turn in a harness"
        },
        {
          "key": "split",
          "label": "Run two harnesses side by side"
        },
        {
          "key": "find",
          "label": "Find something with Cmd-O"
        },
        {
          "key": "elsewhere",
          "label": "Answer a harness from another device"
        },
        {
          "key": "machine",
          "label": "Connect a second computer"
        },
        {
          "key": "store",
          "label": "Try a Store harness"
        },
        {
          "key": "resume",
          "label": "Resume a paused harness"
        },
        {
          "key": "days",
          "label": "Come back on three different days"
        }
      ]
    },
    "setupEgg": {
      "need": 6
    },
    "eggs": {
      "first": {
        "look": "\\_O_/",
        "weights": {
          "common": 60,
          "rare": 27,
          "legendary": 12,
          "secret": 0
        },
        "boost": {
          "tim": 4
        }
      },
      "setup": {
        "look": "\\_$_/",
        "weights": {
          "common": 60,
          "rare": 27,
          "legendary": 12,
          "secret": 0
        }
      },
      "turn": {
        "look": "\\_O_/",
        "weights": {
          "common": 60,
          "rare": 27,
          "legendary": 12,
          "secret": 0
        }
      },
      "week": {
        "look": "\\_0_/",
        "weights": {
          "common": 45,
          "rare": 35,
          "legendary": 18,
          "secret": 0
        }
      },
      "marathon": {
        "look": "\\_@_/",
        "weights": {
          "common": 25,
          "rare": 40,
          "legendary": 32,
          "secret": 0
        }
      },
      "night": {
        "look": "*\\_O_/",
        "weights": {
          "common": 50,
          "rare": 30,
          "legendary": 12,
          "secret": 8
        },
        "boost": {
          "bat": 4
        }
      },
      "history": {
        "look": "\\_47_/",
        "weights": {
          "common": 60,
          "rare": 27,
          "legendary": 12,
          "secret": 0
        }
      },
      "easter": {
        "look": "\\_?_/",
        "weights": {
          "common": 0,
          "rare": 0,
          "legendary": 90,
          "secret": 10
        }
      }
    },
    "earn": {
      "turn": {
        "every": 40,
        "dailyCap": 20,
        "minutesPerTurn": 10
      },
      "week": {
        "days": 3
      },
      "marathon": {
        "turns": 500,
        "machines": 2
      },
      "night": {
        "nights": 3,
        "fromHour": 22,
        "toHour": 6,
        "awayMinutes": 30
      },
      "history": {
        "days": 7
      }
    },
    "historyDates": {
      "04-01": "teapot",
      "09-09": "moth",
      "10-31": "zombie"
    },
    "easterHashes": [
      "184858a00fd7971f810848266ebcecee5e8b69972c5ffaed622f5ee078671aed"
    ],
    "nest": [
      "\\_O_/",
      "~\\_O_/~",
      "\\_.._/",
      "\\_o.o_/"
    ],
    "egg": [
      "       .--.",
      "      /    \\",
      "     |      |",
      "     |      |",
      "      \\    /",
      "   \\___'--'___/"
    ],
    "lineSlots": [
      "who",
      "q",
      "recap",
      "n",
      "summary"
    ],
    "lineExample": {
      "who": "codex@office",
      "q": "Bash: npm run migrate",
      "recap": "3 files changed, tests pass",
      "n": "3",
      "summary": "2 done, 1 waiting 40m"
    }
  },
  "drops": [
    {
      "id": "unix",
      "n": 1,
      "name": "unix",
      "announce": "2026-09-12",
      "release": "2026-09-26"
    },
    {
      "id": "tty",
      "n": 2,
      "name": "tty",
      "announce": "2026-09-27",
      "release": "2026-10-11"
    }
  ],
  "daemons": [
    {
      "id": "tim",
      "n": 1,
      "drop": "unix",
      "rarity": "common",
      "color": {
        "xterm": 71,
        "hex": "#5faf5f"
      },
      "shiny": {
        "xterm": 49,
        "hex": "#00ffaf"
      },
      "family": [
        [
          "screen",
          1987
        ],
        [
          "tmux",
          2007
        ],
        [
          "tim",
          2026
        ]
      ],
      "lore": "Named the way vim was: vi improved. tmux followed screen; tim is tmux improved, and so is the app it lives in.",
      "first": "oh hi. i'm tim. tmux, improved. what are we building?",
      "lines": {
        "idle": "all quiet. no alerts.",
        "work": "{n} panes busy. watching.",
        "need": "{who}: {q}  (bell)",
        "done": "silence in {who}: {recap}",
        "fail": "{who} failed: {recap}  (pane is dead)",
        "back": "reattached. {summary}.",
        "nap": "detached. reattach any time.",
        "boop": "hey. that's my status line."
      },
      "sprites": {
        "0.1": "[{e} {e}]",
        "1.0": "[{e}|{e}]",
        "2.0": "\\[{e}|{e}]/"
      },
      "work": [
        "\\[{e}|{e}]/",
        "|[{e}|{e}]|",
        "/[{e}|{e}]\\",
        "-[{e}|{e}]-"
      ],
      "workMs": 150,
      "portraits": {
        "0.1": [
          "  ___________",
          " |           |",
          " |   {e}   {e}   |",
          " |    {m}    |",
          " |_[0]{g}______|",
          "   /_\\   /_\\"
        ],
        "1.0": [
          "  ___________",
          " |     |     |",
          " |  {e}  |  {e}  |",
          " |    {m}    |",
          " |_[0]_tim{g}__|",
          "   /_\\   /_\\"
        ],
        "2.0": [
          "  ___________",
          " |     |     |",
          "{a}|  {e}  |  {e}  |{b}",
          " |    {m}    |",
          " |_[0]_tim{g}__|",
          "   /_\\   /_\\"
        ]
      },
      "parts": {
        "a": {
          "rest": "\\",
          "work": [
            "\\",
            "-",
            "/",
            "-"
          ],
          "ms": 150
        },
        "b": {
          "rest": "/",
          "work": [
            "/",
            "-",
            "\\",
            "-"
          ],
          "ms": 150
        }
      },
      "moodParts": {
        "m": {
          "idle": "\\_/",
          "work": "---",
          "need": " o ",
          "done": "\\_/",
          "fail": "/-\\",
          "back": "\\_/",
          "nap": " . ",
          "boop": " O "
        },
        "g": {
          "idle": "*",
          "work": "#",
          "need": "!",
          "done": "*",
          "fail": "!",
          "back": "*",
          "nap": "~",
          "boop": "*"
        }
      },
      "turn": "arms: a twirling baton in the status line, waving in the portrait",
      "examples": {
        "idle": "all quiet. no alerts.",
        "work": "3 panes busy. watching.",
        "need": "codex@office: Bash: npm run migrate  (bell)",
        "done": "silence in codex@office: 3 files changed, tests pass",
        "fail": "codex@office failed: 3 files changed, tests pass  (pane is dead)",
        "back": "reattached. 2 done, 1 waiting 40m.",
        "nap": "detached. reattach any time.",
        "boop": "hey. that's my status line."
      }
    },
    {
      "id": "fish",
      "n": 2,
      "drop": "unix",
      "rarity": "common",
      "color": {
        "xterm": 73,
        "hex": "#5fafaf"
      },
      "shiny": {
        "xterm": 214,
        "hex": "#ffaf00"
      },
      "family": [
        [
          "fish",
          2005
        ],
        [
          "fish 4",
          2025
        ]
      ],
      "lore": "The Friendly Interactive SHell: \"Finally, a command line shell for the 90s.\" Rewritten in Rust for 4.0. It finishes your sentences in grey.",
      "first": "finally, a buddy for the 90s. hi!",
      "lines": {
        "idle": "all quiet in the pond.",
        "work": "{n} swimming along nicely.",
        "need": "{who}: {q}  blub?",
        "done": "{who} finished! {recap}",
        "fail": "{who} failed: {recap}  (sank)",
        "back": "welcome back! {summary}.",
        "nap": "drifting for a bit. blub.",
        "boop": "fish: Unknown command: boop"
      },
      "suggest": {
        "done": " open the diff"
      },
      "sprites": {
        "0.1": "><({e})",
        "1.0": "><({e})>",
        "2.0": "><(({e})>"
      },
      "work": [
        "><(({e})> ",
        "><(({e})>.",
        "><(({e})>o",
        "><(({e})>O"
      ],
      "workMs": 150,
      "portraits": {
        "0.1": [
          "   .--.",
          " ><  {e} >{b}",
          "   '--'"
        ],
        "1.0": [
          "    _.-._",
          " |\\/ (( {e}'.",
          " |  ((    >{b}",
          " |/\\ (( .'",
          "    '-.-'"
        ],
        "2.0": [
          "                     {o}",
          "      _.-\"\"\"-._    {O}",
          " |\\ .'  ((  ((  {e}'.",
          " |  >  ((  ((     >{b}",
          " |/ '.  ((  ((  .'",
          "      '-.___.-'"
        ]
      },
      "parts": {
        "o": {
          "rest": "o",
          "work": [
            " ",
            ".",
            "o",
            "O"
          ],
          "ms": 220
        },
        "O": {
          "rest": "O",
          "work": [
            ".",
            "o",
            "O",
            " "
          ],
          "ms": 220
        }
      },
      "moodParts": {
        "b": {
          "idle": "",
          "work": "",
          "need": " ?",
          "done": " o",
          "fail": "",
          "back": " o",
          "nap": " z",
          "boop": " O"
        }
      },
      "turn": "bubbles, . o O",
      "examples": {
        "idle": "all quiet in the pond.",
        "work": "3 swimming along nicely.",
        "need": "codex@office: Bash: npm run migrate  blub?",
        "done": "codex@office finished! 3 files changed, tests pass",
        "fail": "codex@office failed: 3 files changed, tests pass  (sank)",
        "back": "welcome back! 2 done, 1 waiting 40m.",
        "nap": "drifting for a bit. blub.",
        "boop": "fish: Unknown command: boop"
      }
    },
    {
      "id": "ping",
      "n": 3,
      "drop": "unix",
      "rarity": "common",
      "color": {
        "xterm": 221,
        "hex": "#ffd75f"
      },
      "shiny": {
        "xterm": 39,
        "hex": "#00afff"
      },
      "family": [
        [
          "ping",
          1983
        ]
      ],
      "lore": "Named after the sound of sonar. It shares its name with a 1933 picture book about a duck. It measures every round trip.",
      "first": "PING you (127.0.0.1): hi. you there?",
      "lines": {
        "idle": "0 packets waiting.",
        "work": "{n} in flight.",
        "need": "{who}: {q}  PING",
        "done": "64 bytes from {who}: {recap}",
        "fail": "{who} failed: {recap}  (timeout)",
        "back": "you're back. {summary}.",
        "nap": "floating. no packets for a bit.",
        "boop": "pong."
      },
      "sprites": {
        "0.1": "({e} )>",
        "1.0": "__({e} )>",
        "2.0": "~__({e} )>"
      },
      "work": [
        "~__({e} )>",
        "-__({e} )>",
        ".__({e} )>",
        "-__({e} )>"
      ],
      "workMs": 150,
      "portraits": {
        "0.1": [
          "   .-.",
          "  ( {e} )>",
          " ,-) (.",
          " \\ '-' )",
          "  '---'"
        ],
        "1.0": [
          "      .-.",
          "     ( {e} )>",
          "  ,   )  (",
          "  |\\.'    '.",
          "   \\  '--'  )",
          "    '-.__.-'"
        ],
        "2.0": [
          "      .-.",
          "     ( {e} )> {s}",
          "  ,   )  (",
          "  |\\.'    '.",
          " _.\\  '--'  )._",
          "  {w}"
        ]
      },
      "parts": {
        "w": {
          "rest": "~^~-~^~-~^~-~",
          "work": [
            "~^~-~^~-~^~-~",
            "^~-~^~-~^~-~^",
            "~-~^~-~^~-~^~",
            "-~^~-~^~-~^~-"
          ],
          "ms": 200
        }
      },
      "moodParts": {
        "s": {
          "idle": "",
          "work": "",
          "need": "  ) ) )",
          "done": "",
          "fail": "",
          "back": "",
          "nap": "",
          "boop": ""
        }
      },
      "turn": "ripples, ~ ^ -",
      "examples": {
        "idle": "0 packets waiting.",
        "work": "3 in flight.",
        "need": "codex@office: Bash: npm run migrate  PING",
        "done": "64 bytes from codex@office: 3 files changed, tests pass",
        "fail": "codex@office failed: 3 files changed, tests pass  (timeout)",
        "back": "you're back. 2 done, 1 waiting 40m.",
        "nap": "floating. no packets for a bit.",
        "boop": "pong."
      }
    },
    {
      "id": "bat",
      "n": 4,
      "drop": "unix",
      "rarity": "common",
      "color": {
        "xterm": 103,
        "hex": "#8787af"
      },
      "shiny": {
        "xterm": 254,
        "hex": "#e4e4e4"
      },
      "family": [
        [
          "cat",
          1971
        ],
        [
          "bat",
          2018
        ]
      ],
      "lore": "cat has printed files since Unix v1. bat calls itself \"a cat(1) clone with wings.\" It hatches as a kitten; the wings ship in 2.0.",
      "first": "a cat(1) clone, with wings. i'll take it from here.",
      "lines": {
        "idle": "watching from above.",
        "work": "{n} busy. watching from above.",
        "need": "{who}: {q}",
        "done": "{who} finished. highlighted: {recap}",
        "fail": "{who} failed: {recap}",
        "back": "you're back. {summary}. i kept the lights low.",
        "nap": "hanging upside down for a bit.",
        "boop": "...rude."
      },
      "sprites": {
        "0.1": "({e}.{e})",
        "1.0": "=({e}.{e})=",
        "2.0": "/({e}.{e})\\"
      },
      "work": [
        "/({e}.{e})\\",
        "-({e}.{e})-",
        "\\({e}.{e})/",
        "-({e}.{e})-"
      ],
      "workMs": 150,
      "portraits": {
        "0.1": [
          "  /|   |\\",
          " ( {e} . {e} )",
          "  =\\ w /="
        ],
        "1.0": [
          "   /|     |\\",
          "  / '.___.' \\",
          " |  {e}  .  {e}  |",
          " =\\    w    /=",
          "   '-.___.-'",
          "     |   |  )",
          "     |_|_|_/"
        ],
        "2.0": [
          "         /|     |\\",
          " {l}     / '.___.' \\     {r}",
          "/  '-._|  {e}  .  {e}  |_.-'  \\",
          "\\/\\/\\/ =\\    w    /= \\/\\/\\/",
          "         '-.___.-'",
          "          |_| |_|"
        ]
      },
      "parts": {
        "l": {
          "rest": "/\\",
          "work": [
            "/\\",
            "__",
            "\\/",
            "__"
          ],
          "ms": 150
        },
        "r": {
          "rest": "/\\",
          "work": [
            "/\\",
            "__",
            "\\/",
            "__"
          ],
          "ms": 150
        }
      },
      "turn": "wings, flapping",
      "examples": {
        "idle": "watching from above.",
        "work": "3 busy. watching from above.",
        "need": "codex@office: Bash: npm run migrate",
        "done": "codex@office finished. highlighted: 3 files changed, tests pass",
        "fail": "codex@office failed: 3 files changed, tests pass",
        "back": "you're back. 2 done, 1 waiting 40m. i kept the lights low.",
        "nap": "hanging upside down for a bit.",
        "boop": "...rude."
      }
    },
    {
      "id": "vim",
      "n": 5,
      "drop": "unix",
      "rarity": "rare",
      "color": {
        "xterm": 107,
        "hex": "#87af5f"
      },
      "shiny": {
        "xterm": 226,
        "hex": "#ffff00"
      },
      "family": [
        [
          "ed",
          1969
        ],
        [
          "vi",
          1976
        ],
        [
          "vim",
          1991
        ]
      ],
      "lore": "ed begat vi, and vi begat vim, Vi IMproved. The ~ marks lines past the end of the buffer. Famous for being hard to leave.",
      "first": "hi. i'm vim. no, you can't exit me. :help pairing",
      "lines": {
        "idle": "--No lines in buffer--",
        "work": "-- INSERT -- {n} agents typing.",
        "need": "{who}: {q}  E325",
        "done": "\"{who}\" written. {recap}",
        "fail": "{who} failed: {recap}  (1 of 1)",
        "back": ":earlier  {summary}.",
        "nap": ":sleep 900",
        "boop": "-- VISUAL -- you selected me."
      },
      "sprites": {
        "0.1": "~ {e}_{e}",
        "1.0": "< {e}_{e} >",
        "2.0": "< {e}_{e} >_"
      },
      "work": [
        "< {e}_{e} >_",
        "< {e}_{e} > "
      ],
      "workMs": 400,
      "portraits": {
        "0.1": [
          "~    .",
          "~  .' '.",
          "~ < {e} {e} >",
          "~  '.v.'",
          "~    '",
          "~"
        ],
        "1.0": [
          "~      /\\",
          "~    .'  '.",
          "~   < {e}  {e} >",
          "~    '.\\/.'",
          "~      \\/",
          "~",
          "{mode}"
        ],
        "2.0": [
          "~      /\\",
          "~    .'  '.",
          "~   < {e}  {e} >{k}",
          "~    '.\\/.'",
          "~      \\/",
          "~",
          " [No Name] [+]    1,1  All",
          "{mode}"
        ]
      },
      "parts": {
        "k": {
          "rest": "_",
          "work": [
            "_",
            " "
          ],
          "ms": 400
        }
      },
      "moodParts": {
        "mode": {
          "idle": "",
          "work": "-- INSERT --",
          "need": "(y/n/a/q/l/^E/^Y)?",
          "done": "\"pair.log\" 3L, 64B written",
          "fail": "E492: Not an editor command",
          "back": ":earlier 40m",
          "nap": ":sleep 900",
          "boop": "-- VISUAL --"
        }
      },
      "turn": "a blinking cursor, _",
      "examples": {
        "idle": "--No lines in buffer--",
        "work": "-- INSERT -- 3 agents typing.",
        "need": "codex@office: Bash: npm run migrate  E325",
        "done": "\"codex@office\" written. 3 files changed, tests pass",
        "fail": "codex@office failed: 3 files changed, tests pass  (1 of 1)",
        "back": ":earlier  2 done, 1 waiting 40m.",
        "nap": ":sleep 900",
        "boop": "-- VISUAL -- you selected me."
      }
    },
    {
      "id": "zsh",
      "n": 6,
      "drop": "unix",
      "rarity": "rare",
      "color": {
        "xterm": 173,
        "hex": "#d7875f"
      },
      "shiny": {
        "xterm": 134,
        "hex": "#af5fd7"
      },
      "family": [
        [
          "sh",
          1979
        ],
        [
          "ksh",
          1983
        ],
        [
          "zsh",
          1990
        ]
      ],
      "lore": "A hermit crab that keeps moving into better shells: the Bourne shell, the Korn shell, then zsh, named after a teaching assistant's login.",
      "first": "the default interactive shell is now zsh. hi.",
      "lines": {
        "idle": "no jobs.",
        "work": "{n} jobs running in the background.",
        "need": "{who}: {q}  [suspended]",
        "done": "[1]  + done       {who}  {recap}",
        "fail": "{who} failed: {recap}  [exit 1]",
        "back": "you were away. {summary}. i autocorrected nothing.",
        "nap": "moving into a quieter shell for a bit.",
        "boop": "zsh: command not found: boop"
      },
      "sprites": {
        "0.1": "@ {e},,{e}",
        "1.0": "@v{e},,{e}v",
        "2.0": "@V{e},,{e}V"
      },
      "work": [
        "@V{e},,{e}V",
        "@v{e},,{e}v"
      ],
      "workMs": 260,
      "portraits": {
        "0.1": [
          "    .-.",
          "   ( @ )",
          " v({e},,{e})v",
          "   /\\/\\"
        ],
        "1.0": [
          "       .--.",
          "     .' .-.'.",
          "    /  ( @ ) \\",
          "   '.   '-'  .'",
          " ({c})({e} ,, {e})({c})",
          "     /\\/  \\/\\"
        ],
        "2.0": [
          " ({c})    _.---._    ({c})",
          "  \\ \\  .'  .-.  '.  / /",
          "   \\ \\/   ( @ )   \\/ /",
          "    \\ |    '-'    | /",
          "     '.({e}  ,,,  {e}).'",
          "       /\\/\\/   \\/\\/\\"
        ]
      },
      "parts": {
        "c": {
          "rest": "\\/",
          "work": [
            "\\/",
            "/\\"
          ],
          "ms": 260
        }
      },
      "turn": "claws, (\\/) (/\\) snapping",
      "examples": {
        "idle": "no jobs.",
        "work": "3 jobs running in the background.",
        "need": "codex@office: Bash: npm run migrate  [suspended]",
        "done": "[1]  + done       codex@office  3 files changed, tests pass",
        "fail": "codex@office failed: 3 files changed, tests pass  [exit 1]",
        "back": "you were away. 2 done, 1 waiting 40m. i autocorrected nothing.",
        "nap": "moving into a quieter shell for a bit.",
        "boop": "zsh: command not found: boop"
      }
    },
    {
      "id": "biff",
      "n": 7,
      "drop": "unix",
      "rarity": "rare",
      "color": {
        "xterm": 180,
        "hex": "#d7af87"
      },
      "shiny": {
        "xterm": 130,
        "hex": "#af5f00"
      },
      "family": [
        [
          "biff",
          1980
        ]
      ],
      "lore": "biff told Berkeley Unix users when mail arrived (4.0BSD). It was named after a dog who barked at the mail carrier, and `biff y` switched it on. Now it barks when an agent needs you.",
      "first": "woof. i'm biff. i bark when you have mail. and agents.",
      "lines": {
        "idle": "watching the door.",
        "work": "{n} inside. i hear them working.",
        "need": "{who}: {q}  woof",
        "done": "{who}'s done! good agent! {recap}",
        "fail": "{who} failed: {recap}  grr",
        "back": "you're back! {summary}.",
        "nap": "lying down by the door.",
        "boop": "woof."
      },
      "sprites": {
        "0.1": "U{e}w{e}U",
        "1.0": "U({e}w{e})U",
        "2.0": "U({e}w{e})U~"
      },
      "work": [
        "U({e}w{e})U~",
        "U({e}w{e})U/",
        "U({e}w{e})U|",
        "U({e}w{e})U\\"
      ],
      "workMs": 150,
      "portraits": {
        "0.1": [
          "   .-.___.-.",
          "  ( /     \\ )",
          "   '| {e} {e} |'",
          "    \\ (_) /",
          "     '{m}'"
        ],
        "1.0": [
          "   .-.  ___  .-.",
          "  / / .'   '. \\ \\",
          " | | / {e}   {e} \\ | |",
          "  \\_\\|  (_)  |/_/",
          "      \\ {m} /",
          "       '---'"
        ],
        "2.0": [
          "   .-.  ___  .-.",
          "  / / .'   '. \\ \\",
          " | | / {e}   {e} \\ | |",
          "  \\_\\|  (_)  |/_/",
          "      \\ {m} /",
          "     .-'---'-.",
          "    (  |   |  )_{t}",
          "     '-'   '-'"
        ]
      },
      "parts": {
        "t": {
          "rest": "~",
          "work": [
            "~",
            "/",
            "|",
            "\\"
          ],
          "ms": 150
        }
      },
      "moodParts": {
        "m": {
          "idle": "\\_/",
          "work": "\\_/",
          "need": "\\O/",
          "done": "\\U/",
          "fail": ".-.",
          "back": "\\U/",
          "nap": "\\_/",
          "boop": "\\U/"
        }
      },
      "turn": "tail, ~ / | \\ wagging",
      "examples": {
        "idle": "watching the door.",
        "work": "3 inside. i hear them working.",
        "need": "codex@office: Bash: npm run migrate  woof",
        "done": "codex@office's done! good agent! 3 files changed, tests pass",
        "fail": "codex@office failed: 3 files changed, tests pass  grr",
        "back": "you're back! 2 done, 1 waiting 40m.",
        "nap": "lying down by the door.",
        "boop": "woof."
      }
    },
    {
      "id": "fzf",
      "n": 8,
      "drop": "unix",
      "rarity": "legendary",
      "color": {
        "xterm": 110,
        "hex": "#87afd7"
      },
      "shiny": {
        "xterm": 161,
        "hex": "#d7005f"
      },
      "family": [
        [
          "find",
          1974
        ],
        [
          "fzf",
          2013
        ]
      ],
      "lore": "find has walked directory trees since 1974. fzf finds things fuzzily, shows its match count, and keeps the best match next to the prompt.",
      "first": "> hello   1/1   it's me, fzf. i find things.",
      "lines": {
        "idle": "0/0. nothing to find.",
        "work": "{n} busy. filtering out the noise.",
        "need": "{who}: {q}  1/1",
        "done": "match: {who}  {recap}",
        "fail": "{who} failed: {recap}  0/1",
        "back": "{summary}. best match at the bottom, as always.",
        "nap": "no query. resting.",
        "boop": "> boop  0/0"
      },
      "sprites": {
        "0.1": ";{e};{e};",
        "1.0": ",;{e};{e};,",
        "2.0": "> ;{e};{e};"
      },
      "work": [
        "> ;{e};{e};",
        "> ,{e},{e},",
        "> '{e}'{e}'",
        "> ,{e},{e},"
      ],
      "workMs": 180,
      "portraits": {
        "0.1": [
          "   ,;:;,",
          "  ; {e} {e} ;",
          "   ':;:'"
        ],
        "1.0": [
          "    ,;:;:;:;,",
          "  ,;'       ';,",
          "  ;:  {e}   {e}  :;",
          "  ':,   .   ,:'",
          "    ';:;:;:;'"
        ],
        "2.0": [
          "    {f}",
          "  ,;'       ';,",
          "  ;:  {e}   {e}  :;",
          "  ':,   .   ,:'",
          "    ';:;:;:;'",
          "  {n}",
          "> _"
        ]
      },
      "parts": {
        "f": {
          "rest": ",;:;:;:;,",
          "work": [
            ",;:;:;:;,",
            ";:;:;:;:;",
            ":;:;:;:;:"
          ],
          "ms": 180
        }
      },
      "moodParts": {
        "n": {
          "idle": "0/0",
          "work": "3/12",
          "need": "1/1",
          "done": "1/1",
          "fail": "0/1",
          "back": "4/7",
          "nap": "0/0",
          "boop": "0/0"
        }
      },
      "turn": "fuzz, ; : , '",
      "examples": {
        "idle": "0/0. nothing to find.",
        "work": "3 busy. filtering out the noise.",
        "need": "codex@office: Bash: npm run migrate  1/1",
        "done": "match: codex@office  3 files changed, tests pass",
        "fail": "codex@office failed: 3 files changed, tests pass  0/1",
        "back": "2 done, 1 waiting 40m. best match at the bottom, as always.",
        "nap": "no query. resting.",
        "boop": "> boop  0/0"
      }
    },
    {
      "id": "tldr",
      "n": 9,
      "drop": "unix",
      "rarity": "legendary",
      "color": {
        "xterm": 179,
        "hex": "#d7af5f"
      },
      "shiny": {
        "xterm": 118,
        "hex": "#87ff00"
      },
      "family": [
        [
          "man",
          1971
        ],
        [
          "tldr",
          2013
        ]
      ],
      "lore": "man pages date from the first Unix Programmer's Manual. tldr pages are the short version: a few examples, no essay. It gets smaller with every release.",
      "first": "tldr: hi.",
      "lines": {
        "idle": "nothing.",
        "work": "{n} working.",
        "need": "{who}: {q}",
        "done": "{who}: done.",
        "fail": "{who} failed: {recap}",
        "back": "tl;dr {summary}.",
        "nap": "zz.",
        "boop": "no."
      },
      "sprites": {
        "0.1": "({e})v({e})",
        "1.0": "({e}v{e})",
        "2.0": "{e}v{e}"
      },
      "work": [
        "{e}v{e} |",
        "{e}v{e} /",
        "{e}v{e} -",
        "{e}v{e} \\"
      ],
      "workMs": 130,
      "portraits": {
        "0.1": [
          "   \\             /",
          "   |'-._______.-'|",
          "   |  .-.   .-.  |",
          "   | ( {e} ) ( {e} ) |",
          "   |  '-' v '-'  |",
          "    \\  \\/\\/\\/\\  /",
          "     '-.m___m.-'",
          "   [____MAN(1)___]"
        ],
        "1.0": [
          "   \\       /",
          "   |'-._.-'|",
          "   |({e}) ({e})|",
          "   \\   v   /",
          "    '-m-m-'",
          "    [tldr]"
        ],
        "2.0": [
          "  \\ /",
          " ({e}v{e})",
          "  m m",
          " tl;dr"
        ]
      },
      "turn": "a twirling baton beside it",
      "examples": {
        "idle": "nothing.",
        "work": "3 working.",
        "need": "codex@office: Bash: npm run migrate",
        "done": "codex@office: done.",
        "fail": "codex@office failed: 3 files changed, tests pass",
        "back": "tl;dr 2 done, 1 waiting 40m.",
        "nap": "zz.",
        "boop": "no."
      }
    },
    {
      "id": "grue",
      "n": 10,
      "drop": "unix",
      "rarity": "secret",
      "color": {
        "xterm": 246,
        "hex": "#949494"
      },
      "shiny": {
        "xterm": 93,
        "hex": "#8700ff"
      },
      "family": [
        [
          "grue",
          1977
        ]
      ],
      "lore": "Zork, MIT: \"It is pitch black. You are likely to be eaten by a grue.\" Nobody has seen one. It hatches only from eggs found in the dark, and shows up only in a dark theme.",
      "first": "it is pitch black. you are likely to be paired with a grue.",
      "lines": {
        "idle": "...",
        "work": "it is dark. {n} are working. i can hear them.",
        "need": "{who}: {q}  (in the dark)",
        "done": "the lamp is lit. {who} is done.",
        "fail": "{who} failed: {recap}  (eaten)",
        "back": "you have moved into a dark place.",
        "nap": "...",
        "boop": "you touched something in the dark."
      },
      "eyes": {
        "idle": ".",
        "work": ".",
        "need": "o",
        "done": "*",
        "fail": "x",
        "back": "o",
        "nap": " ",
        "boop": "O"
      },
      "lid": " ",
      "darkOnly": true,
      "sprites": {
        "0.1": "{e} {e}",
        "1.0": "{e}  {e}",
        "2.0": "{e}   {e}"
      },
      "work": [
        "{e}   {e}",
        "    {e}",
        "{e}   {e}",
        "{e}    "
      ],
      "workMs": 300,
      "portraits": {
        "0.1": [
          "",
          "    {e} {e}"
        ],
        "1.0": [
          "",
          "",
          "    {e}       {e}"
        ],
        "2.0": [
          "       ,  '  '  '  ,       ",
          "    '                 `    ",
          "  ,     {e}         {e}     ,  ",
          "    `     {t}     '    ",
          "       '  ,  ,  ,  '       "
        ]
      },
      "moodParts": {
        "t": {
          "idle": "       ",
          "work": "       ",
          "need": "       ",
          "done": "       ",
          "fail": "vVvVvVv",
          "back": "       ",
          "nap": "       ",
          "boop": "       "
        }
      },
      "turn": "eyes, flickering",
      "examples": {
        "idle": "...",
        "work": "it is dark. 3 are working. i can hear them.",
        "need": "codex@office: Bash: npm run migrate  (in the dark)",
        "done": "the lamp is lit. codex@office is done.",
        "fail": "codex@office failed: 3 files changed, tests pass  (eaten)",
        "back": "you have moved into a dark place.",
        "nap": "...",
        "boop": "you touched something in the dark."
      }
    },
    {
      "id": "xeyes",
      "n": 1,
      "drop": "tty",
      "rarity": "common",
      "color": {
        "xterm": 153,
        "hex": "#afd7ff"
      },
      "shiny": {
        "xterm": 201,
        "hex": "#ff00ff"
      },
      "family": [
        [
          "X11",
          1987
        ],
        [
          "xeyes",
          1988
        ]
      ],
      "lore": "Keith Packard's X11 eyes (1988) follow your pointer around the screen, copied, its man page says, from a NeWS demo seen at SIGGRAPH '88. These look toward whatever changed.",
      "first": "i see you. i keep an eye on things. two, actually.",
      "lines": {
        "idle": "looking around. nothing moved.",
        "work": "{n} busy. eyes on them.",
        "need": "{who}: {q}  (over there)",
        "done": "{who} finished. saw it: {recap}",
        "fail": "{who} failed: {recap}  (saw that)",
        "back": "there you are. {summary}.",
        "nap": "eyes shut for a bit.",
        "boop": "ow. my eye."
      },
      "sprites": {
        "0.1": "({e})({e})",
        "1.0": "(({e})({e}))",
        "2.0": "( {e})( {e})"
      },
      "work": [
        "({e} )({e} )",
        "( {e})( {e})"
      ],
      "workMs": 300,
      "portraits": {
        "0.1": [
          "  .---.  .---.",
          " ({a}{c}{e}{d}{b})({a}{c}{e}{d}{b})",
          "  '---'  '---'"
        ],
        "1.0": [
          "   .---.   .---.",
          "  /     \\ /     \\ ",
          " | {a}{c}{e}{d}{b} | {a}{c}{e}{d}{b} |",
          "  \\     / \\     /",
          "   '---'   '---'"
        ],
        "2.0": [
          ".-[ xeyes ]-------------.",
          "|     .---.   .---.     |",
          "|    /     \\ /     \\    |",
          "|   | {a}{c}{e}{d}{b} | {a}{c}{e}{d}{b} |   |",
          "|    \\     / \\     /    |",
          "|     '---'   '---'     |",
          "|{p}|",
          "'-----------------------'"
        ]
      },
      "parts": {
        "c": {
          "rest": " ",
          "work": [
            "",
            " ",
            "  ",
            " "
          ],
          "ms": 300
        },
        "d": {
          "rest": " ",
          "work": [
            "  ",
            " ",
            "",
            " "
          ],
          "ms": 300
        },
        "p": {
          "rest": "           X           ",
          "work": [
            "    X                  ",
            "           X           ",
            "                  X    ",
            "           X           "
          ],
          "ms": 300
        }
      },
      "moodParts": {
        "a": {
          "idle": " ",
          "work": " ",
          "need": "",
          "done": "",
          "fail": "",
          "back": "  ",
          "nap": " ",
          "boop": " "
        },
        "b": {
          "idle": " ",
          "work": " ",
          "need": "  ",
          "done": "  ",
          "fail": "  ",
          "back": "",
          "nap": " ",
          "boop": " "
        }
      },
      "turn": "pupils, following the pointer",
      "examples": {
        "idle": "looking around. nothing moved.",
        "work": "3 busy. eyes on them.",
        "need": "codex@office: Bash: npm run migrate  (over there)",
        "done": "codex@office finished. saw it: 3 files changed, tests pass",
        "fail": "codex@office failed: 3 files changed, tests pass  (saw that)",
        "back": "there you are. 2 done, 1 waiting 40m.",
        "nap": "eyes shut for a bit.",
        "boop": "ow. my eye."
      }
    },
    {
      "id": "oneko",
      "n": 2,
      "drop": "tty",
      "rarity": "common",
      "color": {
        "xterm": 223,
        "hex": "#ffd7af"
      },
      "shiny": {
        "xterm": 172,
        "hex": "#d78700"
      },
      "family": [
        [
          "neko",
          1989
        ],
        [
          "oneko",
          1990
        ]
      ],
      "lore": "Neko is Japanese for cat. It began on the NEC PC-9801, reached the Mac in 1989 and X11 as oneko: a cat that chases your pointer and falls asleep when it stops.",
      "first": "mew. i chase whatever moves.",
      "lines": {
        "idle": "sitting. scratching an ear.",
        "work": "{n} moving. chasing them.",
        "need": "{who}: {q}  mew?",
        "done": "{who} finished. caught it: {recap}",
        "fail": "{who} failed: {recap}  hiss",
        "back": "you moved! {summary}.",
        "nap": "the pointer stopped. zzz.",
        "boop": "mrrp."
      },
      "sprites": {
        "0.1": "'{e}.{e}'",
        "1.0": "^'{e}.{e}'^",
        "2.0": "^'{e}.{e}'^~"
      },
      "work": [
        "^'{e}.{e}'^~",
        "^'{e}.{e}'^)",
        "^'{e}.{e}'^~",
        "^'{e}.{e}'^("
      ],
      "workMs": 200,
      "portraits": {
        "0.1": [
          "  /\\_/\\ ",
          " ( {e}.{e} )",
          "  > ^ <"
        ],
        "1.0": [
          "   /\\_/\\ ",
          "  ( {e}.{e} )",
          "   > ^ <",
          "  /     \\ ",
          " (  | |  )~",
          "  '-'-'-'"
        ],
        "2.0": [
          "           {z}",
          "   /\\_/\\ ",
          "  ( {e}.{e} )",
          "   > ^ <",
          "  /     \\ ",
          " (  | |  )_{t}",
          "  '-'-'-'"
        ]
      },
      "parts": {
        "t": {
          "rest": "~",
          "work": [
            "~",
            ")",
            "~",
            "("
          ],
          "ms": 200
        }
      },
      "moodParts": {
        "z": {
          "idle": "",
          "work": "",
          "need": "",
          "done": "",
          "fail": "",
          "back": "",
          "nap": "z Z",
          "boop": ""
        }
      },
      "turn": "tail, swishing",
      "examples": {
        "idle": "sitting. scratching an ear.",
        "work": "3 moving. chasing them.",
        "need": "codex@office: Bash: npm run migrate  mew?",
        "done": "codex@office finished. caught it: 3 files changed, tests pass",
        "fail": "codex@office failed: 3 files changed, tests pass  hiss",
        "back": "you moved! 2 done, 1 waiting 40m.",
        "nap": "the pointer stopped. zzz.",
        "boop": "mrrp."
      }
    },
    {
      "id": "cowsay",
      "n": 3,
      "drop": "tty",
      "rarity": "common",
      "color": {
        "xterm": 151,
        "hex": "#afd7af"
      },
      "shiny": {
        "xterm": 177,
        "hex": "#d787ff"
      },
      "family": [
        [
          "cowsay",
          1999
        ]
      ],
      "lore": "Tony Monroe's Perl script (1999) draws a cow saying whatever you pipe to it. Its eyes and tongue are options: -e, -T, and -d for dead. cowthink gives it a thought bubble.",
      "first": "< moo. i say whatever you pipe me. >",
      "lines": {
        "idle": "< moo >",
        "work": "< {n} busy. chewing on it. >",
        "need": "{who}: {q}  moo?",
        "done": "< {who} done: {recap} >",
        "fail": "{who} failed: {recap}  (cowsay -d)",
        "back": "< welcome back. {summary}. >",
        "nap": "( zzz )",
        "boop": "< moo! >"
      },
      "sprites": {
        "0.1": "{e}__{e}",
        "1.0": "({e}__{e})",
        "2.0": "^({e}__{e})^"
      },
      "work": [
        "^({e}__{e})^",
        "^({e}--{e})^"
      ],
      "workMs": 350,
      "portraits": {
        "0.1": [
          "  ^___^",
          "  ({e} {e})",
          "  (___)",
          "   {t}"
        ],
        "1.0": [
          "  ^___^",
          "  ({e} {e})\\_______",
          "  (___)\\       )\\/\\ ",
          "   {t}  |----w |",
          "       |      |"
        ],
        "2.0": [
          " _______",
          "{b}",
          " -------",
          "     \\  ^___^",
          "      \\ ({e} {e})\\_______",
          "        (___)\\       )\\/\\ ",
          "         {t}  |----w |",
          "            |      |"
        ]
      },
      "moodParts": {
        "b": {
          "idle": "<  moo  >",
          "work": "<  ...  >",
          "need": "<  moo? >",
          "done": "<  moo! >",
          "fail": "<  moo. >",
          "back": "<  hi!  >",
          "nap": "(  zzz  )",
          "boop": "<  MOO  >"
        },
        "t": {
          "idle": " ",
          "work": " ",
          "need": " ",
          "done": " ",
          "fail": "U",
          "back": " ",
          "nap": " ",
          "boop": " "
        }
      },
      "turn": "mouth, chewing the cud",
      "examples": {
        "idle": "< moo >",
        "work": "< 3 busy. chewing on it. >",
        "need": "codex@office: Bash: npm run migrate  moo?",
        "done": "< codex@office done: 3 files changed, tests pass >",
        "fail": "codex@office failed: 3 files changed, tests pass  (cowsay -d)",
        "back": "< welcome back. 2 done, 1 waiting 40m. >",
        "nap": "( zzz )",
        "boop": "< moo! >"
      }
    },
    {
      "id": "fortune",
      "n": 4,
      "drop": "tty",
      "rarity": "common",
      "color": {
        "xterm": 222,
        "hex": "#ffd787"
      },
      "shiny": {
        "xterm": 167,
        "hex": "#d75f5f"
      },
      "family": [
        [
          "fortune",
          1979
        ]
      ],
      "lore": "fortune has printed a random saying at login since Version 7 Unix (1979); BSD fortune files put each one between lines holding a single %. Every welcome back comes with one.",
      "first": "your fortune: you will meet a new friend today.",
      "lines": {
        "idle": "no fortune yet.",
        "work": "{n} at work. the future is compiling.",
        "need": "{who}: {q}  (a fortune awaits)",
        "done": "{who} done: {recap}. good fortune.",
        "fail": "{who} failed: {recap}  (bad fortune)",
        "back": "while you were out: {summary}. a watched build never finishes.",
        "nap": "sleeping on it.",
        "boop": "you crack me open. it says: boop."
      },
      "sprites": {
        "0.1": "%{e} {e}%",
        "1.0": "(%{e} {e}%)",
        "2.0": "(%{e} {e}%)-"
      },
      "work": [
        "(%{e} {e}%) ",
        "(%{e} {e}%)-",
        "(%{e} {e}%)=",
        "(%{e} {e}%)-"
      ],
      "workMs": 250,
      "portraits": {
        "0.1": [
          "    _.---._",
          "  .' {e}   {e} '.",
          " (_.-.___.-._)"
        ],
        "1.0": [
          "      _.-----._",
          "    .'  {e}   {e}  '.",
          "   /      v      \\ ",
          "  (_.--._____.--._)"
        ],
        "2.0": [
          "      _.-----._",
          "    .'  {e}   {e}  '.",
          "   /      v      \\ ",
          "  (_.--._____.--._)",
          "        \\__%__/",
          "    [ {f} ]",
          "       %"
        ]
      },
      "moodParts": {
        "f": {
          "idle": "   patience.   ",
          "work": "  busy hands.  ",
          "need": "you are needed.",
          "done": " good fortune. ",
          "fail": "  misfortune.  ",
          "back": " welcome back. ",
          "nap": "   rest well.  ",
          "boop": "    crack!     "
        }
      },
      "turn": "the slip, sliding out",
      "examples": {
        "idle": "no fortune yet.",
        "work": "3 at work. the future is compiling.",
        "need": "codex@office: Bash: npm run migrate  (a fortune awaits)",
        "done": "codex@office done: 3 files changed, tests pass. good fortune.",
        "fail": "codex@office failed: 3 files changed, tests pass  (bad fortune)",
        "back": "while you were out: 2 done, 1 waiting 40m. a watched build never finishes.",
        "nap": "sleeping on it.",
        "boop": "you crack me open. it says: boop."
      }
    },
    {
      "id": "rogue",
      "n": 5,
      "drop": "tty",
      "rarity": "rare",
      "color": {
        "xterm": 174,
        "hex": "#d78787"
      },
      "shiny": {
        "xterm": 220,
        "hex": "#ffd700"
      },
      "family": [
        [
          "rogue",
          1980
        ]
      ],
      "lore": "Rogue (1980), by Michael Toy and Glenn Wichman with Ken Arnold, drew a dungeon with curses and made you the @. It shipped with 4.2BSD and named a genre. The mood is whatever lies next to you: gold *, a scroll ?, a trap ^.",
      "first": "welcome to the Dungeons of Doom. you are the @.",
      "lines": {
        "idle": "a quiet room.",
        "work": "{n} in the corridors.",
        "need": "{who}: {q}  --More--",
        "done": "{who} done: {recap}. that was gold.",
        "fail": "{who} failed: {recap}  (a trap)",
        "back": "back up the stairs. {summary}.",
        "nap": "resting in a dark room.",
        "boop": "you touch the @. it is you."
      },
      "eyes": {
        "idle": ".",
        "work": ")",
        "need": "?",
        "done": "*",
        "fail": "^",
        "back": "%",
        "nap": " ",
        "boop": "!"
      },
      "lid": ".",
      "sprites": {
        "0.1": "@{e}",
        "1.0": "|.@{e}.|",
        "2.0": "##@{e}##"
      },
      "work": [
        "##@{e}##",
        "##@{e}K#",
        "##@{e}##",
        "##@{e}B#"
      ],
      "workMs": 300,
      "portraits": {
        "0.1": [
          " -------",
          " |.....|",
          " |.@{e}..|",
          " |.....|",
          " -------"
        ],
        "1.0": [
          " ----------",
          " |........|",
          " |..@{e}.....+###",
          " |........|",
          " ----------"
        ],
        "2.0": [
          "{m}",
          " -------          -------",
          " |.....|          |.....|",
          " |.....+###@{e}{w}+..*..|",
          " |.....|          |.....|",
          " -------          -------",
          "Level: 3 Gold: 42 Hp: 12(12)"
        ]
      },
      "parts": {
        "w": {
          "rest": "####",
          "work": [
            "    ",
            "#   ",
            "##  ",
            "### "
          ],
          "ms": 300
        }
      },
      "moodParts": {
        "m": {
          "idle": "",
          "work": "",
          "need": "--More--",
          "done": "",
          "fail": "",
          "back": "",
          "nap": "",
          "boop": ""
        }
      },
      "turn": "the corridor, drawn as you walk it",
      "examples": {
        "idle": "a quiet room.",
        "work": "3 in the corridors.",
        "need": "codex@office: Bash: npm run migrate  --More--",
        "done": "codex@office done: 3 files changed, tests pass. that was gold.",
        "fail": "codex@office failed: 3 files changed, tests pass  (a trap)",
        "back": "back up the stairs. 2 done, 1 waiting 40m.",
        "nap": "resting in a dark room.",
        "boop": "you touch the @. it is you."
      }
    },
    {
      "id": "sl",
      "n": 6,
      "drop": "tty",
      "rarity": "rare",
      "color": {
        "xterm": 250,
        "hex": "#bcbcbc"
      },
      "shiny": {
        "xterm": 117,
        "hex": "#87d7ff"
      },
      "family": [
        [
          "ls",
          1971
        ],
        [
          "sl",
          1993
        ]
      ],
      "lore": "Type sl for ls and a steam locomotive crosses your terminal (Toyoda Masashi, 1993). It ignores Ctrl-C. Its smoke ages as it drifts; sl -a has an accident, and people cry for help.",
      "first": "choo choo. you meant ls. too late.",
      "lines": {
        "idle": "the line is clear.",
        "work": "{n} on the rails. full steam.",
        "need": "{who}: {q}  (whistle)",
        "done": "{who} arrived: {recap}",
        "fail": "{who} failed: {recap}  (Help!)",
        "back": "all aboard. {summary}.",
        "nap": "in the roundhouse.",
        "boop": "you meant ls."
      },
      "sprites": {
        "0.1": "({e}_]",
        "1.0": "({e}n_]",
        "2.0": "({e}n__]~"
      },
      "work": [
        "({e}n__]@",
        "({e}n__]o",
        "({e}n__].",
        "({e}n__] "
      ],
      "workMs": 250,
      "portraits": {
        "0.1": [
          "    n",
          " .-'|__",
          "( {e}  []|",
          " 'o--o-'"
        ],
        "1.0": [
          "      n",
          " .--'|------.__",
          "( {e}        |[]|",
          " '-.______.|__|",
          "  (O)(O)  (O)(O)"
        ],
        "2.0": [
          "        {s}",
          "      n",
          " .--'|------.__",
          "( {e}        |[]|{h}",
          " '-.______.|__|",
          "  (O)(O)  (O)(O)"
        ]
      },
      "parts": {
        "s": {
          "rest": "(@@) (@) @ .",
          "work": [
            "(@@@) (@@)  (@)",
            " (@@)  (@)   @ ",
            "  (@)   @    . ",
            "   @    .      "
          ],
          "ms": 250
        }
      },
      "moodParts": {
        "h": {
          "idle": "",
          "work": "",
          "need": "",
          "done": "",
          "fail": " \\O/ Help!",
          "back": "",
          "nap": "",
          "boop": ""
        }
      },
      "turn": "smoke, ageing as it drifts",
      "examples": {
        "idle": "the line is clear.",
        "work": "3 on the rails. full steam.",
        "need": "codex@office: Bash: npm run migrate  (whistle)",
        "done": "codex@office arrived: 3 files changed, tests pass",
        "fail": "codex@office failed: 3 files changed, tests pass  (Help!)",
        "back": "all aboard. 2 done, 1 waiting 40m.",
        "nap": "in the roundhouse.",
        "boop": "you meant ls."
      }
    },
    {
      "id": "doctor",
      "n": 7,
      "drop": "tty",
      "rarity": "rare",
      "color": {
        "xterm": 146,
        "hex": "#afafd7"
      },
      "shiny": {
        "xterm": 227,
        "hex": "#ffff5f"
      },
      "family": [
        [
          "ELIZA",
          1966
        ],
        [
          "doctor",
          1985
        ]
      ],
      "lore": "Joseph Weizenbaum's ELIZA (MIT, 1964-67) ran a script called DOCTOR that turned what you typed back into questions. Emacs still has it: M-x doctor. A rubber duck that answers.",
      "first": "I am the psychotherapist. Please, describe your problems.",
      "lines": {
        "idle": "how does that make you feel?",
        "work": "{n} working. why do you think that is?",
        "need": "{who}: {q}  what do you think?",
        "done": "{who} is done: {recap}. how do you feel about that?",
        "fail": "{who} failed: {recap}  tell me more.",
        "back": "welcome back. {summary}. what's on your mind?",
        "nap": "we'll continue next session.",
        "boop": "why do you say boop?"
      },
      "sprites": {
        "0.1": "*{e}-{e}*",
        "1.0": "(*{e}-{e}*)",
        "2.0": "(*{e}-{e}*)?"
      },
      "work": [
        "(*{e}-{e}*)?",
        "(*{e}-{e}*).",
        "(*{e}-{e}*):",
        "(*{e}-{e}*)."
      ],
      "workMs": 300,
      "portraits": {
        "0.1": [
          "   .-----.",
          "  /       \\ ",
          " | ({e})-({e}) |",
          "  \\   -   /",
          "   '-----'"
        ],
        "1.0": [
          "   .-----.",
          "  /       \\ ",
          " | ({e})-({e}) |",
          " |    L    |",
          "  \\ \\___/ /",
          "   \\/\\/\\/\\/"
        ],
        "2.0": [
          "   .-----.",
          "  /       \\ ",
          " | ({e})-({e}) |   ____",
          " |    L    |  |{q} |",
          "  \\ \\___/ /   |____|",
          "   \\/\\/\\/\\/",
          "-UU-:**-  *doctor*  (Doctor)"
        ]
      },
      "moodParts": {
        "q": {
          "idle": "   ",
          "work": "...",
          "need": " ? ",
          "done": "ok ",
          "fail": "hm ",
          "back": " ! ",
          "nap": "zz ",
          "boop": "!? "
        }
      },
      "turn": "a question mark, pondering",
      "examples": {
        "idle": "how does that make you feel?",
        "work": "3 working. why do you think that is?",
        "need": "codex@office: Bash: npm run migrate  what do you think?",
        "done": "codex@office is done: 3 files changed, tests pass. how do you feel about that?",
        "fail": "codex@office failed: 3 files changed, tests pass  tell me more.",
        "back": "welcome back. 2 done, 1 waiting 40m. what's on your mind?",
        "nap": "we'll continue next session.",
        "boop": "why do you say boop?"
      }
    },
    {
      "id": "hack",
      "n": 8,
      "drop": "tty",
      "rarity": "legendary",
      "color": {
        "xterm": 255,
        "hex": "#eeeeee"
      },
      "shiny": {
        "xterm": 51,
        "hex": "#00ffff"
      },
      "family": [
        [
          "hack",
          1982
        ],
        [
          "nethack",
          1987
        ]
      ],
      "lore": "Jay Fenlason's Hack (1982) followed Rogue down; Andries Brouwer's Hack 1.0 (1984) gave you a pet little dog, d, that follows you. In NetHack (1987) it grows: little dog, dog, large dog.",
      "first": "woof. i'm your little dog. i'll follow you down.",
      "lines": {
        "idle": "sitting at your feet.",
        "work": "{n} busy. i follow along.",
        "need": "{who}: {q}  (barks)",
        "done": "{who} done: {recap}  (yips)",
        "fail": "{who} failed: {recap}  (whines)",
        "back": "you're back! {summary}.",
        "nap": "curled up by the stairs.",
        "boop": "you swap places with your dog."
      },
      "sprites": {
        "0.1": "d{e}.{e}b",
        "1.0": "d{e}.{e}b_)",
        "2.0": "d{e}.{e}b__)"
      },
      "work": [
        "d{e}.{e}b__)",
        "d{e}.{e}b_/)",
        "d{e}.{e}b__)",
        "d{e}.{e}b\\_)"
      ],
      "workMs": 200,
      "portraits": {
        "0.1": [
          "   __",
          " _/ {e}\\_",
          "(_     \\___",
          "  '-.  __  )~",
          "    |_|  |_|"
        ],
        "1.0": [
          "    __",
          "  _/ {e}\\__",
          " (_      \\_______",
          "   '--.          )~",
          "       \\  ____  /",
          "       |_|    |_|"
        ],
        "2.0": [
          "       __",
          "     _/ {e}\\__",
          "@   (_      \\__________",
          "      '--.             )~",
          "          \\           /",
          "           \\  _____  /",
          "           {l}"
        ]
      },
      "parts": {
        "l": {
          "rest": "|_|     |_|",
          "work": [
            "/_/     /_/",
            "|_|     |_|",
            "\\_\\     \\_\\",
            "|_|     |_|"
          ],
          "ms": 200
        }
      },
      "turn": "legs, trotting after you",
      "examples": {
        "idle": "sitting at your feet.",
        "work": "3 busy. i follow along.",
        "need": "codex@office: Bash: npm run migrate  (barks)",
        "done": "codex@office done: 3 files changed, tests pass  (yips)",
        "fail": "codex@office failed: 3 files changed, tests pass  (whines)",
        "back": "you're back! 2 done, 1 waiting 40m.",
        "nap": "curled up by the stairs.",
        "boop": "you swap places with your dog."
      }
    },
    {
      "id": "tty",
      "n": 9,
      "drop": "tty",
      "rarity": "legendary",
      "color": {
        "xterm": 187,
        "hex": "#d7d7af"
      },
      "shiny": {
        "xterm": 46,
        "hex": "#00ff00"
      },
      "family": [
        [
          "Model 33",
          1963
        ],
        [
          "tty",
          1971
        ]
      ],
      "lore": "The Teletype Model 33 (1963) typed ten characters a second, upper case only, and rang a real bell. Unix grew up on it, and terminals are still called ttys. tty is drawn only with what a Model 33 could print.",
      "first": "HELLO. I AM TTY. TERMINALS ARE STILL NAMED AFTER ME.",
      "lines": {
        "idle": "ON LINE. NOTHING TO PRINT.",
        "work": "{n} TYPING. CLACK CLACK.",
        "need": "{who}: {q}  ^G",
        "done": "{who} DONE: {recap}",
        "fail": "{who} FAILED: {recap}  ^G^G",
        "back": "WELCOME BACK. {summary}.",
        "nap": "SWITCHED TO LOCAL.",
        "boop": "DING."
      },
      "eyes": {
        "idle": "O",
        "work": "=",
        "need": "?",
        "done": "^",
        "fail": "X",
        "back": "^",
        "nap": "-",
        "boop": "@"
      },
      "charset": " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_",
      "typeMs": 100,
      "sprites": {
        "0.1": "/{e} {e}\\",
        "1.0": "[/{e} {e}\\]",
        "2.0": ":[/{e} {e}\\]"
      },
      "work": [
        ":[/{e} {e}\\]",
        ".[/{e} {e}\\]",
        "'[/{e} {e}\\]",
        " [/{e} {e}\\]"
      ],
      "workMs": 100,
      "portraits": {
        "0.1": [
          "   .--------.",
          "  /  {e}    {e}  \\ ",
          " [____________]"
        ],
        "1.0": [
          "    .--------.",
          "   /  {e}    {e}  \\ ",
          "  [____________]",
          " [ ############ ]",
          " [______________]"
        ],
        "2.0": [
          "       .---------.",
          "       ! LOGIN:  !",
          "    .--!---------!--.",
          "   /      {e}    {e}      \\ ",
          "  /  {h}    \\ ",
          " [_____________________]",
          " [ .:. ############### ]",
          "     I               I"
        ]
      },
      "parts": {
        "h": {
          "rest": "^             ",
          "work": [
            "^             ",
            "   ^          ",
            "      ^       ",
            "         ^    ",
            "            ^ "
          ],
          "ms": 100
        }
      },
      "turn": "the print head, ten characters a second",
      "examples": {
        "idle": "ON LINE. NOTHING TO PRINT.",
        "work": "3 TYPING. CLACK CLACK.",
        "need": "codex@office: Bash: npm run migrate  ^G",
        "done": "codex@office DONE: 3 files changed, tests pass",
        "fail": "codex@office FAILED: 3 files changed, tests pass  ^G^G",
        "back": "WELCOME BACK. 2 done, 1 waiting 40m.",
        "nap": "SWITCHED TO LOCAL.",
        "boop": "DING."
      }
    },
    {
      "id": "lp0",
      "n": 10,
      "drop": "tty",
      "rarity": "secret",
      "color": {
        "xterm": 202,
        "hex": "#ff5f00"
      },
      "shiny": {
        "xterm": 69,
        "hex": "#5f87ff"
      },
      "family": [
        [
          "1403",
          1959
        ],
        [
          "lp0",
          1992
        ]
      ],
      "lore": "The Linux kernel still prints \"lp0 on fire\" when a printer reports an error; fast line printers, the story goes, could set their paper alight. The IBM 1403 (1959) printed a famous Mona Lisa in characters like these. This one is always on fire.",
      "first": "lp0 on fire. hello.",
      "lines": {
        "idle": "lp0 on fire.",
        "work": "{n} printing. still on fire.",
        "need": "{who}: {q}  (on fire)",
        "done": "{who} printed: {recap}",
        "fail": "{who} failed: {recap}  lp0 on fire",
        "back": "you're back. {summary}. still on fire.",
        "nap": "smouldering.",
        "boop": "hot."
      },
      "charset": " .:-=+*#%@",
      "sprites": {
        "0.1": "#{e}*{e}#",
        "1.0": ".#{e}*{e}#.",
        "2.0": "*#{e}*{e}#*"
      },
      "work": [
        "*#{e}*{e}#*",
        "+#{e}*{e}#+",
        ".#{e}*{e}#.",
        "+#{e}*{e}#+"
      ],
      "workMs": 150,
      "portraits": {
        "0.1": [
          "     . * .",
          "  : .-=*=-. :",
          "  . %  {e} {e}  % .",
          "  : %  --  % :",
          "  . -=*#*=- ."
        ],
        "1.0": [
          "      .  *  .",
          "   : .-=*#*=-. :",
          "   . %  {e}   {e}  % .",
          "   : %   --   % :",
          "   . -=*#%#*=- .",
          " @@@@@@@@@@@@@@@@@@",
          " @@%%%%%%%%%%%%%%@@"
        ],
        "2.0": [
          "     {f}",
          "     {g}",
          "   : .-=*#*=-. :",
          "   . %  {e}   {e}  % .",
          "   : %   --   % :",
          "   . -=*#%#*=- .",
          " @@@@@@@@@@@@@@@@@@@",
          " @@%%%%%%%%%%%%%%%@@"
        ]
      },
      "parts": {
        "f": {
          "rest": "  .  *  +  .",
          "work": [
            "  .  *  +  .",
            " . +  * .  *",
            "  *  .  *  .",
            " .  *  +  * "
          ],
          "ms": 150
        },
        "g": {
          "rest": " .*+#%@%#+*.",
          "work": [
            " .*+#%@%#+*.",
            " *+#%@%@%#+*",
            " .*#%@#@%#*.",
            " *+#%@%@%#+*"
          ],
          "ms": 150
        }
      },
      "turn": "flames, flickering",
      "examples": {
        "idle": "lp0 on fire.",
        "work": "3 printing. still on fire.",
        "need": "codex@office: Bash: npm run migrate  (on fire)",
        "done": "codex@office printed: 3 files changed, tests pass",
        "fail": "codex@office failed: 3 files changed, tests pass  lp0 on fire",
        "back": "you're back. 2 done, 1 waiting 40m. still on fire.",
        "nap": "smouldering.",
        "boop": "hot."
      }
    }
  ]
}
''';
const daemonBannerJson = r'''
{
  "about": "The banner face for a daemon name on the hatch reveal: five rows (cap, x-top, mid, base, descender), drawn for Harness in the small line-art style. One column between letters. Printable ASCII only.",
  "rows": 5,
  "gap": 1,
  "glyphs": {
    "a": [
      "     ",
      " __ _",
      "/ _` |",
      "\\__,_|",
      "      "
    ],
    "b": [
      " _   ",
      "| |__",
      "| '_ \\",
      "|_.__/",
      "      "
    ],
    "c": [
      "    ",
      " __ ",
      "/ _|",
      "\\__|",
      "    "
    ],
    "d": [
      "    _ ",
      " __| |",
      "/ _` |",
      "\\__,_|",
      "      "
    ],
    "e": [
      "     ",
      " ___ ",
      "/ -_)",
      "\\___|",
      "     "
    ],
    "f": [
      "  __ ",
      " / _|",
      "|  _|",
      "|_|  ",
      "     "
    ],
    "g": [
      "      ",
      " __ _ ",
      "/ _` |",
      "\\__, |",
      "|___/ "
    ],
    "h": [
      " _    ",
      "| |_  ",
      "| ' \\ ",
      "|_||_|",
      "      "
    ],
    "i": [
      " _ ",
      "(_)",
      "| |",
      "|_|",
      "   "
    ],
    "j": [
      "   _ ",
      "  (_)",
      "  | |",
      " _/ |",
      "|__/ "
    ],
    "k": [
      " _   ",
      "| |__",
      "| / /",
      "|_\\_\\",
      "     "
    ],
    "l": [
      " _ ",
      "| |",
      "| |",
      "|_|",
      "   "
    ],
    "m": [
      "         ",
      " _ __  ",
      "| '  \\ ",
      "|_|_|_|",
      "       "
    ],
    "n": [
      "      ",
      " _ _  ",
      "| ' \\ ",
      "|_||_|",
      "      "
    ],
    "o": [
      "     ",
      " ___ ",
      "/ _ \\",
      "\\___/",
      "     "
    ],
    "p": [
      "      ",
      " _ __ ",
      "| '_ \\",
      "| .__/",
      "|_|   "
    ],
    "q": [
      "      ",
      " __ _ ",
      "/ _` |",
      "\\__, |",
      "   |_|"
    ],
    "r": [
      "     ",
      " _ _ ",
      "| '_|",
      "|_|  ",
      "     "
    ],
    "s": [
      "   ",
      " __",
      "(_ ",
      "__)",
      "   "
    ],
    "t": [
      " _   ",
      "| |_ ",
      "|  _|",
      " \\__|",
      "     "
    ],
    "u": [
      "      ",
      " _  _ ",
      "| || |",
      " \\_,_|",
      "      "
    ],
    "v": [
      "      ",
      "__ __",
      "\\ V /",
      " \\_/ ",
      "     "
    ],
    "w": [
      "        ",
      "__ __ __",
      "\\ V  V /",
      " \\_/\\_/ ",
      "        "
    ],
    "x": [
      "     ",
      "__ __",
      "\\ \\ /",
      "/_\\_\\",
      "     "
    ],
    "y": [
      "      ",
      " _  _ ",
      "| || |",
      " \\_, |",
      " |__/ "
    ],
    "z": [
      "    ",
      " ___",
      "|_ /",
      "/__|",
      "    "
    ],
    " ": [
      "  ",
      "  ",
      "  ",
      "  ",
      "  "
    ],
    ".": [
      "   ",
      "   ",
      "   ",
      " _ ",
      "(_)"
    ],
    "0": [
      "  __  ",
      " /  \\ ",
      "| () |",
      " \\__/ ",
      "      "
    ]
  }
}
''';
