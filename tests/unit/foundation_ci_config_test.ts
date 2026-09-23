// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>

import { assert, assertEquals } from "../test_assert.js";

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

Deno.test("CodeQL: every action is SHA-pinned and checkout credentials are discarded", async () => {
  const source = await readRepositoryFile(".github/workflows/codeql.yml");
  const references = usesReferences(source);

  assertEquals(
    references.length,
    3,
    "CodeQL workflow should have checkout, init, and analyze actions",
  );
  for (const reference of references) {
    const { revision } = splitUsesReference(reference);
    assert(
      FULL_COMMIT_SHA.test(revision),
      `${reference} must use an immutable 40-character commit SHA`,
    );
  }

  assert(
    /- name:\s*Checkout\s*\n\s*uses:\s*actions\/checkout@[0-9a-f]{40}(?:\s*#[^\n]*)?\n\s*with:\s*\n\s*persist-credentials:\s*false\s*(?:\n|$)/
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

Deno.test("CodeQL: inline action pins agree with the generated actions lockfile", async () => {
  const [workflow, lockfile] = await Promise.all([
    readRepositoryFile(".github/workflows/codeql.yml"),
    readRepositoryFile(".github/workflows/actions.lock"),
  ]);
  const lockedCommits = lockedActionCommits(lockfile);

  for (const reference of usesReferences(workflow)) {
    const { target, revision } = splitUsesReference(reference);
    const repository = actionRepository(target);
    const candidates = lockedCommits.get(repository) ?? [];
    assertEquals(
      candidates.length,
      1,
      `${repository} must resolve to exactly one locked revision`,
    );
    assertEquals(
      revision,
      candidates[0],
      `${reference} does not match the revision recorded in actions.lock`,
    );
  }
});

Deno.test("Reusable security workflows use their reviewed immutable revisions", async () => {
  const expectedReferences: Record<string, string> = {
    ".github/workflows/governance.yml":
      "hyperpolymath/standards/.github/workflows/governance-reusable.yml@8f31a5a4ba591d544b65f91f6d78b136e07756f0",
    ".github/workflows/hypatia-scan.yml":
      "hyperpolymath/standards/.github/workflows/hypatia-scan-reusable.yml@cc58c0cb23f73fc2019ce85a56a468e5248a93b3",
    ".github/workflows/scorecard.yml":
      "hyperpolymath/standards/.github/workflows/scorecard-reusable.yml@8750b94ac1bbe8c51ad13fe106669b13478f0b62",
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
