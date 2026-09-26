// Generated from daemons/roster.json by daemons/tools/generate.mjs. Do not edit.
export const PAIR_ROSTER = {
  "lineSlots": [
    "who",
    "q",
    "recap",
    "n",
    "summary"
  ],
  "awayMinutes": 30,
  "daemons": [
    {
      "id": "tim",
      "lore": "Named the way vim was: vi improved. tmux followed screen; tim is tmux improved, and so is the app it lives in.",
      "first": "oh hi. i'm tim. tmux, improved. what are we building?",
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
      "lines": {
        "idle": "all quiet. no alerts.",
        "work": "{n} panes busy. watching.",
        "need": "bell in {who}: {q}",
        "done": "silence in {who}: {recap}",
        "fail": "pane is dead: {who}. {recap}",
        "back": "reattached. {summary}.",
        "nap": "detached. reattach any time.",
        "boop": "hey. that's my status line."
      }
    },
    {
      "id": "fish",
      "lore": "The Friendly Interactive SHell: \"Finally, a command line shell for the 90s.\" Rewritten in Rust for 4.0. It finishes your sentences in grey.",
      "first": "finally, a buddy for the 90s. hi!",
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
      "lines": {
        "idle": "all quiet in the pond.",
        "work": "{n} swimming along nicely.",
        "need": "{who} has a question: {q}",
        "done": "{who} finished! {recap}",
        "fail": "{who} sank: {recap}",
        "back": "welcome back! {summary}.",
        "nap": "drifting for a bit. blub.",
        "boop": "fish: Unknown command: boop"
      }
    },
    {
      "id": "ping",
      "lore": "Named after the sound of sonar. It shares its name with a 1933 picture book about a duck. It measures every round trip.",
      "first": "PING you (127.0.0.1): hi. you there?",
      "family": [
        [
          "ping",
          1983
        ]
      ],
      "lines": {
        "idle": "0 packets waiting.",
        "work": "{n} in flight.",
        "need": "PING you: {who} is waiting: {q}",
        "done": "64 bytes from {who}: {recap}",
        "fail": "Request timeout for {who}: {recap}",
        "back": "you're back. {summary}.",
        "nap": "floating. no packets for a bit.",
        "boop": "pong."
      }
    },
    {
      "id": "bat",
      "lore": "cat has printed files since Unix v1. bat calls itself \"a cat(1) clone with wings.\" It hatches as a kitten; the wings ship in 2.0.",
      "first": "a cat(1) clone, with wings. i'll take it from here.",
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
      "lines": {
        "idle": "watching from above.",
        "work": "{n} busy. watching from above.",
        "need": "{who} is waiting: {q}",
        "done": "{who} finished. highlighted: {recap}",
        "fail": "{who} fell over: {recap}",
        "back": "you're back. {summary}. i kept the lights low.",
        "nap": "hanging upside down for a bit.",
        "boop": "...rude."
      }
    },
    {
      "id": "vim",
      "lore": "ed begat vi, and vi begat vim, Vi IMproved. The ~ marks lines past the end of the buffer. Famous for being hard to leave.",
      "first": "hi. i'm vim. no, you can't exit me. :help pairing",
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
      "lines": {
        "idle": "--No lines in buffer--",
        "work": "-- INSERT -- {n} agents typing.",
        "need": "E325: ATTENTION  {who}: {q}",
        "done": "\"{who}\" written. {recap}",
        "fail": "(1 of 1): {who}: {recap}",
        "back": ":earlier  {summary}.",
        "nap": ":sleep 900",
        "boop": "-- VISUAL -- you selected me."
      }
    },
    {
      "id": "zsh",
      "lore": "A hermit crab that keeps moving into better shells: the Bourne shell, the Korn shell, then zsh, named after a teaching assistant's login.",
      "first": "the default interactive shell is now zsh. hi.",
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
      "lines": {
        "idle": "no jobs.",
        "work": "{n} jobs running in the background.",
        "need": "zsh: suspended (tty input)  {who}: {q}",
        "done": "[1]  + done       {who}  {recap}",
        "fail": "[1]  + exit 1     {who}  {recap}",
        "back": "you were away. {summary}. i autocorrected nothing.",
        "nap": "moving into a quieter shell for a bit.",
        "boop": "zsh: command not found: boop"
      }
    },
    {
      "id": "biff",
      "lore": "biff told Berkeley Unix users when mail arrived (4.0BSD). It was named after a dog who barked at the mail carrier, and `biff y` switched it on. Now it barks when an agent needs you.",
      "first": "woof. i'm biff. i bark when you have mail. and agents.",
      "family": [
        [
          "biff",
          1980
        ]
      ],
      "lines": {
        "idle": "watching the door.",
        "work": "{n} inside. i hear them working.",
        "need": "new mail for you: {who} asks {q}",
        "done": "{who}'s done! good agent! {recap}",
        "fail": "grr. {who}: {recap}",
        "back": "you're back! {summary}.",
        "nap": "lying down by the door.",
        "boop": "woof."
      }
    },
    {
      "id": "fzf",
      "lore": "find has walked directory trees since 1974. fzf finds things fuzzily, shows its match count, and keeps the best match next to the prompt.",
      "first": "> hello   1/1   it's me, fzf. i find things.",
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
      "lines": {
        "idle": "0/0. nothing to find.",
        "work": "{n} busy. filtering out the noise.",
        "need": "> needs you  {who}: {q}",
        "done": "match: {who}  {recap}",
        "fail": "0 matches for 'passing': {who}: {recap}",
        "back": "{summary}. best match at the bottom, as always.",
        "nap": "no query. resting.",
        "boop": "> boop  0/0"
      }
    },
    {
      "id": "tldr",
      "lore": "man pages date from the first Unix Programmer's Manual. tldr pages are the short version: a few examples, no essay. It gets smaller with every release.",
      "first": "tldr: hi.",
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
      "lines": {
        "idle": "nothing.",
        "work": "{n} working.",
        "need": "{who}: {q}",
        "done": "{who}: done.",
        "fail": "{who}: failed.",
        "back": "tl;dr {summary}.",
        "nap": "zz.",
        "boop": "no."
      }
    },
    {
      "id": "grue",
      "lore": "Zork, MIT: \"It is pitch black. You are likely to be eaten by a grue.\" Nobody has seen one. It hatches only from eggs found in the dark, and shows up only in a dark theme.",
      "first": "it is pitch black. you are likely to be paired with a grue.",
      "family": [
        [
          "grue",
          1977
        ]
      ],
      "lines": {
        "idle": "...",
        "work": "it is dark. {n} are working. i can hear them.",
        "need": "something in the dark wants your answer: {q}",
        "done": "the lamp is lit. {who} is done.",
        "fail": "{who} was eaten. it wasn't me.",
        "back": "you have moved into a dark place.",
        "nap": "...",
        "boop": "you touched something in the dark."
      }
    }
  ]
} as const
