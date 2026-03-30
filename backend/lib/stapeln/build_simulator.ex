# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Stapeln.BuildSimulator - Simulates container build execution without running
# real container commands. Produces estimated layer sizes, build times, cache
# hits, and security assessments for each build step.

defmodule Stapeln.BuildSimulator do
  @moduledoc """
  Container build simulation engine.

  Given a pipeline graph (as produced by the Pipeline Designer), this module
  simulates what would happen if each node were executed as a real container
  build step. It does NOT run containers — it uses heuristics and static
  analysis to produce:

  - **Layer manifest**: estimated size, hash placeholder, cache eligibility
  - **Build timeline**: estimated duration per step, parallelisation opportunities
  - **Security posture**: per-layer vulnerability surface, privilege escalation risks
  - **Supply chain trace**: image provenance, registry trust levels, signature status

  ## Design decisions

  - Deterministic: same pipeline + same params = same result (no randomness)
  - Offline: no network calls — all analysis is local heuristic
  - Conservative: estimates err on the side of larger sizes and longer times
  - Chainguard-aware: knows about cgr.dev image sizes and security posture

  ## Usage

      pipeline = %{"nodes" => [...], "connections" => [...]}
      result = Stapeln.BuildSimulator.simulate(pipeline)
      # => %{layers: [...], timeline: [...], total_size: ..., total_time: ..., ...}
  """

  alias Stapeln.PipelineEngine

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type layer :: %{
          node_id: String.t(),
          node_type: String.t(),
          instruction: String.t(),
          estimated_size: non_neg_integer(),
          estimated_time_ms: non_neg_integer(),
          cacheable: boolean(),
          cache_key: String.t(),
          security_notes: [String.t()],
          layer_index: non_neg_integer()
        }

  @type timeline_entry :: %{
          stage: non_neg_integer(),
          node_ids: [String.t()],
          parallel: boolean(),
          estimated_time_ms: non_neg_integer()
        }

  @type supply_chain_entry :: %{
          image: String.t(),
          registry: String.t(),
          trust_level: atom(),
          signed: boolean(),
          sbom_available: boolean(),
          chainguard: boolean()
        }

  @type build_result :: %{
          valid: boolean(),
          layers: [layer()],
          timeline: [timeline_entry()],
          supply_chain: [supply_chain_entry()],
          total_size: non_neg_integer(),
          total_time_ms: non_neg_integer(),
          cache_hit_ratio: float(),
          security_score: float(),
          security_findings: [map()],
          optimisation_hints: [String.t()],
          containerfile_preview: String.t(),
          errors: [String.t()]
        }

  # ---------------------------------------------------------------------------
  # Base image size database (bytes). Conservative estimates.
  # Chainguard images are significantly smaller than traditional distro images.
  # ---------------------------------------------------------------------------

  @base_image_sizes %{
    "cgr.dev/chainguard/static" => 2_200_000,
    "cgr.dev/chainguard/wolfi-base" => 12_500_000,
    "cgr.dev/chainguard/go" => 280_000_000,
    "cgr.dev/chainguard/rust" => 450_000_000,
    "cgr.dev/chainguard/node" => 120_000_000,
    "cgr.dev/chainguard/python" => 95_000_000,
    "cgr.dev/chainguard/postgres" => 85_000_000,
    "cgr.dev/chainguard/redis" => 16_000_000,
    "cgr.dev/chainguard/nginx" => 18_000_000,
    "alpine" => 7_500_000,
    "ubuntu" => 78_000_000,
    "debian" => 125_000_000,
    "fedora" => 180_000_000,
    "node" => 350_000_000,
    "python" => 420_000_000,
    "rust" => 850_000_000,
    "golang" => 320_000_000,
    "nginx" => 45_000_000,
    "postgres" => 130_000_000,
    "redis" => 35_000_000,
    "scratch" => 0
  }

  # Estimated time per package install (milliseconds)
  @pkg_install_time_ms 3_500

  # Estimated time per compilation command (milliseconds)
  @compile_time_ms 15_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Simulate a full container build from a pipeline graph.

  Returns a build_result with layer manifest, timeline, supply chain info,
  and security findings. The simulation is deterministic and offline.
  """
  @spec simulate(map()) :: build_result()
  def simulate(pipeline) when is_map(pipeline) do
    # Step 1: validate the pipeline first
    validation = PipelineEngine.validate(pipeline)

    unless validation.valid do
      %{
        valid: false,
        layers: [],
        timeline: [],
        supply_chain: [],
        total_size: 0,
        total_time_ms: 0,
        cache_hit_ratio: 0.0,
        security_score: 0.0,
        security_findings: [],
        optimisation_hints: [],
        containerfile_preview: "",
        errors: validation.errors
      }
    else
      nodes = get_nodes(pipeline)
      connections = get_connections(pipeline)

      # Step 2: topological sort for build order
      case PipelineEngine.topological_sort(nodes, connections) do
        {:ok, sorted_ids} ->
          node_index = index_nodes(nodes)

          # Step 3: simulate each layer in build order
          {layers, _layer_idx} =
            sorted_ids
            |> Enum.reduce({[], 0}, fn node_id, {acc, idx} ->
              node = Map.get(node_index, node_id)
              layer = simulate_layer(node, idx)
              {[layer | acc], idx + 1}
            end)

          layers = Enum.reverse(layers)

          # Step 4: compute build timeline with parallelisation
          timeline = compute_timeline(sorted_ids, connections, node_index, layers)

          # Step 5: extract supply chain information
          supply_chain = extract_supply_chain(nodes)

          # Step 6: compute aggregate metrics
          total_size = Enum.reduce(layers, 0, fn l, acc -> acc + l.estimated_size end)
          total_time = Enum.reduce(timeline, 0, fn t, acc -> acc + t.estimated_time_ms end)

          cacheable_count = Enum.count(layers, & &1.cacheable)

          cache_hit_ratio =
            if length(layers) > 0,
              do: Float.round(cacheable_count / length(layers), 2),
              else: 0.0

          # Step 7: security analysis
          security_findings = analyze_build_security(layers, supply_chain, nodes)
          security_score = compute_build_security_score(supply_chain, security_findings, nodes)

          # Step 8: optimisation hints
          hints = generate_optimisation_hints(layers, supply_chain, nodes)

          # Step 9: generate Containerfile preview
          preview = generate_containerfile_preview(layers, node_index, sorted_ids)

          %{
            valid: true,
            layers: layers,
            timeline: timeline,
            supply_chain: supply_chain,
            total_size: total_size,
            total_time_ms: total_time,
            cache_hit_ratio: cache_hit_ratio,
            security_score: security_score,
            security_findings: security_findings,
            optimisation_hints: hints,
            containerfile_preview: preview,
            errors: []
          }

        {:error, msg} ->
          %{
            valid: false,
            layers: [],
            timeline: [],
            supply_chain: [],
            total_size: 0,
            total_time_ms: 0,
            cache_hit_ratio: 0.0,
            security_score: 0.0,
            security_findings: [],
            optimisation_hints: [],
            containerfile_preview: "",
            errors: [msg]
          }
      end
    end
  end

  def simulate(_), do: %{valid: false, layers: [], timeline: [], supply_chain: [],
    total_size: 0, total_time_ms: 0, cache_hit_ratio: 0.0, security_score: 0.0,
    security_findings: [], optimisation_hints: [], containerfile_preview: "", errors: ["pipeline must be a map"]}

  # ---------------------------------------------------------------------------
  # Layer simulation
  # ---------------------------------------------------------------------------

  defp simulate_layer(node, layer_index) do
    node_id = node_id(node)
    node_type = node_type(node)
    config = node_config(node)

    {instruction, size, time_ms, cacheable, cache_key, security_notes} =
      case node_type do
        "source" ->
          image = config_value(config, "image") || "unknown"
          size = lookup_base_image_size(image)
          {"FROM #{image}", size, 2_000, false, "base:#{image}",
           source_security_notes(image)}

        "run" ->
          cmds = get_commands(config)
          cmd_str = Enum.join(cmds, " && ")
          {size, time} = estimate_run_impact(cmds)
          cacheable = not Enum.any?(cmds, &dynamic_command?/1)
          {"RUN #{cmd_str}", size, time, cacheable, "run:#{:erlang.phash2(cmd_str)}",
           run_security_notes(cmds)}

        "copy" ->
          src = config_value(config, "src") || "."
          dst = config_value(config, "dst") || "."
          size = estimate_copy_size(src)
          cacheable = not String.contains?(src, "*")
          {"COPY #{src} #{dst}", size, 500, cacheable, "copy:#{src}:#{dst}",
           copy_security_notes(src)}

        "env" ->
          key = config_value(config, "key") || "KEY"
          value = config_value(config, "value") || ""
          notes = env_security_notes(key, value)
          {"ENV #{key}=#{value}", 0, 10, true, "env:#{key}=#{value}", notes}

        "expose" ->
          port = config_value(config, "port") || 0
          notes = expose_security_notes(port)
          {"EXPOSE #{port}", 0, 10, true, "expose:#{port}", notes}

        "workdir" ->
          path = config_value(config, "path") || "/app"
          notes = workdir_security_notes(path)
          {"WORKDIR #{path}", 0, 10, true, "workdir:#{path}", notes}

        "label" ->
          key = config_value(config, "key") || ""
          value = config_value(config, "value") || ""
          {"LABEL #{key}=#{value}", 0, 10, true, "label:#{key}", []}

        "volume" ->
          path = config_value(config, "path") || "/data"
          {"VOLUME #{path}", 0, 10, true, "volume:#{path}",
           ["volume mounts bypass image layer isolation"]}

        "security_gate" ->
          tool = config_value(config, "tool") || "trivy"
          {"# SECURITY GATE: #{tool} scan", 0, 8_000, false, "gate:#{tool}",
           ["security gate adds ~8s build time but catches vulnerabilities before push"]}

        "push" ->
          registry = config_value(config, "registry") || config_value(config, "target") || ""
          tag = config_value(config, "tag") || "latest"
          {"# PUSH #{registry}:#{tag}", 0, 5_000, false, "push:#{registry}",
           push_security_notes(registry, tag)}

        _ ->
          {"# UNKNOWN: #{node_type}", 0, 100, false, "unknown:#{node_type}", []}
      end

    %{
      node_id: node_id,
      node_type: node_type,
      instruction: instruction,
      estimated_size: size,
      estimated_time_ms: time_ms,
      cacheable: cacheable,
      cache_key: cache_key,
      security_notes: security_notes,
      layer_index: layer_index
    }
  end

  # ---------------------------------------------------------------------------
  # Size and time estimation for RUN commands
  # ---------------------------------------------------------------------------

  defp estimate_run_impact(commands) do
    Enum.reduce(commands, {0, 0}, fn cmd, {total_size, total_time} ->
      cmd_str = to_string(cmd)

      {size, time} =
        cond do
          # Package installation
          String.contains?(cmd_str, "apk add") ->
            pkg_count = count_packages(cmd_str, "apk add")
            {pkg_count * 5_000_000, pkg_count * @pkg_install_time_ms}

          String.contains?(cmd_str, "apt-get install") ->
            pkg_count = count_packages(cmd_str, "apt-get install")
            {pkg_count * 12_000_000, pkg_count * @pkg_install_time_ms * 2}

          String.contains?(cmd_str, "dnf install") or String.contains?(cmd_str, "yum install") ->
            pkg_count = count_packages(cmd_str, "install")
            {pkg_count * 15_000_000, pkg_count * @pkg_install_time_ms * 2}

          # Language package managers
          String.contains?(cmd_str, "npm ci") or String.contains?(cmd_str, "npm install") ->
            {120_000_000, 25_000}

          String.contains?(cmd_str, "yarn install") ->
            {110_000_000, 22_000}

          String.contains?(cmd_str, "pip install") ->
            {60_000_000, 18_000}

          String.contains?(cmd_str, "cargo build") ->
            {250_000_000, 120_000}

          String.contains?(cmd_str, "go build") ->
            {80_000_000, 30_000}

          String.contains?(cmd_str, "mix deps.get") ->
            {40_000_000, 15_000}

          String.contains?(cmd_str, "mix release") ->
            {30_000_000, 45_000}

          String.contains?(cmd_str, "deno cache") or String.contains?(cmd_str, "deno install") ->
            {25_000_000, 8_000}

          # Compilation
          String.contains?(cmd_str, "make") or String.contains?(cmd_str, "cmake") ->
            {50_000_000, @compile_time_ms}

          String.contains?(cmd_str, "gcc") or String.contains?(cmd_str, "g++") ->
            {30_000_000, @compile_time_ms}

          # Cleanup commands (reduce size)
          String.contains?(cmd_str, "rm -rf") or String.contains?(cmd_str, "apk del") ->
            {-10_000_000, 1_000}

          String.contains?(cmd_str, "apt-get clean") or String.contains?(cmd_str, "apt-get purge") ->
            {-20_000_000, 2_000}

          # Default: small overhead
          true ->
            {1_000_000, 500}
        end

      {max(0, total_size + size), total_time + time}
    end)
  end

  defp count_packages(cmd_str, prefix) do
    case String.split(cmd_str, prefix, parts: 2) do
      [_, rest] ->
        rest
        |> String.split()
        |> Enum.reject(fn s -> String.starts_with?(s, "-") or s == "" end)
        |> length()
        |> max(1)

      _ ->
        1
    end
  end

  defp dynamic_command?(cmd) do
    cmd_str = to_string(cmd)

    String.contains?(cmd_str, "$(") or
      String.contains?(cmd_str, "`") or
      String.contains?(cmd_str, "$RANDOM") or
      String.contains?(cmd_str, "date") or
      String.contains?(cmd_str, "curl") or
      String.contains?(cmd_str, "wget")
  end

  # ---------------------------------------------------------------------------
  # Copy size estimation
  # ---------------------------------------------------------------------------

  defp estimate_copy_size(src) do
    src_str = to_string(src)

    cond do
      # Package manifest files are small
      src_str in ~w(package.json package-lock.json yarn.lock Gemfile Gemfile.lock
                     requirements.txt Pipfile.lock go.mod go.sum Cargo.toml Cargo.lock
                     mix.exs mix.lock gleam.toml rescript.json bsconfig.json) ->
        50_000

      # Whole directory copies
      String.ends_with?(src_str, "/") or src_str == "." ->
        20_000_000

      # Single file
      true ->
        2_000_000
    end
  end

  # ---------------------------------------------------------------------------
  # Security analysis per node type
  # ---------------------------------------------------------------------------

  defp source_security_notes(image) do
    notes = []
    image_str = to_string(image)

    notes =
      if String.ends_with?(image_str, ":latest") do
        ["using :latest tag — unpinned base image, builds are not reproducible" | notes]
      else
        notes
      end

    notes =
      if String.contains?(image_str, "cgr.dev/chainguard") do
        ["Chainguard image — minimal attack surface, signed, SBOM available" | notes]
      else
        notes
      end

    notes =
      if not String.contains?(image_str, ":") or String.ends_with?(image_str, ":latest") do
        ["pin image to a specific digest for supply chain integrity" | notes]
      else
        notes
      end

    notes =
      if image_str in ["ubuntu", "debian", "fedora", "centos"] do
        ["full distro image — consider using a minimal image like Chainguard or Alpine" | notes]
      else
        notes
      end

    notes
  end

  defp run_security_notes(commands) do
    Enum.flat_map(commands, fn cmd ->
      cmd_str = to_string(cmd)
      notes = []

      notes =
        if String.contains?(cmd_str, "curl") or String.contains?(cmd_str, "wget") do
          ["downloading from network during build — verify checksums" | notes]
        else
          notes
        end

      notes =
        if String.contains?(cmd_str, "chmod 777") do
          ["chmod 777 grants world-writable permissions — security risk" | notes]
        else
          notes
        end

      notes =
        if String.contains?(cmd_str, "sudo") do
          ["sudo in container build — consider if root is necessary" | notes]
        else
          notes
        end

      notes =
        if String.contains?(cmd_str, "pip install") and not String.contains?(cmd_str, "--no-cache-dir") do
          ["pip install without --no-cache-dir leaves cache in layer" | notes]
        else
          notes
        end

      notes =
        if String.contains?(cmd_str, "npm install") and not String.contains?(cmd_str, "ci") do
          ["prefer 'npm ci' over 'npm install' for reproducible builds" | notes]
        else
          notes
        end

      notes
    end)
  end

  defp copy_security_notes(src) do
    src_str = to_string(src)

    cond do
      src_str == "." ->
        ["COPY . copies everything — use .containerignore to exclude secrets and build artifacts"]

      String.contains?(src_str, ".env") ->
        ["CRITICAL: copying .env file into image leaks secrets"]

      String.contains?(src_str, "id_rsa") or String.contains?(src_str, ".ssh") ->
        ["CRITICAL: copying SSH keys into image layer — they persist even if deleted later"]

      true ->
        []
    end
  end

  defp env_security_notes(key, value) do
    key_str = to_string(key) |> String.upcase()
    value_str = to_string(value)

    notes = []

    notes =
      if key_str in ["PASSWORD", "SECRET", "API_KEY", "TOKEN", "PRIVATE_KEY", "AWS_SECRET_ACCESS_KEY"] do
        ["CRITICAL: secret '#{key}' baked into image layer — use runtime secrets instead" | notes]
      else
        notes
      end

    notes =
      if String.length(value_str) > 100 do
        ["large ENV value — consider using a config file instead" | notes]
      else
        notes
      end

    notes
  end

  defp expose_security_notes(port) do
    port_num = if is_integer(port), do: port, else: String.to_integer(to_string(port))

    cond do
      port_num < 1024 ->
        ["privileged port #{port_num} — container may need elevated privileges"]

      port_num in [22, 23, 3389] ->
        ["EXPOSE #{port_num} — remote access port should not be exposed in production containers"]

      port_num in [3306, 5432, 27017, 6379] ->
        ["database port #{port_num} — ensure it is not exposed to the public network"]

      true ->
        []
    end
  rescue
    _ -> []
  end

  defp workdir_security_notes(path) do
    path_str = to_string(path)

    cond do
      path_str == "/" ->
        ["WORKDIR / — running in root directory, use a subdirectory"]

      path_str == "/root" ->
        ["WORKDIR /root — implies running as root user"]

      true ->
        []
    end
  end

  defp push_security_notes(registry, tag) do
    reg_str = to_string(registry)
    tag_str = to_string(tag)

    notes = []

    notes =
      if tag_str == "latest" do
        ["pushing with :latest tag — use semantic versioning for traceability" | notes]
      else
        notes
      end

    notes =
      if String.contains?(reg_str, "docker.io") do
        ["Docker Hub — consider using a private registry or ghcr.io" | notes]
      else
        notes
      end

    notes =
      if not String.contains?(reg_str, "ghcr.io") and not String.contains?(reg_str, "cgr.dev") do
        ["verify registry '#{reg_str}' supports image signing" | notes]
      else
        notes
      end

    notes
  end

  # ---------------------------------------------------------------------------
  # Build timeline computation
  # ---------------------------------------------------------------------------

  defp compute_timeline(sorted_ids, connections, node_index, layers) do
    case PipelineEngine.execution_plan(%{"nodes" => Map.values(node_index), "connections" => connections}) do
      {:ok, stages} ->
        layer_index = Map.new(layers, fn l -> {l.node_id, l} end)

        Enum.map(stages, fn %{stage: stage_num, nodes: node_ids} ->
          stage_layers =
            node_ids
            |> Enum.map(fn id -> Map.get(layer_index, id) end)
            |> Enum.reject(&is_nil/1)

          # Parallel stages: time is the max of the parallel steps
          max_time =
            stage_layers
            |> Enum.map(& &1.estimated_time_ms)
            |> Enum.max(fn -> 0 end)

          %{
            stage: stage_num,
            node_ids: node_ids,
            parallel: length(node_ids) > 1,
            estimated_time_ms: max_time
          }
        end)

      {:error, _} ->
        # Fallback: sequential timeline
        sorted_ids
        |> Enum.with_index(1)
        |> Enum.map(fn {id, idx} ->
          layer = Enum.find(layers, fn l -> l.node_id == id end)
          time = if layer, do: layer.estimated_time_ms, else: 100

          %{
            stage: idx,
            node_ids: [id],
            parallel: false,
            estimated_time_ms: time
          }
        end)
    end
  end

  # ---------------------------------------------------------------------------
  # Supply chain extraction
  # ---------------------------------------------------------------------------

  defp extract_supply_chain(nodes) do
    nodes
    |> Enum.filter(fn n -> node_type(n) == "source" end)
    |> Enum.map(fn node ->
      image = config_value(node_config(node), "image") || "unknown"
      image_str = to_string(image)

      registry =
        cond do
          String.starts_with?(image_str, "cgr.dev/") -> "cgr.dev"
          String.starts_with?(image_str, "ghcr.io/") -> "ghcr.io"
          String.starts_with?(image_str, "docker.io/") -> "docker.io"
          String.contains?(image_str, "/") -> image_str |> String.split("/") |> List.first()
          true -> "docker.io"
        end

      chainguard = String.contains?(image_str, "cgr.dev/chainguard")

      trust_level =
        cond do
          chainguard -> :high
          registry in ["ghcr.io", "gcr.io", "quay.io"] -> :medium
          registry == "docker.io" -> :low
          true -> :unknown
        end

      %{
        image: image_str,
        registry: registry,
        trust_level: trust_level,
        signed: chainguard,
        sbom_available: chainguard,
        chainguard: chainguard
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Build-level security analysis
  # ---------------------------------------------------------------------------

  defp analyze_build_security(layers, supply_chain, nodes) do
    findings = []

    # Check for secrets in ENV layers
    env_secret_findings =
      layers
      |> Enum.filter(fn l -> l.node_type == "env" end)
      |> Enum.flat_map(fn l ->
        l.security_notes
        |> Enum.filter(&String.starts_with?(&1, "CRITICAL"))
        |> Enum.map(fn note ->
          %{severity: "critical", layer: l.node_id, message: note,
            recommendation: "Use runtime environment variables or a secrets manager"}
        end)
      end)

    # Check for unpinned base images
    unpinned_findings =
      supply_chain
      |> Enum.filter(fn sc -> String.ends_with?(sc.image, ":latest") or not String.contains?(sc.image, ":") end)
      |> Enum.map(fn sc ->
        %{severity: "high", layer: "source", message: "base image '#{sc.image}' is not pinned to a specific version",
          recommendation: "Pin to a digest: #{sc.image}@sha256:..."}
      end)

    # Check for untrusted registries
    untrusted_findings =
      supply_chain
      |> Enum.filter(fn sc -> sc.trust_level in [:low, :unknown] end)
      |> Enum.map(fn sc ->
        %{severity: "medium", layer: "source", message: "image '#{sc.image}' from #{sc.trust_level}-trust registry '#{sc.registry}'",
          recommendation: "Consider using Chainguard images (cgr.dev/chainguard/) for minimal attack surface"}
      end)

    # Check for missing security gates
    has_gate = Enum.any?(nodes, fn n -> node_type(n) == "security_gate" end)
    has_push = Enum.any?(nodes, fn n -> node_type(n) == "push" end)

    gate_findings =
      if has_push and not has_gate do
        [%{severity: "high", layer: "pipeline", message: "no security gate before push — images ship without vulnerability scanning",
           recommendation: "Add a security_gate node (trivy, grype, or snyk) before push nodes"}]
      else
        []
      end

    # Check for large layers (>200MB)
    large_layer_findings =
      layers
      |> Enum.filter(fn l -> l.estimated_size > 200_000_000 end)
      |> Enum.map(fn l ->
        size_mb = Float.round(l.estimated_size / 1_000_000, 1)
        %{severity: "info", layer: l.node_id, message: "layer '#{l.instruction}' estimated at #{size_mb}MB",
          recommendation: "Consider multi-stage build to reduce final image size"}
      end)

    findings ++ env_secret_findings ++ unpinned_findings ++ untrusted_findings ++ gate_findings ++ large_layer_findings
  end

  defp compute_build_security_score(supply_chain, security_findings, nodes) do
    base = 70.0

    # Bonus for Chainguard images
    chainguard_count = Enum.count(supply_chain, & &1.chainguard)
    total_images = max(length(supply_chain), 1)
    chainguard_bonus = 15.0 * (chainguard_count / total_images)

    # Bonus for security gate
    gate_bonus = if Enum.any?(nodes, fn n -> node_type(n) == "security_gate" end), do: 10.0, else: 0.0

    # Penalty per critical/high finding
    critical_count = Enum.count(security_findings, fn f -> f.severity == "critical" end)
    high_count = Enum.count(security_findings, fn f -> f.severity == "high" end)
    penalty = critical_count * 20.0 + high_count * 10.0

    score = base + chainguard_bonus + gate_bonus - penalty
    Float.round(max(0.0, min(100.0, score)), 1)
  end

  # ---------------------------------------------------------------------------
  # Optimisation hints
  # ---------------------------------------------------------------------------

  defp generate_optimisation_hints(layers, supply_chain, _nodes) do
    hints = []

    # Hint: merge consecutive RUN layers
    run_layers = Enum.filter(layers, fn l -> l.node_type == "run" end)

    hints =
      if length(run_layers) > 3 do
        ["merge #{length(run_layers)} RUN layers into fewer layers to reduce image size and build cache misses" | hints]
      else
        hints
      end

    # Hint: copy package manifests before source code
    copy_layers = Enum.filter(layers, fn l -> l.node_type == "copy" end)
    first_copy = List.first(copy_layers)

    hints =
      if first_copy != nil and String.contains?(first_copy.instruction, "COPY .") do
        ["copy package manifest files (package.json, Cargo.toml, etc.) before full source for better cache utilisation" | hints]
      else
        hints
      end

    # Hint: use multi-stage builds for compiled languages
    has_compile =
      Enum.any?(layers, fn l ->
        String.contains?(l.instruction, "cargo build") or
          String.contains?(l.instruction, "go build") or
          String.contains?(l.instruction, "make build") or
          String.contains?(l.instruction, "mix release")
      end)

    source_count = Enum.count(layers, fn l -> l.node_type == "source" end)

    hints =
      if has_compile and source_count < 2 do
        ["consider a multi-stage build: compile in a builder stage, copy binary to a minimal runtime image" | hints]
      else
        hints
      end

    # Hint: use Chainguard images
    non_chainguard = Enum.reject(supply_chain, & &1.chainguard)

    hints =
      if length(non_chainguard) > 0 do
        images = Enum.map(non_chainguard, & &1.image) |> Enum.join(", ")
        ["replace #{images} with Chainguard equivalents for smaller images and built-in SBOMs" | hints]
      else
        hints
      end

    Enum.reverse(hints)
  end

  # ---------------------------------------------------------------------------
  # Containerfile preview generation
  # ---------------------------------------------------------------------------

  defp generate_containerfile_preview(layers, _node_index, _sorted_ids) do
    layers
    |> Enum.reject(fn l -> String.starts_with?(l.instruction, "# PUSH") end)
    |> Enum.map(fn l ->
      comment =
        if l.security_notes != [] do
          notes = Enum.map_join(l.security_notes, "\n# WARNING: ", & &1)
          "# WARNING: #{notes}\n"
        else
          ""
        end

      size_comment =
        if l.estimated_size > 0 do
          size_mb = Float.round(l.estimated_size / 1_000_000, 1)
          " # ~#{size_mb}MB"
        else
          ""
        end

      "#{comment}#{l.instruction}#{size_comment}"
    end)
    |> Enum.join("\n")
  end

  # ---------------------------------------------------------------------------
  # Base image size lookup
  # ---------------------------------------------------------------------------

  defp lookup_base_image_size(image) do
    image_str = to_string(image)
    image_base = image_str |> String.split(":") |> List.first() |> to_string()

    Enum.find_value(@base_image_sizes, 50_000_000, fn {pattern, size} ->
      if String.contains?(image_base, pattern), do: size, else: nil
    end)
  end

  # ---------------------------------------------------------------------------
  # Node accessors (handle both atom and string keys)
  # ---------------------------------------------------------------------------

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

  defp config_value(config, key) when is_map(config) do
    Map.get(config, key, Map.get(config, String.to_existing_atom(key), nil))
  end

  defp config_value(_, _), do: nil

  defp index_nodes(nodes) do
    Map.new(nodes, fn n -> {node_id(n), n} end)
  end

  defp get_commands(config) do
    cmds = config_value(config, "commands") || config_value(config, "command") || []
    if is_list(cmds), do: cmds, else: [cmds]
  end
end
