# hn browser viewer handoff

`hn view` opens the focused harness's existing viewer in the user's default browser.
`hn view -t <harness>` also works from a shell without starting or attaching a terminal.
The command palette exposes `open-viewer`; tmux's keys are unchanged. The harness preview
and a focused harness's ready notification tell the user when a viewer is available.

On a local desktop, a local harness opens its managed viewer URL directly. SSH, another
linked machine, `-w`, and copying with `-c` use the browser app's authenticated destination:
`/?viewer=1&machine=<encoded-id>&agent=<encoded-id>`. The existing website root rewrite
serves this entry point. No new server route, public listener, or share is created. URLs
contain identities, never account tokens or link credentials. The browser still signs in
as the owner and establishes its own machine link.

The invoking CLI process chooses whether to launch a browser. A request forwarded to an
existing hn client only obtains the URL; the client's older SSH/display environment cannot
make the invoking shell launch a browser on the wrong host. `-p` prints only, `-c` copies
through the terminal clipboard when supported, and an unavailable/failed browser opener
falls back to printing the link. URL schemes, credentials and control characters are checked
before starting an opener, which receives a single argv value without a shell.

The browser companion reuses the existing interactive viewer. It never joins the shared
desk, restores or saves its terminal layout, or attaches a terminal stream. Its destination
survives OAuth's callback. It shows linking, offline, missing harness, waiting viewer and
retry states. Closing it only releases its viewer surface; the agent remains running.
A Chrome interaction test also exposed the viewer image's missing explicit dimensions:
the image now fills the same viewport used to normalize pointer coordinates, including
while decoding and when the remote renderer caps its resolution.

## Boundaries

The existing remote interactive-viewer transport renders on the harness machine using
Chrome or Chromium and relays encrypted images and input. This change reuses that transport;
it does not introduce browser-side WebGL rendering or install a renderer. Local direct
viewers use the user's browser without that additional renderer. Existing browser viewer
limitations, including server-side rendering requirements, remain.

Release the browser app before native hn so new links are understood before hn emits them.
This work does not publish a release, reinstall the user's hn, change the production daemon,
or change creature behavior.

## Validation

All interactive CLI tests use a disposable HOME, a frozen binary, explicit socket prefix,
matching `PORT`/`--port`, unset tmux/socket variables, and guarded ports in 19000–19999.
The browser opener is a recording stub. Chrome tests use an isolated headless test profile
and synthetic machine/viewer data. Nothing controls a real harness.

- Rust release unit tests, including URL escaping, invalid schemes, no-viewer and waiting states.
- `tui/tests/viewer.py`: public CLI commands, direct local viewer, exact opener argv, failed
  opener fallback, SSH, peer viewers, current pane through IPC, caller environment, and errors.
- Existing `tui/tests/e2e.sh`: tmux/fzf and terminal lifecycle regression checks.
- Flutter viewer location, OAuth return, viewer page, desk isolation, interactive viewer and
  auth lifecycle regressions.
- Chrome browser test: sign-in gate, viewer-only route, rendered input area, mouse and keyboard
  input, recovery, and closing without removing the harness.
- Flutter analyzer and production web compilation.

The new CLI integration test is included in both Linux architecture jobs in the on-demand
CI workflow. Tests and source are the verification record; no production browser account or
remote machine was used as a test fixture.
