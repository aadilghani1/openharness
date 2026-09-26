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
    "firstEgg": {
      "need": 5,
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
    "eggs": {
      "first": {
        "look": "\\_O_/",
        "weights": {
          "common": 60,
          "rare": 27,
          "legendary": 12,
          "secret": 1
        }
      },
      "turn": {
        "look": "\\_O_/",
        "weights": {
          "common": 60,
          "rare": 27,
          "legendary": 12,
          "secret": 1
        }
      },
      "week": {
        "look": "\\_0_/",
        "weights": {
          "common": 45,
          "rare": 35,
          "legendary": 18,
          "secret": 2
        }
      },
      "marathon": {
        "look": "\\_@_/",
        "weights": {
          "common": 25,
          "rare": 40,
          "legendary": 32,
          "secret": 3
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
          "secret": 1
        }
      },
      "easter": {
        "look": "\\_?_/",
        "weights": {
          "common": 0,
          "rare": 0,
          "legendary": 50,
          "secret": 50
        }
      }
    },
    "earn": {
      "turn": {
        "every": 40,
        "dailyCap": 20
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
        "fromHour": 0,
        "toHour": 4
      }
    },
    "historyDates": {
      "04-01": "teapot",
      "09-09": "moth",
      "10-31": "zombie"
    },
    "easterWords": [
      "xyzzy"
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
      "name": "unix"
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
        "need": "bell in {who}: {q}",
        "done": "silence in {who}: {recap}",
        "fail": "pane is dead: {who}. {recap}",
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
        "need": "bell in codex@office: Bash: npm run migrate",
        "done": "silence in codex@office: 3 files changed, tests pass",
        "fail": "pane is dead: codex@office. 3 files changed, tests pass",
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
        "need": "{who} has a question: {q}",
        "done": "{who} finished! {recap}",
        "fail": "{who} sank: {recap}",
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
        "need": "codex@office has a question: Bash: npm run migrate",
        "done": "codex@office finished! 3 files changed, tests pass",
        "fail": "codex@office sank: 3 files changed, tests pass",
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
        "need": "PING you: {who} is waiting: {q}",
        "done": "64 bytes from {who}: {recap}",
        "fail": "Request timeout for {who}: {recap}",
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
        "need": "PING you: codex@office is waiting: Bash: npm run migrate",
        "done": "64 bytes from codex@office: 3 files changed, tests pass",
        "fail": "Request timeout for codex@office: 3 files changed, tests pass",
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
        "need": "{who} is waiting: {q}",
        "done": "{who} finished. highlighted: {recap}",
        "fail": "{who} fell over: {recap}",
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
        "need": "codex@office is waiting: Bash: npm run migrate",
        "done": "codex@office finished. highlighted: 3 files changed, tests pass",
        "fail": "codex@office fell over: 3 files changed, tests pass",
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
        "need": "E325: ATTENTION  {who}: {q}",
        "done": "\"{who}\" written. {recap}",
        "fail": "(1 of 1): {who}: {recap}",
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
        "need": "E325: ATTENTION  codex@office: Bash: npm run migrate",
        "done": "\"codex@office\" written. 3 files changed, tests pass",
        "fail": "(1 of 1): codex@office: 3 files changed, tests pass",
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
        "need": "zsh: suspended (tty input)  {who}: {q}",
        "done": "[1]  + done       {who}  {recap}",
        "fail": "[1]  + exit 1     {who}  {recap}",
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
        "need": "zsh: suspended (tty input)  codex@office: Bash: npm run migrate",
        "done": "[1]  + done       codex@office  3 files changed, tests pass",
        "fail": "[1]  + exit 1     codex@office  3 files changed, tests pass",
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
        "need": "new mail for you: {who} asks {q}",
        "done": "{who}'s done! good agent! {recap}",
        "fail": "grr. {who}: {recap}",
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
        "need": "new mail for you: codex@office asks Bash: npm run migrate",
        "done": "codex@office's done! good agent! 3 files changed, tests pass",
        "fail": "grr. codex@office: 3 files changed, tests pass",
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
        "need": "> needs you  {who}: {q}",
        "done": "match: {who}  {recap}",
        "fail": "0 matches for 'passing': {who}: {recap}",
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
        "need": "> needs you  codex@office: Bash: npm run migrate",
        "done": "match: codex@office  3 files changed, tests pass",
        "fail": "0 matches for 'passing': codex@office: 3 files changed, tests pass",
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
        "fail": "{who}: failed.",
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
        "fail": "codex@office: failed.",
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
        "need": "something in the dark wants your answer: {q}",
        "done": "the lamp is lit. {who} is done.",
        "fail": "{who} was eaten. it wasn't me.",
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
        "need": "something in the dark wants your answer: Bash: npm run migrate",
        "done": "the lamp is lit. codex@office is done.",
        "fail": "codex@office was eaten. it wasn't me.",
        "back": "you have moved into a dark place.",
        "nap": "...",
        "boop": "you touched something in the dark."
      }
    }
  ]
}
''';
