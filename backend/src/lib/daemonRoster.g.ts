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
    "setupEgg": {
      "need": 6
    },
    "eggs": {
      "first": {
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
        "weights": {
          "common": 60,
          "rare": 27,
          "legendary": 12,
          "secret": 0
        }
      },
      "turn": {
        "weights": {
          "common": 60,
          "rare": 27,
          "legendary": 12,
          "secret": 0
        }
      },
      "week": {
        "weights": {
          "common": 45,
          "rare": 35,
          "legendary": 18,
          "secret": 0
        }
      },
      "marathon": {
        "weights": {
          "common": 25,
          "rare": 40,
          "legendary": 32,
          "secret": 0
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
      "history": {
        "weights": {
          "common": 60,
          "rare": 27,
          "legendary": 12,
          "secret": 0
        }
      },
      "easter": {
        "weights": {
          "common": 0,
          "rare": 0,
          "legendary": 90,
          "secret": 10
        }
      }
    },
    "easterHashes": [
      "184858a00fd7971f810848266ebcecee5e8b69972c5ffaed622f5ee078671aed"
    ],
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
    }
  },
  "drops": [
    {
      "id": "unix",
      "announce": "2026-09-12",
      "release": "2026-09-26"
    },
    {
      "id": "tty",
      "announce": "2026-09-27",
      "release": "2026-10-11"
    }
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
    },
    {
      "id": "xeyes",
      "n": 1,
      "drop": "tty",
      "rarity": "common"
    },
    {
      "id": "oneko",
      "n": 2,
      "drop": "tty",
      "rarity": "common"
    },
    {
      "id": "cowsay",
      "n": 3,
      "drop": "tty",
      "rarity": "common"
    },
    {
      "id": "fortune",
      "n": 4,
      "drop": "tty",
      "rarity": "common"
    },
    {
      "id": "rogue",
      "n": 5,
      "drop": "tty",
      "rarity": "rare"
    },
    {
      "id": "sl",
      "n": 6,
      "drop": "tty",
      "rarity": "rare"
    },
    {
      "id": "doctor",
      "n": 7,
      "drop": "tty",
      "rarity": "rare"
    },
    {
      "id": "hack",
      "n": 8,
      "drop": "tty",
      "rarity": "legendary"
    },
    {
      "id": "tty",
      "n": 9,
      "drop": "tty",
      "rarity": "legendary"
    },
    {
      "id": "lp0",
      "n": 10,
      "drop": "tty",
      "rarity": "secret"
    }
  ]
} as const
