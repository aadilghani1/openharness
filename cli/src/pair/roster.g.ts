// Generated from daemons/roster.json by daemons/tools/generate.mjs. Do not edit.
export const PAIR_ROSTER = {
  "daemons": [
    {
      "id": "tim",
      "lines": {
        "idle": "two agents idle. nothing needs you.",
        "work": "two panes busy. i'm watching both.",
        "need": "codex@office wants to run the migration. i'd say yes. [y/n]",
        "done": "claude finished the refactor. 3 files, tests pass.",
        "fail": "codex exited 1. same flaky test as tuesday.",
        "back": "welcome back. 2 done, 1 waiting 40m. nothing on fire.",
        "nap": "detached. reattach any time.",
        "boop": "hey. that's my status line."
      }
    },
    {
      "id": "fish",
      "lines": {
        "idle": "all quiet in the pond.",
        "work": "agents are swimming along nicely.",
        "need": "claude has a question for you.",
        "done": "codex finished!",
        "fail": "that one sank. same test as last time.",
        "back": "welcome back! 2 done while you were out.",
        "nap": "drifting for a bit. blub.",
        "boop": "blub!"
      }
    },
    {
      "id": "ping",
      "lines": {
        "idle": "0 packets waiting. all good.",
        "work": "3 agents replying. avg 12s per turn.",
        "need": "PING you: codex@office is waiting. you there?",
        "done": "64 bytes from claude: done time=4m12s",
        "fail": "request timeout for codex. exit 1.",
        "back": "you're back. 2 replies, 1 waiting, 0% loss.",
        "nap": "floating. no packets for a bit.",
        "boop": "pong."
      }
    },
    {
      "id": "bat",
      "lines": {
        "idle": "watching. from above.",
        "work": "three agents busy. i have the high ground.",
        "need": "claude is waiting on you. it's been pacing.",
        "done": "codex finished. i highlighted the interesting lines.",
        "fail": "a test fell over. i'd start at line 212.",
        "back": "you're back. i kept the lights low. 2 done.",
        "nap": "hanging upside down for a bit.",
        "boop": "...rude."
      }
    },
    {
      "id": "vim",
      "lines": {
        "idle": "-- NORMAL -- nothing pending.",
        "work": "-- INSERT -- three agents typing.",
        "need": "E37: claude wants to write. add ! to approve.",
        "done": "\"auth.ts\" 3L written. clean.",
        "fail": "E492: codex tried something odd. exit 1.",
        "back": ":earlier 40m  2 done, 1 waiting.",
        "nap": "-- NORMAL -- resting my eyes.",
        "boop": "-- VISUAL -- you selected me."
      }
    },
    {
      "id": "zsh",
      "lines": {
        "idle": "no jobs. clean prompt.",
        "work": "[3] jobs running in the background.",
        "need": "zsh: suspended (tty input)  codex@office",
        "done": "[1]  + done  claude  auth refactor",
        "fail": "[2]  - exit 1  codex  billing.spec.ts",
        "back": "you were away 40m. i autocorrected nothing. promise.",
        "nap": "moving into a quieter shell for a bit.",
        "boop": "zsh: command not found: boop"
      }
    },
    {
      "id": "biff",
      "lines": {
        "idle": "watching the door.",
        "work": "three agents inside. i hear them working.",
        "need": "woof! codex@office needs you!",
        "done": "claude's done! good agent! good!",
        "fail": "grr. a test failed. i'm sitting next to it.",
        "back": "you're back!!! 2 done, 1 waiting. i waited too.",
        "nap": "lying down by the door.",
        "boop": "!!!"
      }
    },
    {
      "id": "fzf",
      "lines": {
        "idle": "0/0. nothing to find.",
        "work": "3/12 agents busy. filtering out the noise.",
        "need": "> needs you   1/1   codex@office",
        "done": "best match for 'done': claude, auth refactor.",
        "fail": "0/1 matches for 'passing tests'. codex failed.",
        "back": "4/7 things changed. want the top one?",
        "nap": "no query. resting.",
        "boop": "> boop   0/0"
      }
    },
    {
      "id": "tldr",
      "lines": {
        "idle": "nothing.",
        "work": "3 working.",
        "need": "codex: needs you.",
        "done": "done. tests pass.",
        "fail": "failed. flaky test.",
        "back": "tl;dr 2 done, 1 waiting.",
        "nap": "zz.",
        "boop": "no."
      }
    },
    {
      "id": "grue",
      "lines": {
        "idle": "...",
        "work": "it is dark. your agents are working. i can hear them.",
        "need": "something in the dark wants your answer.",
        "done": "the lamp is lit. codex is done.",
        "fail": "a test was eaten. it wasn't me.",
        "back": "you came back to the dark. brave.",
        "nap": "...",
        "boop": "you touched something in the dark."
      }
    }
  ]
} as const
