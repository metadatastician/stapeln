// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>

import { assert, assertEquals, assertExists } from "../test_assert.js";

const REPOSITORY_ROOT = new URL("../../", import.meta.url);
const FULL_COMMIT_SHA = /^[0-9a-f]{40}$/;

async function readRepositoryFile(path: string): Promise<string> {
  return await Deno.readTextFile(new URL(path, REPOSITORY_ROOT));
}

function dependabotPullRequestLimits(
  source: string,
): Map<string, number | undefined> {
  const limits = new Map<string, number | undefined>();
  let currentEcosystem: string | undefined;

  for (const line of source.split("\n")) {
    const ecosystem = line.match(
      /^[ ]{2}- package-ecosystem:\s*["']([^"']+)["']/,
    );
    if (ecosystem) {
      currentEcosystem = ecosystem[1];
      assert(
        !limits.has(currentEcosystem),
        `duplicate Dependabot entry for ${currentEcosystem}`,
      );
      limits.set(currentEcosystem, undefined);
      continue;
    }

    const limit = line.match(/^[ ]{4}open-pull-requests-limit:\s*(\d+)\s*$/);
    if (limit && currentEcosystem) {
      limits.set(currentEcosystem, Number(limit[1]));
    }
  }

  return limits;
}

function usesReferences(source: string): string[] {
  return [...source.matchAll(/^\s*uses:\s*([^\s#]+)(?:\s+#.*)?$/gm)]
    .map((match) => match[1]);
}

function splitUsesReference(
  reference: string,
): { target: string; revision: string } {
  const separator = reference.lastIndexOf("@");
  assert(separator > 0, `uses reference lacks a revision: ${reference}`);
  return {
    target: reference.slice(0, separator),
    revision: reference.slice(separator + 1),
  };
}

function actionRepository(target: string): string {
  const [owner, repository] = target.split("/");
  assert(Boolean(owner && repository), `invalid action target: ${target}`);
  return `${owner}/${repository}`;
}

function lockedActionCommits(source: string): Map<string, string[]> {
  const commits = new Map<string, string[]>();
  let currentDependency: string | undefined;

  for (const line of source.split("\n")) {
    const dependency = line.match(/^[ ]{4}'([^']+@[^']+)':\s*$/);
    if (dependency) {
      currentDependency = dependency[1];
      continue;
    }

    const commit = line.match(/^[ ]{8}commit:\s*'sha1-([0-9a-f]{40})'\s*$/);
    if (!commit || !currentDependency) continue;

    const target = currentDependency.slice(
      0,
      currentDependency.lastIndexOf("@"),
    );
    const existing = commits.get(target) ?? [];
    existing.push(commit[1]);
    commits.set(target, existing);
  }

  return commits;
}

Deno.test("Dependabot: each ecosystem keeps its intended open-PR limit", async () => {
  const source = await readRepositoryFile(".github/dependabot.yml");
  const limits = dependabotPullRequestLimits(source);

  assertEquals(
    Object.fromEntries(limits),
    {
      "github-actions": 2,
      cargo: 0,
      mix: 3,
      npm: 3,
      pip: 3,
      nix: undefined,
    },
    "Dependabot limits must throttle routine updates without re-enabling Cargo version PRs",
  );
});

/** The per-workflow dependency list recorded in actions.lock. */
function lockedWorkflowDependencies(
  source: string,
): Map<string, string[]> {
  const dependencies = new Map<string, string[]>();
  let current: string | undefined;

  for (const line of source.split("\n")) {
    const workflow = line.match(/^ {4}'([^']+\.ya?ml)':\s*$/);
    if (workflow) {
      current = workflow[1];
      dependencies.set(current, []);
      continue;
    }
    const dependency = line.match(/^ {8}- '([^']+)'\s*$/);
    if (dependency && current) {
      (dependencies.get(current) as string[]).push(dependency[1]);
    }
  }

  return dependencies;
}

Deno.test("CodeQL: every action is pinned by the lockfile and checkout credentials are discarded", async () => {
  const [source, lockfile] = await Promise.all([
    readRepositoryFile(".github/workflows/codeql.yml"),
    readRepositoryFile(".github/workflows/actions.lock"),
  ]);
  const references = usesReferences(source);

  assertEquals(
    references.length,
    3,
    "CodeQL workflow should have checkout, init, and analyze actions",
  );

  // This repository HAS an actions.lock, so the lockfile is the pin authority
  // for its own actions and the workflow carries the tag ref. Asserting an
  // inline SHA *as well* demanded a second hand-maintained copy of the pin; when
  // the copies disagreed GitHub rejected the workflow at startup and the
  // security scanner stopped running without producing a failing check.
  const locked = lockedWorkflowDependencies(lockfile).get(
    ".github/workflows/codeql.yml",
  );
  assertExists(locked, "actions.lock must record the CodeQL workflow");
  for (const reference of references) {
    const { target, revision } = splitUsesReference(reference);
    const dependency = `${actionRepository(target)}@${revision}`;
    assert(
      locked.includes(dependency),
      `${reference} is not recorded in the actions.lock entry for codeql.yml ` +
        `(locked: ${locked.join(", ")}) — regenerate the lockfile in the same ` +
        `commit as any uses: change, or the workflow fails to start`,
    );
  }

  assert(
    /- name:\s*Checkout\s*\n\s*uses:\s*actions\/checkout@\S+\s*(?:#[^\n]*)?\n\s*with:\s*\n\s*persist-credentials:\s*false\s*(?:\n|$)/
      .test(source),
    "persist-credentials: false must be configured on the checkout step",
  );

  const codeqlRevisions = references
    .map(splitUsesReference)
    .filter(({ target }) => target.startsWith("github/codeql-action/"))
    .map(({ revision }) => revision);
  assertEquals(
    codeqlRevisions.length,
    2,
    "CodeQL init and analyze steps must both be present",
  );
  assertEquals(
    new Set(codeqlRevisions).size,
    1,
    "CodeQL init and analyze must use the same action revision",
  );
});

Deno.test("CodeQL: the lockfile commits behind the workflow are immutable", async () => {
  const lockfile = await readRepositoryFile(
    ".github/workflows/actions.lock",
  );
  const locked = lockedActionCommits(lockfile);

  for (const repository of ["actions/checkout", "github/codeql-action"]) {
    const candidates = locked.get(repository) ?? [];
    assert(
      candidates.length > 0,
      `${repository} must be recorded in actions.lock`,
    );
    for (const commit of candidates) {
      assert(
        FULL_COMMIT_SHA.test(commit),
        `${repository} is locked to ${commit}, which is not an immutable ` +
          `40-character commit SHA`,
      );
    }
  }
});

Deno.test("Reusable security workflows use their reviewed immutable revisions", async () => {
  // These must name the revision the workflows ACTUALLY call. The previous
  // values (8f31a5a4, cc58c0cb, 8750b94a) are not reachable from any ref in
  // hyperpolymath/standards: all three return "No commit found" from the API.
  // A pin to a commit that is no longer reachable makes every run a zero-job
  // failure ("workflow was not found"), and `gh pr checks` does not surface it
  // because a rejected workflow produces no checks at all. 8750b94a is the same
  // dead pin that left a sibling repository's Scorecard not running — and it is
  // also not a commit: it is the blob id of scorecard-reusable.yml at standards
  // 1f3eef6. A hard-coded expectation is a safety net only while it is TRUE, so
  // when a reusable is deliberately re-pinned, update this map in the same
  // commit as the workflows.
  const expectedReferences: Record<string, string> = {
    ".github/workflows/governance.yml":
      "hyperpolymath/standards/.github/workflows/governance-reusable.yml@fad242d35291de1898242d6737ba02b74a59a2f2",
    ".github/workflows/hypatia-scan.yml":
      "hyperpolymath/standards/.github/workflows/hypatia-scan-reusable.yml@fad242d35291de1898242d6737ba02b74a59a2f2",
    ".github/workflows/scorecard.yml":
      "hyperpolymath/standards/.github/workflows/scorecard-reusable.yml@fad242d35291de1898242d6737ba02b74a59a2f2",
  };

  for (const [path, expectedReference] of Object.entries(expectedReferences)) {
    const references = usesReferences(await readRepositoryFile(path));
    assertEquals(
      references,
      [expectedReference],
      `${path} must call the reviewed reusable workflow revision`,
    );

    const { revision } = splitUsesReference(references[0]);
    assert(
      FULL_COMMIT_SHA.test(revision),
      `${path} must not use a mutable branch or tag`,
    );
  }
});
