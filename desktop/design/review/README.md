# Local companion reviews

Open `index.html` from disk. The three previews contain their own styles, scripts, and data;
they need no server, artifact host, account, or network connection.

- `terminal-creature-lookbook.html`: six early creatures in twelve moods, gestures, hatching,
  font and size controls. Arrow keys navigate the comparison; Enter selects a pose.
- `egg-status-animation.html`: early shell/nest alternatives, growing/ready/hatched states,
  a requested gesture, and a reset control. No periodic idle animation.
- `developer-onboarding.html`: the September 24 proposal. Local controls expose journey
  moments and readiness states; all operations and replies are examples. Escape returns
  from a project or the guide. Cmd/Ctrl-Enter submits an example task.

These are historical concepts. The current terminal workspace and dialog documents take
precedence for app changes. The separate daemons reviews on the `daemons` branch contain
the later drop-init art and individual-daemon design.

Edit the corresponding HTML in `src/`, or its shared `review.css` and `review.js`, then run:

```sh
node desktop/design/review/src/build.mjs
node desktop/design/review/src/build.mjs --check
```

Commit the sources and generated HTML together. Keep future reviews as local files here.
Do not replace them with hosted artifact links. Screenshots under `onboarding-2026-09-24/`
are the original evidence; their dates and the review notes' test counts are historical.

Run the local DOM regression checks with:

```sh
npm ci --prefix desktop/design/review/src --ignore-scripts
npm test --prefix desktop/design/review/src
```

They check page loading, links, labels, keyboard handlers, creature selection, animation
cancellation, hatching, the absence of idle egg timers, preserved project drafts, launch
cancellation, form validation, and the return journey. Font metrics and time are simulated.
They do not replace browser visual inspection, which was blocked by the local-file URL policy
during this pass. No real app, sign-in, installation, or harness was used.
