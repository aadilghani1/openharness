# Session branches and pull requests

A session can use several branches and create several pull requests. The app
shows those branches and their PRs. Worktree directories are internal references
for locating code, not user-facing identities.

## Display and navigation

The focused bar shows the branch checked out for the session, plus its matching
PR link when there is one. If more than one branch is checked out in associated
checkouts, it shows `2 branches` (or the corresponding count). A historical branch
does not increase this count. A dependent viewer uses its owner's context.

Click the branch, or use **Branches and pull requests** in the desktop command picker. Details list checked-out and previously recorded branches, followed
by their PR links, titles, head/base branches and GitHub states. Open and draft
PRs precede completed work. Temporary folder names and subdirectory lists are
not shown. Matching repository and branch names are one visible branch even
when several local copies exist; different repositories remain distinct.

| Fact | Source |
| --- | --- |
| Session's assigned checkout | Harness's saved launch/resume association |
| Checked-out branch | Git, read directly on the owning machine |
| Branch history | Saved Git observations for this conversation |
| Additional checkout association | Previously verified observations or successful tool activity |
| PR identity and state | GitHub, matched by head repository and branch, or a recorded PR URL |

The Git reader works for every engine, including Claude Code, Codex and Grok.
No transcript or successful tool receipt is required for the assigned branch,
branch switches, branch history, or PR lookup. Unknown, pending and failed tool
activity cannot erase Git facts. Looking up a saved branch can discover its PR
after that local branch or checkout has been deleted.

This is an association record, not an authorship claim. Harness does not attach
every branch in the shared repository to every agent, infer ownership from a
branch prefix or GitHub author, or pretend that the last command's directory is
the session's one current branch. Engine activity can add associations and PR
URLs. Formats the reader cannot understand add nothing and remove nothing.

## Freshness and history

The assigned checkout and previously associated checkouts are read through the
existing 15-second Git cache. An explicit details refresh clears their cached
Git snapshots. One projection inspects at most eight additional locations,
collapsing known subdirectories without additional Git subprocesses. Incomplete
history is labeled. Short-lived branches switched away between observations,
and activity deleted before it was observed, cannot be reconstructed reliably.

Opening details checks a bounded page of four saved branch identities and four
PR URLs. **Show more** continues discovery and history refresh. GitHub results
are cached for 60 seconds with their actual check times. A failed lookup retains
saved PR state. Offline clients show saved data with an offline label. Deleted
checkouts do not delete branch/PR history. A merged PR is not proof of a release
or permission to delete a checkout.

Histories live in private atomic files under `ADAPTER_DATA_DIR/session-git-history`,
outside the Git checkout, with at most 128 branches and 128 PRs per conversation.
They contain validated locations, branch identities and PR metadata, never raw
commands, credentials or transcript output. Inherited fork receipts are excluded.
The optional Claude/Codex reader accepts bounded literal operations without
executing transcript text. Existing v3 checkpoints replay available transcripts
once to recover missed batched receipts; later v4 reads stay incremental.

Registry `cwd` and the legacy `project` field keep their launch/resume meaning.
The additive `gitContext.checkouts` contains verified Git snapshots. List and
push frames use the same projection and versions. Older clients remain readable;
the desktop groups the snapshots into branch identities. PR badge responses
are bound to the displayed repository, branch and checkout, and stale replies
are discarded. Readers run on the owning machine; private data uses the existing
encrypted machine RPC. No new dependencies or filesystem watchers are required.

This UI only inspects and navigates. It never checks out, pushes, merges,
deletes, or sends input to a terminal.

## Branch workflow

Use one topic branch per independently reviewable change and one isolated
checkout per concurrently editing agent. Sequential tasks can reuse a checkout
and produce several PRs. Start unrelated changes from updated `origin/main`;
make deliberate stacked dependencies explicit. Put review fixes on the original
PR branch. After merging, start a new branch for the next task, once changes are
saved and processes using the checkout have finished.
