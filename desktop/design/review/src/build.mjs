// Inline everything needed by the three local review pages. Run from any directory.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
const source = dirname(fileURLToPath(import.meta.url)),
  out = resolve(source, "..");
const read = (name) => readFileSync(resolve(source, name), "utf8");
const check = process.argv.includes("--check");
const pages = [
  {
    file: "index.html",
    label: "Overview",
    title: "The early companion reviews.",
    description:
      "Local, interactive records of the first creature designs, the status-line egg, and a developer onboarding proposal.",
  },
  {
    file: "terminal-creature-lookbook.html",
    label: "Creatures",
    title: "Six creatures. Twelve moods.",
    description:
      "Inspect every pose, play a gesture, and hatch a companion. Compare the actual-size sprite in different terminal fonts.",
  },
  {
    file: "egg-status-animation.html",
    label: "Status-line egg",
    title: "Before the first hello.",
    description:
      "The early shell and nest treatments, in their status-line context. Try a growing egg, a ready egg, and a hatched companion.",
  },
  {
    file: "developer-onboarding.html",
    label: "Onboarding",
    title: "From a project to a first result.",
    description:
      "Walk through the September 24 onboarding proposal with example content. Try different readiness states, cancel, return, and start a second task.",
  },
];
for (const page of pages) {
  const index = page.file === "index.html";
  const nav =
    '<nav class="review-nav" aria-label="Review pages">' +
    pages
      .map(
        (p) =>
          '<a href="' +
          p.file +
          '"' +
          (p === page ? ' aria-current="page"' : "") +
          ">" +
          p.label +
          "</a>",
      )
      .join("") +
    "</nav>";
  const notice =
    '<aside class="review-notice"><strong>Historical concept · September 2026.</strong> These previews preserve early design directions. The current <a href="../terminal-workspace.md">workspace design</a> and <a href="../terminal-dialogs.md">dialog rules</a> take precedence for the app. All launches, sign-ins, installations, replies, and hatches here are simulated.</aside>';
  const controls = index
    ? ""
    : '<section class="review-tools" aria-labelledby="review-controls-title"><h2 id="review-controls-title">Preview controls</h2><div class="review-fields" id="review-fields"><label class="review-field">Palette<select id="review-theme"><option value="system">System</option><option value="dark">Dark</option><option value="light">Light</option></select></label><label class="review-field review-toggle"><input id="review-motion" type="checkbox" checked>Motion</label></div></section>';
  const body = index
    ? '<div class="review-index">' +
      pages
        .slice(1)
        .map(
          (p) =>
            '<a class="review-destination" href="' +
            p.file +
            '"><span class="review-kicker">' +
            p.label +
            "</span><h2>" +
            p.title +
            "</h2><p>" +
            p.description +
            "</p><span>Open preview →</span></a>",
        )
        .join("") +
      "</div>"
    : read(page.file);
  const html =
    '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n<title>' +
    page.label +
    " · Companion reviews</title>\n<style>\n" +
    read("review.css") +
    "\n</style>\n" +
    (index ? "" : "<script>\n" + read("review.js") + "\n</script>") +
    '\n</head>\n<body>\n<a class="review-skip" href="#review-main">Skip to preview</a><header>' +
    nav +
    '<span class="review-kicker">Local review / early concepts</span><h1 class="review-heading">' +
    page.title +
    '</h1><p class="review-lede">' +
    page.description +
    "</p>" +
    notice +
    controls +
    '</header>\n<main id="review-main" tabindex="-1">\n' +
    body +
    '\n</main>\n<noscript><p>Enable JavaScript to use the interactive controls. These files work offline.</p></noscript>\n<footer class="review-footer"><a href="index.html">All reviews</a><a href="../onboarding-review-2026-09-24.md">Onboarding notes</a><a href="../companion-polish-review-2026-09-25.md">Companion notes</a><span>Self-contained local files · no external calls</span></footer>\n</body>\n</html>\n';
  const path = resolve(out, page.file);
  if (check) {
    if (readFileSync(path, "utf8") !== html)
      throw new Error(
        page.file + " is stale. Run node desktop/design/review/src/build.mjs",
      );
  } else writeFileSync(path, html);
}
console.log(
  check
    ? "All four companion review pages match their sources."
    : "Built four standalone companion review pages.",
);
