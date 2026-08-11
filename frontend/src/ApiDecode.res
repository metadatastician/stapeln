// SPDX-License-Identifier: MPL-2.0
// ApiDecode.res - Pure JSON response decoders.
//
// No DOM/React imports on purpose: this module must compile to a plain
// .res.js importable straight from Deno for unit testing (see
// tests/unit/api_decode_test.js).

// Decode the response body of `POST /api/stacks` / `PUT /api/stacks/:id`
// (`%{"data" => %{"id" => n, ...}}`) into the stack's integer id.
//
// This replaces the old `Int.fromString(bodyText)` approach, which parsed
// the *entire* JSON body as an integer literal and therefore always failed
// (`None`), silently defaulting to stack id `0` — which the backend's
// `id > 0` guard always rejected with 400.
let decodeSaveResponse = (json: JSON.t): result<int, string> => {
  switch json {
  | Object(obj) =>
    switch Dict.get(obj, "data") {
    | Some(Object(data)) =>
      switch Dict.get(data, "id") {
      | Some(Number(n)) => Ok(Float.toInt(n))
      | _ => Error("missing stack id in response")
      }
    | _ => Error("missing stack id in response")
    }
  | _ => Error("missing stack id in response")
  }
}
