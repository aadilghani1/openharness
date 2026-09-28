# Daemons review pages

Self-contained HTML pages used to review the daemons' art and design with the product owner. Open any
of them straight from disk in a browser (`open daemons/review/eggs.html`); they need no server. Edit
them here and commit: these files are the review pages, not copies of something elsewhere.

| page | what it shows |
|---|---|
| `eggs.html` | How an egg cracks: the nine states (five while you earn it, four when you open it) with each state's status-line one-liner, every egg kind's shell, and a hatch player (pick progress and what is inside). Approved. |
| `traits.html` | Traits for all ten drop-1 species: colour families, markings, shape and rare extras with their odds, six rolled individuals each with flags, `1 in N`, and the status-line one-liner. |
| `lookbook.html` | The lookbook as it was reviewed: `daemons/lookbook.html` plus the review-only sections (drop 1 showcase with the paper look, twelve tims with traits, the first filled eggs). The canonical lookbook is `daemons/lookbook.html`, which `generate.mjs` refreshes from the roster. |
| `overnight/index.html` | The overnight build report (26-27 Sep): PRs, screenshots from tests, decisions and open questions at that time. Superseded in places by drop init; see `docs/research/2026-09-27-daemons-handoff.md`. |

## How they were built

The pages embed their data, so they open anywhere. The scripts that made that data are in `src/`, as
they were written during the review; they are reference, not part of the build:

- `src/eggs/`: the egg prototype (`egg2.mjs`, now `daemons/plates/egg.mjs`), the prototype shader with
  the material channel (`plate.mjs`, now in `daemons/tools/plate.mjs`), `build2.mjs` (bakes the eggs the
  page embeds), `sheet.mjs` (prints the nine states as text), `epv2.mjs` (a preview CLI).
- `src/traits/`: each species' trait prototype (`<id>.mjs`, now `daemons/plates/<id>.mjs`),
  `samples.mjs` (picks and renders six individuals), `page-data.mjs` (gathers the traits page's data),
  `one-liners.json` and `check-one-liners.mjs` (the extras' status-line sprites, now in roster.json).
- `src/lookbook/`: the section templates and injectors for the review-only lookbook sections, and the
  plate preview tools used while drawing drop init.

Paths in those scripts are placeholders: `REPO` is the repository root, `SCRATCH` the directory the
script ran from, `FLUTTER_BIN` a Flutter 3.47.2 `bin`. To reuse one, point those at real paths. New
review pages should be written here directly, from the repo's own models (`daemons/plates`,
`daemons/tools`), so they stay in step with what ships.
