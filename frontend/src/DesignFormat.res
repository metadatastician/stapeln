// SPDX-License-Identifier: MPL-2.0
// DesignFormat.res - JSON schema for stapeln designs

open Model

// Design file format version
let currentVersion = "1.0"

type designMetadata = {
  version: string,
  created: string,
  author: string,
  description: string,
  // User-facing stack name. Serialized as a top-level "name" key (see
  // serializeDesign) — the backend's `derive_name` reads `params["name"]`
  // first, falling back to `metadata.description` and then the literal
  // "stapeln-stack" only when both are empty. Kept out of `designMetadata`'s
  // own JSON sub-object so it lines up with that contract.
  name: string,
}

type designFile = {
  metadata: designMetadata,
  canvas: model,
}

// Serialize component to JSON
let componentToJson = (comp: component): JSON.t => {
  // Convert config dict<string> to dict<JSON.t>
  let configJson = Dict.fromArray(
    comp.config
    ->Dict.toArray
    ->Array.map(((key, value)) => (key, JSON.Encode.string(value))),
  )

  Dict.fromArray([
    ("id", JSON.Encode.string(comp.id)),
    ("type", JSON.Encode.string(componentTypeToString(comp.componentType))),
    (
      "position",
      Dict.fromArray([
        ("x", JSON.Encode.float(comp.position.x)),
        ("y", JSON.Encode.float(comp.position.y)),
      ])->JSON.Encode.object,
    ),
    ("config", configJson->JSON.Encode.object),
  ])->JSON.Encode.object
}

// Deserialize component from JSON
let componentFromJson = (json: JSON.t): option<component> => {
  switch json {
  | Object(obj) => {
      let id = Dict.get(obj, "id")->Option.flatMap(JSON.Decode.string)
      let typeStr = Dict.get(obj, "type")->Option.flatMap(JSON.Decode.string)
      let position = Dict.get(obj, "position")->Option.flatMap(posJson => {
        switch posJson {
        | Object(posObj) => {
            let x = Dict.get(posObj, "x")->Option.flatMap(JSON.Decode.float)
            let y = Dict.get(posObj, "y")->Option.flatMap(JSON.Decode.float)
            switch (x, y) {
            | (Some(x), Some(y)) => Some({x, y})
            | _ => None
            }
          }
        | _ => None
        }
      })
      let config = Dict.get(obj, "config")->Option.flatMap(cfg => {
        switch cfg {
        | Object(dict) => {
            // Convert dict<JSON.t> to dict<string>
            let stringDict = Dict.make()
            dict
            ->Dict.toArray
            ->Array.forEach(((key, value)) => {
              switch JSON.Decode.string(value) {
              | Some(str) => stringDict->Dict.set(key, str)
              | None => () // Skip non-string values
              }
            })
            Some(stringDict)
          }
        | _ => None
        }
      })

      // Convert type string to componentType
      let componentType = switch typeStr {
      | Some("Cerro Torre") => Some(CerroTorre)
      | Some("Lago Grey") => Some(LagoGrey)
      | Some("Svalinn") => Some(Svalinn)
      | Some("selur") => Some(Selur)
      | Some("Vörðr") => Some(Vordr)
      | Some("Podman") => Some(Podman)
      | Some("Docker") => Some(Docker)
      | Some("nerdctl") => Some(Nerdctl)
      | Some("Volume") => Some(Volume)
      | Some("Network") => Some(Network)
      | _ => None
      }

      switch (id, componentType, position, config) {
      | (Some(id), Some(ct), Some(pos), Some(cfg)) =>
        Some({id, componentType: ct, position: pos, config: cfg})
      | _ => None
      }
    }
  | _ => None
  }
}

// Serialize connection to JSON
let connectionToJson = (conn: connection): JSON.t => {
  Dict.fromArray([
    ("id", JSON.Encode.string(conn.id)),
    ("from", JSON.Encode.string(conn.from)),
    ("to", JSON.Encode.string(conn.to)),
  ])->JSON.Encode.object
}

// Deserialize connection from JSON
let connectionFromJson = (json: JSON.t): option<connection> => {
  switch json {
  | Object(obj) => {
      let id = Dict.get(obj, "id")->Option.flatMap(JSON.Decode.string)
      let from = Dict.get(obj, "from")->Option.flatMap(JSON.Decode.string)
      let to = Dict.get(obj, "to")->Option.flatMap(JSON.Decode.string)

      switch (id, from, to) {
      | (Some(id), Some(from), Some(to)) => Some({id, from, to})
      | _ => None
      }
    }
  | _ => None
  }
}

