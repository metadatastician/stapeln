import { assert, assertEquals } from "../test_assert.js";

const workflow = await Deno.readTextFile(
  new URL("../../.github/workflows/dogfood-gate.yml", import.meta.url),
);
const lock = await Deno.readTextFile(
  new URL("../../.github/workflows/actions.lock", import.meta.url),
);
const jobs = workflow.split(/\njobs:\n/)[1];
assert(jobs, "Dogfood workflow has no jobs section");

function job(name) {
  const entries = [...jobs.matchAll(/^  ([\w-]+):\s*$/gm)];
  const index = entries.findIndex((entry) => entry[1] === name);
  assert(index !== -1, `Missing workflow job: ${name}`);
  return jobs.slice(entries[index].index, entries[index + 1]?.index);
}

function scorecardScript() {
  const match = job("dogfood-summary").match(
    /^      - name: Generate dogfooding scorecard\n        run: \|\n((?: {10}.*\n|\n)*)/m,
  );
  assert(match, "Missing dogfooding scorecard shell step");
  return match[1].split("\n").map((line) => line.replace(/^ {10}/, "")).join("\n");
}

async function renderScorecard(files) {
  const directory = await Deno.makeTempDir();
  try {
    for (const [name, content] of Object.entries(files)) {
      const path = `${directory}/${name}`;
      await Deno.mkdir(path.substring(0, path.lastIndexOf("/")), { recursive: true });
      await Deno.writeTextFile(path, content);
    }
    const summaryPath = `${directory}/summary.md`;
    const result = await new Deno.Command("bash", {
      args: ["-c", scorecardScript()],
      cwd: directory,
      env: { GITHUB_STEP_SUMMARY: summaryPath },
      stdout: "piped",
      stderr: "piped",
    }).output();
    assertEquals(result.code, 0, new TextDecoder().decode(result.stderr));
    return await Deno.readTextFile(summaryPath);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}

Deno.test("retired A2ML job is absent while surviving validation jobs remain", () => {
  assertEquals(
    [...jobs.matchAll(/^  ([\w-]+):\s*$/gm)].map((entry) => entry[1]).sort(),
    ["dogfood-summary", "empty-lint", "groove-check", "k9-validate"].sort(),
  );
  assert(!/a2ml/i.test(workflow), "A2ML gate remains in the workflow");
});

Deno.test("summary waits for surviving jobs even if a validation job fails", () => {
  const summary = job("dogfood-summary");
  const needs = summary.match(/^    needs: \[([^\]]+)\]$/m);
  assert(needs, "Summary has no explicit validation dependencies");
  assertEquals(
    needs[1].split(",").map((name) => name.trim()).sort(),
    ["empty-lint", "groove-check", "k9-validate"].sort(),
  );
  assert(/^    if: always\(\)$/m.test(summary), "Summary must run after failed jobs");
});

Deno.test("action lock reflects the workflow without an orphaned A2ML dependency", () => {
  const entry = lock.match(
    /^    '\.github\/workflows\/dogfood-gate\.yml':\n((?:        - '[^']+'\n)*)/m,
  );
  assert(entry, "Dogfood workflow is missing from the action lock");
  const locked = [...entry[1].matchAll(/^        - '([^']+)'$/gm)]
    .map((match) => match[1]).sort();
  const used = [...new Set([...workflow.matchAll(/^\s+uses: ([^\s#]+)/gm)]
    .map((match) => match[1].replace(/\/validate-action(?=@)/, "")))].sort();
  assertEquals(locked, used, "Locked actions do not match the workflow's uses");
  assert(/^    'hyperpolymath\/k9-ecosystem@main':/m.test(lock));
  assert(!/a2ml-ecosystem/i.test(lock), "Retired action remains in the lock");
});

Deno.test("empty and A2ML-only repositories both score zero of four", async () => {
  const empty = await renderScorecard({});
  const retiredOnly = await renderScorecard({ "0-AI-MANIFEST.a2ml": "retired" });
  assertEquals(retiredOnly, empty, "A2ML must not change the scorecard");
  assert(empty.includes("**Score: 0/4**"));
  assert(!/A2ML/i.test(empty), "Retired format still appears in the scorecard");
  assertEquals((empty.match(/^\| (?:K9 contracts|\.editorconfig|Groove endpoint|VeriSimDB integration) \|/gm) ?? []).length, 4);
});

Deno.test("all four surviving scorecard signals reach the maximum", async () => {
  const summary = await renderScorecard({
    "contract.k9": "contract",
    ".editorconfig": "root = true",
    ".well-known/groove/manifest.json": "{}",
    "config.toml": "db = 'VeriSimDB'",
    "0-AI-MANIFEST.a2ml": "retired",
  });
  assert(summary.includes("**Score: 4/4**"));
  assertEquals((summary.match(/\| :white_check_mark: \|/g) ?? []).length, 4);
  assert(!/A2ML/i.test(summary));
});

Deno.test("alternate K9 extension alone scores one without optional signals", async () => {
  const summary = await renderScorecard({ "contract.k9.ncl": "contract" });
  assert(summary.includes("**Score: 1/4**"));
  assert(summary.includes("| K9 contracts | :white_check_mark: |"));
  assert(summary.includes("| .editorconfig | :x: |"));
  assert(summary.includes("| Groove endpoint | :ballot_box_with_check: |"));
  assert(summary.includes("| VeriSimDB integration | :ballot_box_with_check: |"));
});
