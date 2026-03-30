# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Stapeln.SupplyChainAnalyzer - Analyzes container supply chain integrity
# for a pipeline. Detects trust boundary crossings, SBOM gaps, unsigned
# images, and provenance issues.

defmodule Stapeln.SupplyChainAnalyzer do
  @moduledoc """
  Container supply chain analysis engine.

  Inspects a pipeline's source images, registries, and build steps to
  produce a supply chain risk assessment. This is the static-analysis
  counterpart to the dynamic `SimulationEngine` — it answers "is this
  pipeline trustworthy?" rather than "does this pipeline work?"

  ## Analysis dimensions

  1. **Image provenance** — Where do base images come from? Are they signed?
  2. **Registry trust** — Are registries trusted, authenticated, using TLS?
  3. **SBOM coverage** — Do all images have Software Bills of Materials?
  4. **Build integrity** — Are build steps reproducible? Any network fetches?
  5. **Dependency chains** — How deep is the dependency tree? Any circular deps?
  6. **Trust boundaries** — Where do trust boundaries cross in the pipeline?

  ## SLSA compliance levels

  The analyzer maps pipeline properties to SLSA (Supply-chain Levels for
  Software Artifacts) levels:

  - **SLSA 0**: No provenance (unsigned, unknown registry)
  - **SLSA 1**: Build exists but is not verifiable
  - **SLSA 2**: Hosted, tamper-resistant build (signed images, known registry)
  - **SLSA 3**: Hardened builds (Chainguard images, SBOM, signed, pinned digests)

  ## Usage

      report = Stapeln.SupplyChainAnalyzer.analyze(pipeline)
      # => %{slsa_level: 2, risk_score: ..., findings: [...], trust_map: [...]}
  """

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type trust_boundary :: %{
          from_node: String.t(),
          to_node: String.t(),
          boundary_type: atom(),
          risk: atom()
        }

  @type image_provenance :: %{
          image: String.t(),
          node_id: String.t(),
          registry: String.t(),
          signed: boolean(),
          sbom: boolean(),
          pinned: boolean(),
          chainguard: boolean(),
          slsa_level: non_neg_integer()
        }

  @type analysis_result :: %{
          slsa_level: non_neg_integer(),
          risk_score: float(),
          findings: [map()],
          image_provenance: [image_provenance()],
          trust_boundaries: [trust_boundary()],
          dependency_depth: non_neg_integer(),
          reproducible: boolean(),
          recommendations: [String.t()]
        }

  # ---------------------------------------------------------------------------
  # Registry trust database
  # ---------------------------------------------------------------------------

  @registry_trust %{
    "cgr.dev" => %{trust: :high, signing: true, sbom: true, tls: true},
    "ghcr.io" => %{trust: :medium, signing: true, sbom: false, tls: true},
    "gcr.io" => %{trust: :medium, signing: true, sbom: false, tls: true},
    "quay.io" => %{trust: :medium, signing: true, sbom: false, tls: true},
    "docker.io" => %{trust: :low, signing: false, sbom: false, tls: true},
    "registry.hub.docker.com" => %{trust: :low, signing: false, sbom: false, tls: true}
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Perform a full supply chain analysis on a pipeline.

  Returns an analysis_result with SLSA level assessment, risk score,
  findings, image provenance details, and trust boundary crossings.
  """
  @spec analyze(map()) :: analysis_result()
  def analyze(pipeline) when is_map(pipeline) do
    nodes = get_nodes(pipeline)
    connections = get_connections(pipeline)

    # Analyze each source image
    provenance = analyze_image_provenance(nodes)

    # Detect trust boundary crossings
    trust_boundaries = detect_trust_boundaries(nodes, connections)

    # Check build reproducibility
    reproducible = check_reproducibility(nodes)

    # Compute dependency depth
    depth = compute_dependency_depth(nodes, connections)

    # Generate findings
    findings = generate_findings(provenance, trust_boundaries, nodes, reproducible)

    # Compute overall SLSA level (minimum across all images)
    slsa_level =
      case provenance do
        [] -> 0
        imgs -> imgs |> Enum.map(& &1.slsa_level) |> Enum.min()
      end

    # Compute risk score (0 = safe, 100 = dangerous)
    risk_score = compute_risk_score(provenance, trust_boundaries, findings, reproducible)

    # Generate recommendations
    recommendations = generate_recommendations(provenance, findings, reproducible)

    %{
      slsa_level: slsa_level,
      risk_score: risk_score,
      findings: findings,
      image_provenance: provenance,
      trust_boundaries: trust_boundaries,
      dependency_depth: depth,
      reproducible: reproducible,
      recommendations: recommendations
    }
  end

  def analyze(_), do: %{slsa_level: 0, risk_score: 100.0, findings: [],
    image_provenance: [], trust_boundaries: [], dependency_depth: 0,
    reproducible: false, recommendations: ["provide a valid pipeline map"]}

  # ---------------------------------------------------------------------------
  # Image provenance analysis
  # ---------------------------------------------------------------------------

  defp analyze_image_provenance(nodes) do
    nodes
    |> Enum.filter(fn n -> node_type(n) == "source" end)
    |> Enum.map(fn node ->
      config = node_config(node)
      image = to_string(config_value(config, "image") || "unknown")

      registry = extract_registry(image)
      registry_info = Map.get(@registry_trust, registry, %{trust: :unknown, signing: false, sbom: false, tls: false})

      chainguard = String.contains?(image, "cgr.dev/chainguard")
      pinned = String.contains?(image, "@sha256:") or (String.contains?(image, ":") and not String.ends_with?(image, ":latest"))
      signed = chainguard or registry_info.signing
      sbom = chainguard or registry_info.sbom

      trust_level =
        cond do
          chainguard -> :high
          registry_info.trust == :medium -> :medium
          registry_info.trust == :low -> :low
          true -> :unknown
        end

      slsa_level =
        cond do
          chainguard and pinned -> 3
          signed and pinned -> 2
          signed or pinned -> 1
          true -> 0
        end

      %{
        image: image,
        node_id: node_id(node),
        registry: registry,
        trust_level: trust_level,
        signed: signed,
        sbom: sbom,
        pinned: pinned,
        chainguard: chainguard,
        slsa_level: slsa_level
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Trust boundary detection
  # ---------------------------------------------------------------------------

  defp detect_trust_boundaries(nodes, connections) do
    node_index = Map.new(nodes, fn n -> {node_id(n), n} end)

    connections
    |> Enum.flat_map(fn conn ->
      from_id = conn_from(conn)
      to_id = conn_to(conn)
      from_node = Map.get(node_index, from_id)
      to_node = Map.get(node_index, to_id)

      if from_node && to_node do
        detect_boundary(from_node, to_node)
      else
        []
      end
    end)
  end

  defp detect_boundary(from_node, to_node) do
    from_type = node_type(from_node)
    to_type = node_type(to_node)
    boundaries = []

    # Source to run: trust boundary between external image and local commands
    boundaries =
      if from_type == "source" and to_type == "run" do
        [%{
          from_node: node_id(from_node),
          to_node: node_id(to_node),
          boundary_type: :image_to_build,
          risk: :medium
        } | boundaries]
      else
        boundaries
      end

    # Copy into container: trust boundary between host filesystem and container
    boundaries =
      if to_type == "copy" do
        [%{
          from_node: node_id(from_node),
          to_node: node_id(to_node),
          boundary_type: :host_to_container,
          risk: :low
        } | boundaries]
      else
        boundaries
      end

    # Before push: trust boundary between build environment and registry
    boundaries =
      if to_type == "push" do
        risk = if from_type == "security_gate", do: :low, else: :high
        [%{
          from_node: node_id(from_node),
          to_node: node_id(to_node),
          boundary_type: :build_to_registry,
          risk: risk
        } | boundaries]
      else
        boundaries
      end

    boundaries
  end

  # ---------------------------------------------------------------------------
  # Reproducibility check
  # ---------------------------------------------------------------------------

  defp check_reproducibility(nodes) do
    # A build is reproducible if:
    # 1. All source images are pinned (not :latest)
    # 2. No RUN commands fetch from network
    # 3. No dynamic commands (date, $RANDOM, etc.)

    all_pinned =
      nodes
      |> Enum.filter(fn n -> node_type(n) == "source" end)
      |> Enum.all?(fn n ->
        image = to_string(config_value(node_config(n), "image") || "")
        String.contains?(image, "@sha256:") or
          (String.contains?(image, ":") and not String.ends_with?(image, ":latest"))
      end)

    no_network_fetch =
      nodes
      |> Enum.filter(fn n -> node_type(n) == "run" end)
      |> Enum.all?(fn n ->
        cmds = get_commands(node_config(n))
        not Enum.any?(cmds, fn cmd ->
          cmd_str = to_string(cmd)
          String.contains?(cmd_str, "curl") or
            String.contains?(cmd_str, "wget") or
            String.contains?(cmd_str, "git clone")
        end)
      end)

    no_dynamic =
      nodes
      |> Enum.filter(fn n -> node_type(n) == "run" end)
      |> Enum.all?(fn n ->
        cmds = get_commands(node_config(n))
        not Enum.any?(cmds, fn cmd ->
          cmd_str = to_string(cmd)
          String.contains?(cmd_str, "$(date") or
            String.contains?(cmd_str, "$RANDOM") or
            String.contains?(cmd_str, "`date")
        end)
      end)

    all_pinned and no_network_fetch and no_dynamic
  end

  # ---------------------------------------------------------------------------
  # Dependency depth computation
  # ---------------------------------------------------------------------------

  defp compute_dependency_depth(nodes, connections) do
    # Longest path in the DAG = dependency depth
    node_ids = Enum.map(nodes, &node_id/1)
    outgoing = build_outgoing_map(connections)

    node_ids
    |> Enum.map(fn id -> longest_path(id, outgoing, MapSet.new()) end)
    |> Enum.max(fn -> 0 end)
  end

  defp longest_path(node_id, outgoing, visited) do
    if MapSet.member?(visited, node_id) do
      0
    else
      neighbours = Map.get(outgoing, node_id, [])
      new_visited = MapSet.put(visited, node_id)

      case neighbours do
        [] ->
          1

        _ ->
          1 + (neighbours |> Enum.map(fn n -> longest_path(n, outgoing, new_visited) end) |> Enum.max())
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Findings generation
  # ---------------------------------------------------------------------------

  defp generate_findings(provenance, trust_boundaries, nodes, reproducible) do
    findings = []

    # Unsigned images
    unsigned = Enum.filter(provenance, fn p -> not p.signed end)

    findings =
      findings ++
        Enum.map(unsigned, fn p ->
          %{severity: "high", category: "signing",
            message: "image '#{p.image}' is not signed — cannot verify authenticity",
            node_id: p.node_id}
        end)

    # Missing SBOMs
    no_sbom = Enum.filter(provenance, fn p -> not p.sbom end)

    findings =
      findings ++
        Enum.map(no_sbom, fn p ->
          %{severity: "medium", category: "sbom",
            message: "image '#{p.image}' has no SBOM — cannot audit dependencies",
            node_id: p.node_id}
        end)

    # Unpinned images
    unpinned = Enum.filter(provenance, fn p -> not p.pinned end)

    findings =
      findings ++
        Enum.map(unpinned, fn p ->
          %{severity: "high", category: "pinning",
            message: "image '#{p.image}' is not pinned — vulnerable to tag mutation attacks",
            node_id: p.node_id}
        end)

    # High-risk trust boundaries
    high_risk_boundaries = Enum.filter(trust_boundaries, fn b -> b.risk == :high end)

    findings =
      findings ++
        Enum.map(high_risk_boundaries, fn b ->
          %{severity: "high", category: "trust_boundary",
            message: "high-risk trust boundary: #{b.from_node} -> #{b.to_node} (#{b.boundary_type})",
            node_id: b.to_node}
        end)

    # Non-reproducible build
    findings =
      if not reproducible do
        [%{severity: "medium", category: "reproducibility",
           message: "build is not reproducible — results may vary between runs",
           node_id: "pipeline"} | findings]
      else
        findings
      end

    # Network fetches in build steps
    network_findings =
      nodes
      |> Enum.filter(fn n -> node_type(n) == "run" end)
      |> Enum.flat_map(fn n ->
        cmds = get_commands(node_config(n))
        if Enum.any?(cmds, fn c -> String.contains?(to_string(c), "curl") or String.contains?(to_string(c), "wget") end) do
          [%{severity: "medium", category: "network_fetch",
             message: "RUN step '#{node_id(n)}' fetches from network during build — integrity not guaranteed",
             node_id: node_id(n)}]
        else
          []
        end
      end)

    findings ++ network_findings
  end

  # ---------------------------------------------------------------------------
  # Risk score computation
  # ---------------------------------------------------------------------------

  defp compute_risk_score(provenance, trust_boundaries, findings, reproducible) do
    # Start at 0 (safe) and add risk points
    base = 0.0

    # Unsigned images: +15 each
    unsigned_risk = Enum.count(provenance, fn p -> not p.signed end) * 15.0

    # Unpinned images: +10 each
    unpinned_risk = Enum.count(provenance, fn p -> not p.pinned end) * 10.0

    # High-risk trust boundaries: +10 each
    boundary_risk = Enum.count(trust_boundaries, fn b -> b.risk == :high end) * 10.0

    # Critical findings: +20 each, high: +10, medium: +5
    finding_risk =
      Enum.reduce(findings, 0.0, fn f, acc ->
        case f.severity do
          "critical" -> acc + 20.0
          "high" -> acc + 10.0
          "medium" -> acc + 5.0
          _ -> acc
        end
      end)

    # Non-reproducible: +10
    repro_risk = if reproducible, do: 0.0, else: 10.0

    score = base + unsigned_risk + unpinned_risk + boundary_risk + finding_risk + repro_risk
    Float.round(min(100.0, score), 1)
  end

  # ---------------------------------------------------------------------------
  # Recommendations
  # ---------------------------------------------------------------------------

  defp generate_recommendations(provenance, findings, reproducible) do
    recs = []

    # Recommend Chainguard for non-Chainguard images
    non_cg = Enum.reject(provenance, & &1.chainguard)

    recs =
      if length(non_cg) > 0 do
        ["Switch to Chainguard images for built-in signing, SBOMs, and minimal attack surface" | recs]
      else
        recs
      end

    # Recommend pinning
    unpinned = Enum.reject(provenance, & &1.pinned)

    recs =
      if length(unpinned) > 0 do
        ["Pin all images to specific digests (sha256) for reproducible, tamper-proof builds" | recs]
      else
        recs
      end

    # Recommend reproducibility
    recs =
      if not reproducible do
        ["Remove network fetches from RUN steps and pin all image tags for reproducible builds" | recs]
      else
        recs
      end

    # Recommend security gate if missing
    has_signing_finding = Enum.any?(findings, fn f -> f.category == "signing" end)

    recs =
      if has_signing_finding do
        ["Add image signing (cosign) to your push step for SLSA Level 2+ compliance" | recs]
      else
        recs
      end

    # Recommend higher SLSA level
    min_slsa =
      case provenance do
        [] -> 0
        p -> p |> Enum.map(& &1.slsa_level) |> Enum.min()
      end

    recs =
      if min_slsa < 2 do
        ["Current SLSA level is #{min_slsa} — target Level 2+ with signed images and pinned digests" | recs]
      else
        recs
      end

    Enum.reverse(recs)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp extract_registry(image) do
    image_str = to_string(image)

    cond do
      String.starts_with?(image_str, "cgr.dev/") -> "cgr.dev"
      String.starts_with?(image_str, "ghcr.io/") -> "ghcr.io"
      String.starts_with?(image_str, "gcr.io/") -> "gcr.io"
      String.starts_with?(image_str, "quay.io/") -> "quay.io"
      String.starts_with?(image_str, "docker.io/") -> "docker.io"
      String.contains?(image_str, ".") and String.contains?(image_str, "/") ->
        image_str |> String.split("/") |> List.first()
      true -> "docker.io"
    end
  end

  defp get_nodes(pipeline) do
    case Map.get(pipeline, "nodes", Map.get(pipeline, :nodes, [])) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp get_connections(pipeline) do
    case Map.get(pipeline, "connections", Map.get(pipeline, :connections, [])) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp node_id(node), do: Map.get(node, "id", Map.get(node, :id, ""))
  defp node_type(node), do: Map.get(node, "type", Map.get(node, :type, ""))
  defp node_config(node), do: Map.get(node, "config", Map.get(node, :config, %{}))
  defp conn_from(c), do: Map.get(c, "from", Map.get(c, :from, ""))
  defp conn_to(c), do: Map.get(c, "to", Map.get(c, :to, ""))

  defp config_value(config, key) when is_map(config) do
    Map.get(config, key, Map.get(config, String.to_atom(key), nil))
  end

  defp config_value(_, _), do: nil

  defp get_commands(config) do
    cmds = config_value(config, "commands") || config_value(config, "command") || []
    if is_list(cmds), do: cmds, else: [cmds]
  end

  defp build_outgoing_map(connections) do
    Enum.reduce(connections, %{}, fn c, acc ->
      Map.update(acc, conn_from(c), [conn_to(c)], fn existing -> existing ++ [conn_to(c)] end)
    end)
  end
end
