import { load } from "./dom-test.mjs";
import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";
const companion = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
load(path.join(companion, "index.html"));
{
  const a = load(path.join(companion, "terminal-creature-lookbook.html"));
  const { $, document, click, event, advance } = a;
  assert.equal(document.querySelectorAll(".pose-button").length, 72);
  assert.equal(document.querySelectorAll("#review-fields select").length, 2);
  click('[data-creature="fish"][data-mood="curious"]');
  assert.match($("#pet-selected-title").textContent, /Fish \/ curious/);
  click("#pet-play-hatch");
  advance(4000);
  assert.match($("#pet-hatch-label").textContent, /hello, little fish/);
  click("#pet-play-mood");
  advance(400);
  click("#pet-reset");
  const before = $("#pet-large").textContent;
  advance(5000);
  assert.equal($("#pet-large").textContent, before);
  const cell = $('.pose-button[data-creature="fish"][data-mood="curious"]');
  event(cell, "keydown", { key: "ArrowRight" });
  assert.equal(document.activeElement.dataset.creature, "spider");
  console.log(
    "PASS creature selection, hatching, cancellation, keyboard comparison and local controls",
  );
}
{
  const a = load(path.join(companion, "egg-status-animation.html"));
  const { $, click, advance } = a;
  assert.ok($("#review-fields").querySelectorAll("select").length === 3);
  click(".egg-resident");
  advance(3000);
  assert.match($(".egg-resident").getAttribute("aria-label"), /Your companion/);
  assert.match($("#egg-review-announcement").textContent, /hatched/);
  click("#egg-preview-reset");
  assert.match($(".egg-resident").getAttribute("aria-label"), /An egg/);
  advance(100000);
  assert.equal(a.timers.size, 0, "No idle egg timers");
  console.log(
    "PASS companion egg hatching, reset, native controls and no idle timers",
  );
}
{
  const a = load(path.join(companion, "developer-onboarding.html"));
  const { $, click, input, event, advance, document } = a;
  const stage = () =>
    [...document.querySelectorAll("[data-view]")].find((el) => !el.hidden)
      .dataset.view;
  click('[data-action="open"]');
  assert.equal(stage(), "project");
  assert.equal(document.activeElement.id, "h-project");
  input("#h-project", "~/projects/example-new");
  click('[data-action="back"]');
  click('[data-action="open"]');
  assert.equal($("#h-project").value, "~/projects/example-new");
  click('[data-action="start"]');
  advance(400);
  click('[data-action="back"]');
  advance(3000);
  assert.equal(stage(), "welcome", "Canceled launch must not navigate");
  click('[data-action="open"]');
  input("#h-project", "   ");
  click('[data-action="start"]');
  advance(3000);
  assert.equal(stage(), "project");
  input("#h-project", "~/projects/example-new");
  click('[data-action="start"]');
  advance(2000);
  assert.equal(stage(), "terminal");
  click('[data-action="explain"]');
  assert.ok($("#h-task").value.length > 0);
  assert.equal(stage(), "terminal", "Starter must remain a draft");
  event($("#h-task"), "keydown", { key: "Enter", ctrlKey: true });
  advance(1200);
  assert.equal(stage(), "answer");
  assert.equal(document.activeElement.dataset.action, "continue");
  click('[data-action="close-pane"]');
  assert.equal(stage(), "return");
  click('[data-action="resume"]');
  assert.equal(stage(), "answer");
  click('[data-action="second"]');
  click('[data-action="prepare-second"]');
  assert.equal(stage(), "project");
  assert.match($('[data-slot="title"]').textContent, /second pane/);
  event($("#h-project"), "keydown", { key: "Escape" });
  assert.equal(stage(), "parallel");
  console.log(
    "PASS onboarding local controls, draft preservation, cancel, validation, starter, submit, focus and return journey",
  );
}
for (const file of [
  "terminal-creature-lookbook.html",
  "egg-status-animation.html",
]) {
  const a = load(path.join(companion, file), { reduced: true });
  if (file.startsWith("terminal")) {
    a.click("#pet-play-hatch");
    assert.match(a.$("#pet-hatch-label").textContent, /hello, little cat/);
  } else {
    a.click(".egg-resident");
    assert.match(a.$("#egg-review-announcement").textContent, /hatched/);
  }
  assert.equal(a.$("#review-motion").checked, false);
}
console.log("PASS reduced-motion hatches in both companion previews");
