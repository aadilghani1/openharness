// Generated from daemons/roster.json by daemons/tools/generate.mjs. Do not edit.
export const DAEMON_ROSTER = {
  "version": 1,
  "rules": {
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
        "turn",
        "split",
        "find",
        "elsewhere",
        "machine",
        "store",
        "resume",
        "days"
      ]
    },
    "eggs": {
      "first": {
        "weights": {
          "common": 60,
          "rare": 27,
          "legendary": 12,
          "secret": 1
        }
      },
      "turn": {
        "weights": {
          "common": 60,
          "rare": 27,
          "legendary": 12,
          "secret": 1
        }
      },
      "week": {
        "weights": {
          "common": 45,
          "rare": 35,
          "legendary": 18,
          "secret": 2
        }
      },
      "marathon": {
        "weights": {
          "common": 25,
          "rare": 40,
          "legendary": 32,
          "secret": 3
        }
      },
      "night": {
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
      "easter": {
        "weights": {
          "common": 0,
          "rare": 0,
          "legendary": 50,
          "secret": 50
        }
      }
    },
    "easterWords": [
      "xyzzy"
    ],
    "versions": [
      "0.1",
      "1.0",
      "2.0"
    ]
  },
  "drops": [
    "unix"
  ],
  "daemons": [
    {
      "id": "tim",
      "n": 1,
      "drop": "unix",
      "rarity": "common"
    },
    {
      "id": "fish",
      "n": 2,
      "drop": "unix",
      "rarity": "common"
    },
    {
      "id": "ping",
      "n": 3,
      "drop": "unix",
      "rarity": "common"
    },
    {
      "id": "bat",
      "n": 4,
      "drop": "unix",
      "rarity": "common"
    },
    {
      "id": "vim",
      "n": 5,
      "drop": "unix",
      "rarity": "rare"
    },
    {
      "id": "zsh",
      "n": 6,
      "drop": "unix",
      "rarity": "rare"
    },
    {
      "id": "biff",
      "n": 7,
      "drop": "unix",
      "rarity": "rare"
    },
    {
      "id": "fzf",
      "n": 8,
      "drop": "unix",
      "rarity": "legendary"
    },
    {
      "id": "tldr",
      "n": 9,
      "drop": "unix",
      "rarity": "legendary"
    },
    {
      "id": "grue",
      "n": 10,
      "drop": "unix",
      "rarity": "secret"
    }
  ]
} as const
