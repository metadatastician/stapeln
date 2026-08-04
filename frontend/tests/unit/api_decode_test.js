// SPDX-License-Identifier: MPL-2.0
// api_decode_test.js - Deno unit tests for the compiled ApiDecode.res.js.
//
// Exercises the fix for the 400-always bug: ApiClient.saveStack used to
// return the raw response body text and callers parsed it with
// Int.fromString, which always failed against a JSON object body and
// defaulted to stack id 0 (backend's `id > 0` guard then rejected every
// save with 400). ApiDecode.decodeSaveResponse decodes the id from the
// right place instead.

import { assertEquals } from "jsr:@std/assert@1";
import { decodeSaveResponse } from "../../src/ApiDecode.res.js";

Deno.test("decodeSaveResponse: decodes the id from a well-formed save response", () => {
  const result = decodeSaveResponse({ data: { id: 7 } });
  assertEquals(result, { TAG: "Ok", _0: 7 });
});

Deno.test("decodeSaveResponse: errors when data has no id", () => {
  const result = decodeSaveResponse({ data: {} });
  assertEquals(result.TAG, "Error");
});

Deno.test("decodeSaveResponse: errors on an error-shaped response", () => {
  const result = decodeSaveResponse({ error: "x" });
  assertEquals(result.TAG, "Error");
});

Deno.test("decodeSaveResponse: errors when the top-level value isn't an object", () => {
  const result = decodeSaveResponse("not an object");
  assertEquals(result.TAG, "Error");
});

Deno.test("decodeSaveResponse: errors when data.id isn't a number", () => {
  const result = decodeSaveResponse({ data: { id: "7" } });
  assertEquals(result.TAG, "Error");
});
