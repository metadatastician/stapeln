// SPDX-License-Identifier: MPL-2.0
//
// Unit tests for the repository automation changed by PR #76. These tests keep
// the security-sensitive workflow pins, checkout settings, and Dependabot
// limits from drifting independently.

import { assert, assertEquals, assertExists } from "../test_assert.js";

const REPOSITORY_ROOT = new URL("../../", import.meta.url);
const FULL_SHA = /^[0-9a-f]{40}$/;

interface DependabotUpdate {
  ecosystem: string;
  directory?: string;
  interval?: string;
  openPullRequestsLimit?: number;
}

interface UsesReference {
  action: string;
  revision: string;
  versionComment?: string;
}

function repositoryFile(path: string): URL {
  return new URL(path, REPOSITORY_ROOT);
}

async function readRepositoryFile(path: string): Promise<string> {
  return await Deno.readTextFile(repositoryFile(path));
}

function unquote(value: string): string {
  return value.trim().replace(/^(["'])(.*)\1$/, "$2");
}

function parseDependabotUpdates(source: string): DependabotUpdate[] {
  const starts = [...source.matchAll(/^ {2}- package-ecosystem:\s*(.+)$/gm)];

  return starts.map((match, index) => {
    const start = match.index ?? 0;
    const end = starts[index + 1]?.index ?? source.length;
    const block = source.slice(start, end);
    const directory = block.match(/^ {4}directory:\s*(.+)$/m)?.[1];
    const interval = block.match(/^ {6}interval:\s*(.+)$/m)?.[1];
    const limit = block.match(/^ {4}open-pull-requests-limit:\s*(\d+)\s*$/m)
      ?.[1];

    return {
      ecosystem: unquote(match[1]),
      directory: directory === undefined ? undefined : unquote(directory),
      interval: interval === undefined ? undefined : unquote(interval),
      openPullRequestsLimit: limit === undefined ? undefined : Number(limit),
    };
  });
}

function parseUsesReferences(source: string): UsesReference[] {
  return [...source.matchAll(/^\s+uses:\s*([^\s#]+)(?:\s+#\s*(\S+))?\s*$/gm)]
    .map(
      (match) => {
        const separator = match[1].lastIndexOf("@");
        assert(separator > 0, `uses reference has no revision: ${match[1]}`);
        return {
          action: match[1].slice(0, separator),
          revision: match[1].slice(separator + 1),
          versionComment: match[2],
        };
      },
    );
}

function isFullShaPin(reference: UsesReference): boolean {
  return FULL_SHA.test(reference.revision);
}

function workflowStep(source: string, name: string): string | undefined {
  const steps = source.split(/(?=^ {6}- name: )/m);
  return steps.find((step) => step.startsWith(`      - name: ${name}\n`));
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function workflowJob(source: string, name: string): string | undefined {
  const start = new RegExp(`^ {2}${escapeRegExp(name)}:\\s*$`, "m").exec(
    source,
  );
  if (start?.index === undefined) return undefined;

  const job = source.slice(start.index);
  const afterHeader = job.slice(start[0].length);
  const nextJob = /^ {2}[A-Za-z0-9_-]+:\s*$/m.exec(afterHeader);
  return nextJob?.index === undefined
    ? job
    : job.slice(0, start[0].length + nextJob.index);
}

function lockedCommit(
  lockfile: string,
  dependency: string,
): string | undefined {
  const dependencyBlock = new RegExp(
    `^    '${
      escapeRegExp(dependency)
    }':\\n([\\s\\S]*?)(?=^    '[^']+':|(?![\\s\\S]))`,
    "m",
  ).exec(lockfile)?.[1];
  return dependencyBlock?.match(/^ {8}commit:\s*'sha1-([0-9a-f]{40})'\s*$/m)
    ?.[1];
}

Deno.test("Dependabot: changed ecosystems have the intended pull request limits", async () => {
  const updates = parseDependabotUpdates(
    await readRepositoryFile(".github/dependabot.yml"),
  );
  const limits = new Map(
    updates.map((update) => [update.ecosystem, update.openPullRequestsLimit]),
  );

  assertEquals(limits.get("github-actions"), 2);
  assertEquals(limits.get("cargo"), 0);
  assertEquals(limits.get("mix"), 3);
  assertEquals(limits.get("npm"), 3);
  assertEquals(limits.get("pip"), 3);
});

Deno.test("Dependabot: adjacent update blocks do not inherit another ecosystem's limit", async () => {
  const updates = parseDependabotUpdates(
    await readRepositoryFile(".github/dependabot.yml"),
  );
  const byEcosystem = new Map(
    updates.map((update) => [update.ecosystem, update]),
  );

  assertEquals(
    byEcosystem.size,
    6,
    "every configured ecosystem should be parsed exactly once",
  );
  assertEquals(byEcosystem.get("cargo")?.openPullRequestsLimit, 0);
  assertEquals(byEcosystem.get("mix")?.openPullRequestsLimit, 3);
  assertEquals(
    byEcosystem.get("nix")?.openPullRequestsLimit,
    undefined,
    "the final Nix block must not inherit pip's limit",
  );

  for (const update of updates) {
    assertEquals(
      update.directory,
      "/",
      `${update.ecosystem} should continue to scan the repository root`,
    );
    assertEquals(
      update.interval,
      "weekly",
      `${update.ecosystem} should retain its weekly schedule`,
    );
  }
});

Deno.test("Workflow security: every reusable-workflow call is pinned to a full commit SHA", async () => {
  // A `uses:` that points into ANOTHER repository is not something this
  // repository's actions.lock can resolve — the lockfile covers this
  // repository's own actions and their transitive dependencies, not a job-level
  // call into hyperpolymath/standards. So these three must carry the immutable
  // commit themselves, and a tag or branch is not acceptable.
  //
  // codeql.yml is deliberately absent. It has an actions.lock, and the lockfile
  // is the pin authority for a repository's own actions. Requiring an inline
  // SHA *as well* meant a second, hand-maintained copy of the pin, and when the
  // two disagreed GitHub rejected the whole workflow before any job started
  // ("Invalid lockfile") — so the CodeQL scanner silently stopped running with
  // no failing check to show for it. The equivalent invariant for codeql.yml,
  // that every ref it uses is recorded in the lock, is asserted in
  // foundation_ci_config_test.ts.
  const workflowPaths = [
    ".github/workflows/governance.yml",
    ".github/workflows/hypatia-scan.yml",
    ".github/workflows/scorecard.yml",
  ];

  for (const path of workflowPaths) {
    const references = parseUsesReferences(await readRepositoryFile(path));
    assert(
      references.length > 0,
      `${path} should contain at least one uses reference`,
    );
    for (const reference of references) {
      assert(
        isFullShaPin(reference),
        `${path}: ${reference.action} must use a lowercase 40-character commit SHA`,
      );
    }
  }
});

Deno.test("Workflow security: tag, branch, uppercase, and abbreviated pins are rejected", () => {
  for (
    const revision of [
      "v4.37.6",
      "main",
      "abc1234",
      "A".repeat(40),
      "a".repeat(39),
    ]
  ) {
    assert(
      !isFullShaPin({ action: "example/action", revision }),
      `${revision} must not satisfy the immutable pin contract`,
    );
  }
  assert(isFullShaPin({ action: "example/action", revision: "a".repeat(40) }));
});

Deno.test("CodeQL: checkout credentials are not persisted", async () => {
  const workflow = await readRepositoryFile(".github/workflows/codeql.yml");
  const checkout = workflowStep(workflow, "Checkout");

  assertExists(checkout, "the CodeQL workflow should retain its checkout step");
  assert(
    /^ {10}persist-credentials:\s*false\s*$/m.test(checkout as string),
    "the checkout step must explicitly disable persisted GitHub credentials",
  );
});

Deno.test("CodeQL: initialization and analysis use one immutable action revision", async () => {
  const workflow = await readRepositoryFile(".github/workflows/codeql.yml");
  const references = parseUsesReferences(workflow);
  const init = references.find((reference) =>
    reference.action === "github/codeql-action/init"
  );
  const analyze = references.find((reference) =>
    reference.action === "github/codeql-action/analyze"
  );

  assertExists(init, "the CodeQL initialization action should be present");
  assertExists(analyze, "the CodeQL analysis action should be present");
  const initReference = init as UsesReference;
  const analyzeReference = analyze as UsesReference;
  assertEquals(
    initReference.revision,
    analyzeReference.revision,
    "CodeQL phases should not mix action revisions",
  );
  assertEquals(
    initReference.versionComment,
    analyzeReference.versionComment,
    "CodeQL phases should document one version",
  );

  assert(/^ {10}languages:\s*\$\{\{ matrix\.language \}\}\s*$/m.test(workflow));
  assert(
    /^ {10}build-mode:\s*\$\{\{ matrix\.build-mode \}\}\s*$/m.test(workflow),
  );
  assert(
    /^ {10}category:\s*["']\/language:\$\{\{ matrix\.language \}\}["']\s*$/m
      .test(workflow),
  );
});

Deno.test("CodeQL: every action is recorded in the actions lockfile, with an immutable commit", async () => {
  const workflow = await readRepositoryFile(".github/workflows/codeql.yml");
  const lockfile = await readRepositoryFile(".github/workflows/actions.lock");

  // The lockfile owns the commit; the workflow carries the tag ref. Both halves
  // have to be present: a ref with no lock entry is unpinned, and a lock entry
  // the workflow does not reference is drift GitHub rejects as "Invalid
  // lockfile" — the failure that stopped the CodeQL scanner from running.
  for (const reference of parseUsesReferences(workflow)) {
    const action = reference.action.split("/").slice(0, 2).join("/");
    const dependency = `${action}@${reference.revision}`;
    const commit = lockedCommit(lockfile, dependency);
    assertExists(
      commit,
      `${dependency} should have a dependency entry in actions.lock`,
    );
    assert(
      FULL_SHA.test(commit),
      `${dependency} is locked to ${commit}, which is not an immutable 40-character commit SHA`,
    );
  }
});

Deno.test("Reusable workflows retain their expected entry points and permissions", async () => {
  const expectations = [
    {
      path: ".github/workflows/governance.yml",
      action:
        "hyperpolymath/standards/.github/workflows/governance-reusable.yml",
      permissions: ["actions: read", "contents: read"],
    },
    {
      path: ".github/workflows/hypatia-scan.yml",
      action:
        "hyperpolymath/standards/.github/workflows/hypatia-scan-reusable.yml",
      permissions: [
        "actions: read",
        "contents: read",
        "security-events: write",
      ],
    },
    {
      path: ".github/workflows/scorecard.yml",
      action:
        "hyperpolymath/standards/.github/workflows/scorecard-reusable.yml",
      permissionScope: "scorecard",
      permissions: [
        "actions: read",
        "contents: read",
        "id-token: write",
        "security-events: write",
      ],
    },
  ];

  for (const expectation of expectations) {
    const workflow = await readRepositoryFile(expectation.path);
    const references = parseUsesReferences(workflow);
    assertEquals(
      references.length,
      1,
      `${expectation.path} should delegate to one reusable workflow`,
    );
    assertEquals(references[0].action, expectation.action);
    const permissionScope = expectation.permissionScope === undefined
      ? workflow
      : workflowJob(workflow, expectation.permissionScope);
    assertExists(
      permissionScope,
      `${expectation.path} should contain its ${expectation.permissionScope} job`,
    );
    for (const permission of expectation.permissions) {
      assert(
        (permissionScope as string).includes(permission),
        `${expectation.path} should retain ${permission}`,
      );
    }
  }
});
