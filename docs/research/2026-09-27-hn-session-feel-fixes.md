# hn session and terminal-feel fixes before round 19

Baseline: `af2971ee`. References: tmux 3.5a and the isolated mock daemon.

## Changes

- The last attached client leaves a headless hn process while sessions remain, so tmux-sessionizer can detect the running server.
- A new home window has a backing shell and reports one pane to scripts. Its home page, active window and shell ownership survive detach, including with desk synchronization enabled. Pending desk metadata is retained while a new client or headless server waits for the desk response.
- Buffered input and waiting command chains belong to their shell request. Switching between two pending home windows sends input to the selected window. Selecting a harness replaces the home window's unused shell.
- Long home-page titles keep their distinguishing ending with middle clipping.
- Injected `send-keys -K` text preserves case and repeat counts. Opening a prompt through injected keys returns control to the calling CLI. Explicit shifted characters follow tmux's status-prompt behavior.
- `prefix-timeout` reads its server option and expires on the following key. A prefix-table miss checks the root binding table.
- Messages and prompts replace only `message-line`; other status-format rows remain visible. Menus clear text attributes as tmux does. Very short terminals retain a pane row when configured status rows cannot fit.
- The default status line includes the short host name. Animation refreshes every 100 ms, independently of maintenance timers.
- WebSocket ping/pong deadlines detect an open but unresponsive daemon. Its last screen remains visible with reconnect feedback, and existing input queuing applies.
- End-to-end invocations now supply the socket name, daemon port and disposable home explicitly, reject ports outside the isolated test range, and clean up detached servers.

Prompt history persistence and its two-client concurrency check are documented in the companion tmux fixes report. Picker and rendering comparisons have their own reports.

## Rechecks

Every hn invocation used a frozen binary, throwaway HOME, matching `-L`, `--port`, `PORT` and `HN_SOCKET_NAME`, with `TMUX`, `TMUX_PANE` and `HN_SOCKET` unset. Root checks used guarded ports 19410–19419 and `hnr19fix` socket prefixes. Reference and outer tmux servers always used an explicit private `-L`.

- `send-keys -K C-b , C-u viaK Enter` produces `viaK`.
- With `status-keys emacs`, `send-keys -K -N 3 Ab` followed by `S-a Enter` produces `AbAbAb`, matching tmux.
- With two status rows, `message-line 1` preserves row zero and replaces row one for both messages and prompts. Captured text matches tmux.
- Bind a root `M-h` message, then type `C-b M-h`: both tools display it. Set `prefix-timeout 500`, type `C-b`, wait 800 ms, then type `c`: neither creates a window.
- Create a home window, detach, wait three seconds, then attach: one hn server remains, both windows and their panes remain, the home page remains selected, and typing reaches its backing shell. Repeated with desk synchronization enabled.
- Delay shell-creation replies by 500 ms, create two home windows rapidly, and type: only the second shell gets the text. Repeat after switching back to the first window before typing: only the first gets it.
- Stop the isolated mock with SIGSTOP: the daemon-down format becomes 1 after the heartbeat deadline. Continue the mock before cleanup. The reconnect banner after a desk detach/reattach is under a separate follow-up check; one capture retained the screen without the banner.
- A command entered through the physical status prompt appears in shared history, is saved in tmux's typed history-file format and is restored by a new server.

The combined release unit suite passes all 106 tests. The full isolated end-to-end suite, release build and whitespace checks pass. No real daemon, default socket or installed hn binary was used.
