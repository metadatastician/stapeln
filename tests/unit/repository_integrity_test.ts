// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>

import { assert, assertEquals } from "../test_assert.js";

const REPOSITORY_ROOT = new URL("../../", import.meta.url);

async function readRepositoryFile(path: string): Promise<string> {
  return await Deno.readTextFile(new URL(path, REPOSITORY_ROOT));
}

async function repositoryFileExists(path: string): Promise<boolean> {
  try {
    const stat = await Deno.stat(new URL(path, REPOSITORY_ROOT));
    return stat.isFile;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
}

Deno.test("Repository metadata: removed container-stack gitlinks have no stale submodule entries", async () => {
  const gitmodules = await readRepositoryFile(".gitmodules");
  const removedGitlinks = ["cerro-torre", "rokur", "selur", "svalinn", "vordr"];

  for (const name of removedGitlinks) {
    const path = `container-stack/${name}`;
    assert(
      !gitmodules.includes(`path = ${path}`),
      `.gitmodules still declares removed gitlink ${path}`,
    );
  }
});

Deno.test("Runtime integration fixture: every declared rootfs diff ID has a blob", async () => {
  const layoutRoot =
    "verified-container-spec/vectors/runtime-integration/valid-bundle/oci-layout";
  const index = JSON.parse(
    await readRepositoryFile(`${layoutRoot}/index.json`),
  );

  assertEquals(
    index.schemaVersion,
    2,
    "valid bundle must use OCI image layout schema version 2",
  );
  assert(Array.isArray(index.manifests), "OCI index must declare manifests");
  assert(
    index.manifests.length > 0,
    "OCI index must contain at least one manifest",
  );

  for (const descriptor of index.manifests) {
    assert(
      typeof descriptor.digest === "string" &&
        descriptor.digest.startsWith("sha256:"),
      "OCI descriptor digest must be a sha256 digest",
    );
    const descriptorDigest = descriptor.digest.slice("sha256:".length);
    const descriptorPath = `${layoutRoot}/blobs/sha256/${descriptorDigest}`;
    assert(
      await repositoryFileExists(descriptorPath),
      `missing OCI descriptor blob ${descriptor.digest}`,
    );

    const descriptorBytes = await Deno.readFile(
      new URL(descriptorPath, REPOSITORY_ROOT),
    );
    assertEquals(
      descriptorBytes.byteLength,
      descriptor.size,
      `OCI descriptor ${descriptor.digest} has the wrong recorded size`,
    );

    const configuration = JSON.parse(new TextDecoder().decode(descriptorBytes));
    const diffIds = configuration.rootfs?.diff_ids;
    assert(
      Array.isArray(diffIds),
      `OCI descriptor ${descriptor.digest} must declare rootfs.diff_ids`,
    );
    assert(
      diffIds.length > 0,
      `OCI descriptor ${descriptor.digest} must declare at least one layer`,
    );

    for (const diffId of diffIds) {
      assert(
        typeof diffId === "string" && diffId.startsWith("sha256:"),
        `invalid rootfs diff ID ${String(diffId)}`,
      );
      const layerPath = `${layoutRoot}/blobs/sha256/${
        diffId.slice("sha256:".length)
      }`;
      assert(
        await repositoryFileExists(layerPath),
        `missing OCI layer blob ${diffId}`,
      );
    }
  }
});