// Serialize model to JSON
let modelToJson = (model: model): JSON.t => {
  Dict.fromArray([
    ("components", model.components->Array.map(componentToJson)->JSON.Encode.array),
    ("connections", model.connections->Array.map(connectionToJson)->JSON.Encode.array),
  ])->JSON.Encode.object
}

// Deserialize model from JSON
let modelFromJson = (json: JSON.t): option<model> => {
  switch json {
  | Object(obj) => {
      let components = Dict.get(obj, "components")->Option.flatMap(arr => {
        switch arr {
        | Array(items) => {
            let parsed = items->Array.map(componentFromJson)->Array.keepMap(x => x)
            Some(parsed)
          }
        | _ => None
        }
      })

      let connections = Dict.get(obj, "connections")->Option.flatMap(arr => {
        switch arr {
        | Array(items) => {
            let parsed = items->Array.map(connectionFromJson)->Array.keepMap(x => x)
            Some(parsed)
          }
        | _ => None
        }
      })

      switch (components, connections) {
      | (Some(comps), Some(conns)) =>
        Some({
          ...initialModel,
          components: comps,
          connections: conns,
        })
      | _ => None
      }
    }
  | _ => None
  }
}

// Serialize full design to JSON string
let serializeDesign = (model: model, metadata: designMetadata): string => {
  let fields = [
    ("version", JSON.Encode.string(metadata.version)),
    (
      "metadata",
      Dict.fromArray([
        ("created", JSON.Encode.string(metadata.created)),
        ("author", JSON.Encode.string(metadata.author)),
        ("description", JSON.Encode.string(metadata.description)),
      ])->JSON.Encode.object,
    ),
    ("canvas", modelToJson(model)),
  ]

  // Only emit a top-level "name" when it's non-empty. The backend's
  // `derive_name` does `Map.get(params, "name") || fallback...`, and in
  // Elixir an empty string is truthy — so sending `"name" => ""` would
  // short-circuit derive_name's fallback to metadata.description /
  // "stapeln-stack" and "stick" every unnamed stack with an empty name
  // instead. Omitting the key entirely when there's nothing to send lets
  // that fallback chain do its job.
  let fields = switch metadata.name {
  | "" => fields
  | name => Array.concat(fields, [("name", JSON.Encode.string(name))])
  }

  JSON.stringify(Dict.fromArray(fields)->JSON.Encode.object)
}

// Deserialize design from JSON string
let deserializeDesign = (jsonStr: string): Result.t<(designMetadata, model), string> => {
  try {
    let json = JSON.parseOrThrow(jsonStr)

    switch json {
    | Object(obj) => {
        let version = Dict.get(obj, "version")->Option.flatMap(JSON.Decode.string)

        // Top-level "name" is optional (older design documents predate it) —
        // default to "" rather than failing the whole parse.
        let name =
          Dict.get(obj, "name")
          ->Option.flatMap(JSON.Decode.string)
          ->Belt.Option.getWithDefault("")

        let metadata = Dict.get(obj, "metadata")->Option.flatMap(metaJson => {
          switch metaJson {
          | Object(metaObj) => {
              let created = Dict.get(metaObj, "created")->Option.flatMap(JSON.Decode.string)
              let author = Dict.get(metaObj, "author")->Option.flatMap(JSON.Decode.string)
              let description =
                Dict.get(metaObj, "description")->Option.flatMap(JSON.Decode.string)

              switch (created, author, description) {
              | (Some(created), Some(author), Some(description)) =>
                Some({
                  version: version->Belt.Option.getWithDefault("1.0"),
                  created,
                  author,
                  description,
                  name,
                })
              | _ => None
              }
            }
          | _ => None
          }
        })

        let canvas = Dict.get(obj, "canvas")->Option.flatMap(modelFromJson)

        switch (metadata, canvas) {
        | (Some(meta), Some(model)) => Ok((meta, model))
        | _ => Error("Invalid design file structure")
        }
      }
    | _ => Error("Design file must be a JSON object")
    }
  } catch {
  | JsExn(e) =>
    Error("JSON parse error: " ++ JsExn.message(e)->Belt.Option.getWithDefault("Unknown error"))
  }
}
