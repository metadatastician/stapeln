# SPDX-License-Identifier: MPL-2.0

defmodule Stapeln.BundleCodegenTest do
  use ExUnit.Case, async: true

  alias Stapeln.{BundleCodegen, Parts}

  @sample_stack %{
    name: "acme-platform",
    description: "A platform for testing the bundle compiler.",
    design: %{
      "components" => [
        %{"id" => "c1", "componentType" => "Svalinn", "position" => %{"x" => 10.0, "y" => 20.0}}
      ],
      "connections" => []
    },
    services: [
      %{name: "web", image: "nginx:1.27-alpine", ports: ["8080:80"]},
      %{name: "api", image: "cgr.dev/chainguard/static:latest", ports: ["9000:9000"]}
    ]
  }

  @required [author: "A. Author", email: "a@example.org", license: "MPL-2.0", owner: "acme"]

  describe "generate/2" do
    test "emits exactly the eleven bundle files" do
      {:ok, bundle} = BundleCodegen.generate(@sample_stack, @required)

      assert Enum.sort(Map.keys(bundle)) == BundleCodegen.bundle_files()
      assert map_size(bundle) == 11
    end

    test "no file contains a residual {{TOKEN}}" do
      {:ok, bundle} = BundleCodegen.generate(@sample_stack, @required)

      for {name, content} <- bundle do
        refute content =~ ~r/\{\{[A-Z_]+\}\}/,
               "#{name} still contains an unsubstituted placeholder"
      end
    end

    test "substitutes design-derived tokens from the stack, not from defaults" do
      {:ok, bundle} = BundleCodegen.generate(@sample_stack, @required)
      manifest = bundle["manifest.toml"]

      assert manifest =~ "acme-platform"
      assert manifest =~ "A platform for testing the bundle compiler."
      assert manifest =~ "A. Author"
      assert manifest =~ "MPL-2.0"
      # SERVICE_NAME comes from the FIRST service, not the stack name.
      assert bundle["compose.toml"] =~ "web"
    end

    test "applies documented defaults for the benign tokens" do
      {:ok, bundle} = BundleCodegen.generate(@sample_stack, @required)

      assert bundle["compose.toml"] =~ "ghcr.io"
      assert bundle["manifest.toml"] =~ "github.com"
    end

    test "an explicit registry redirects the APP image but not the satellites" do
      {:ok, bundle} =
        BundleCodegen.generate(@sample_stack, @required ++ [registry: "registry.example.org"])

      compose = bundle["compose.toml"]

      # The app image follows {{REGISTRY}}...
      assert compose =~ "registry.example.org/web:latest.ctp"

      # ...but rokur and svalinn are pinned to ghcr.io in the template on
      # purpose. Where you publish YOUR application has nothing to do with
      # where the hyperpolymath satellites are published, and rewriting those
      # would point the stack at images that do not exist.
      assert compose =~ "ghcr.io/hyperpolymath/rokur"
      assert compose =~ "ghcr.io/hyperpolymath/svalinn"
      refute compose =~ "registry.example.org/hyperpolymath"
    end

    test "stapeln.design.json round-trips the design and names its schema" do
      {:ok, bundle} = BundleCodegen.generate(@sample_stack, @required)

      decoded = Jason.decode!(bundle["stapeln.design.json"])

      assert decoded["schema"] == "stapeln.design/v1"
      assert decoded["name"] == "acme-platform"
      assert decoded["design"] == @sample_stack.design
      assert length(decoded["services"]) == 2
    end
  end

  describe "required options" do
    test "each of the four is genuinely required" do
      for missing <- [:author, :email, :license, :owner] do
        opts = Keyword.delete(@required, missing)

        assert {:error, reason} = BundleCodegen.generate(@sample_stack, opts)
        assert reason =~ to_string(missing)
      end
    end

    test "an empty string counts as absent" do
      # This is how a web form posts a field the user left blank. "author = """
      # in a manifest is no better than "{{AUTHOR}}", so it must not pass.
      opts = Keyword.put(@required, :author, "   ")

      assert {:error, reason} = BundleCodegen.generate(@sample_stack, opts)
      assert reason =~ "author"
    end

    test "the error names every missing option, not just the first" do
      assert {:error, reason} = BundleCodegen.generate(@sample_stack, [])

      for expected <- ~w(author email license owner) do
        assert reason =~ expected
      end
    end
  end

  describe "scanner findings from the #39 review — regression guards" do
    test "CONFIRMED: an unparseable port falls back to 8080, because 0 is TRUTHY" do
      # `service_port(svc) || 8080` was wrong: in Elixir only nil and false are
      # falsy, and service_port/1 returns 0 for a port string it cannot parse.
      # `0 || 8080` is 0, so the bundle emitted APP_PORT = "0".
      stack = %{name: "p", design: nil, services: [%{"name" => "web", "port" => "abc"}]}

      {:ok, bundle} = BundleCodegen.generate(stack, @required)

      assert bundle["compose.toml"] =~ ~s(APP_PORT = "8080")
      refute bundle["compose.toml"] =~ ~s(APP_PORT = "0")
    end

    test "a real port is still used" do
      stack = %{name: "p", design: nil, services: [%{"name" => "web", "port" => "9443"}]}
      {:ok, bundle} = BundleCodegen.generate(stack, @required)

      assert bundle["compose.toml"] =~ ~s(APP_PORT = "9443")
    end

    test "CONFIRMED: metadata carrying a newline is rejected, not injected" do
      # This was TOML INJECTION, not mere corruption: substitution is textual,
      # so a newline in `author` closes the string and the remainder becomes
      # new top-level keys in manifest.toml -- the file cerro-torre reads to
      # attribute a build.
      opts = Keyword.put(@required, :author, "A\nInjected = true")

      assert {:error, reason} = BundleCodegen.generate(@sample_stack, opts)
      assert reason =~ "author"
      assert reason =~ "control"
    end

    test "metadata carrying a quote or backslash is rejected" do
      for {key, bad} <- [author: ~s(A "Q" Author), owner: "a\\b", license: ~s(MP"L)] do
        opts = Keyword.put(@required, key, bad)

        assert {:error, reason} = BundleCodegen.generate(@sample_stack, opts),
               "#{key}=#{inspect(bad)} should have been rejected"

        assert reason =~ to_string(key)
      end
    end

    test "the rejection names every offending option, and ordinary values still pass" do
      opts = @required |> Keyword.put(:author, ~s(a")) |> Keyword.put(:owner, "b\\")

      assert {:error, reason} = BundleCodegen.generate(@sample_stack, opts)
      assert reason =~ "author"
      assert reason =~ "owner"

      # Control: names with spaces, dots, apostrophes and non-ASCII are fine.
      ok = Keyword.put(@required, :author, "Jonathan D.A. Jewell — Ólafsdóttir")
      assert {:ok, _} = BundleCodegen.generate(@sample_stack, ok)
    end
  end

  describe "assert_no_placeholders!/2 — the guard itself" do
    # These are canary tests. The estate has been bitten by a placeholder check
    # that silently verified nothing (the e2e `find -exec` whose $file was unset
    # outside the body, so every grep ran on an empty string and passed). A guard
    # that has never been OBSERVED failing is not a guard, so these assert that
    # it raises rather than that some other thing passes.

    test "raises on a residual token" do
      assert_raise ArgumentError, ~r/\{\{OWNER\}\}/, fn ->
        BundleCodegen.assert_no_placeholders!("owner = \"{{OWNER}}\"\n", "manifest.toml")
      end
    end

    test "the message names the file and every distinct token" do
      err =
        assert_raise ArgumentError, fn ->
          BundleCodegen.assert_no_placeholders!(
            "{{OWNER}} {{REPO}} {{OWNER}}",
            "manifest.toml"
          )
        end

      assert err.message =~ "manifest.toml"
      assert err.message =~ "{{OWNER}}"
      assert err.message =~ "{{REPO}}"
      # 3 occurrences, 2 distinct — the count reports occurrences.
      assert err.message =~ "3 unsubstituted"
    end

    test "passes content through unchanged when clean" do
      clean = "owner = \"acme\"\n"
      assert BundleCodegen.assert_no_placeholders!(clean, "manifest.toml") == clean
    end

    test "does not fire on lookalikes that are not tokens" do
      # Nickel and shell both use braces; the guard must not reject them.
      for benign <- ["{{ not a token }}", "${VAR}", "{ x = 1 }", "{{lowercase}}"] do
        assert BundleCodegen.assert_no_placeholders!(benign, "deploy.k9.ncl") == benign
      end
    end
  end

  describe "templates on disk" do
    test "template_dir resolves under mix test, not just at runtime" do
      assert File.dir?(BundleCodegen.template_dir()),
             "priv/bundle_templates is not reachable via Application.app_dir/2"
    end

    test "every template the module claims to render actually exists" do
      for name <- BundleCodegen.bundle_files() -- BundleCodegen.generated_files() do
        path = Path.join(BundleCodegen.template_dir(), name)
        assert File.exists?(path), "missing template: #{path}"
      end
    end
  end
  # W5/#76. The template this pins replaced one that made rokur REFUSE TO
  # START: it invented `[server] listen`, a `backend` key rokur has never
  # implemented, and rate_limit/policy/audit key names taken from nowhere. The
  # suite was 209 green over that file, because nothing asserted on it -- so
  # these tests pin what stapeln EMITS rather than restating rokur's schema,
  # which is rokur's to own and would simply drift here in a second copy.
  describe "the emitted rokur.toml" do
    defp rokur_toml(opts \\ []) do
      {:ok, bundle} = BundleCodegen.generate(@sample_stack, @required ++ opts)
      bundle["rokur.toml"]
    end

    test "decodes with a real TOML decoder" do
      assert {:ok, _doc} = Toml.decode(rokur_toml())
    end

    test "emits only the three tables stapeln has a source for" do
      doc = Toml.decode!(rokur_toml())

      assert Enum.sort(Map.keys(doc)) == ["metadata", "secrets", "server"]

      assert Enum.sort(Map.keys(doc["server"])) == ["health_path", "host", "port"]
    end

    test "carries no key rokur's parser rejects" do
      doc = Toml.decode!(rokur_toml())

      # Each of these was in the previous template and is independently fatal.
      refute Map.has_key?(doc["server"], "listen")
      refute Map.has_key?(doc["server"], "backend")
      refute Map.has_key?(doc, "rate_limit")
      refute Map.has_key?(doc, "policy")
      refute Map.has_key?(doc, "audit")
    end

    test "takes port and health_path from the part descriptor" do
      doc = Toml.decode!(rokur_toml())
      rokur = Parts.load!()["rokur"]

      assert doc["server"]["port"] == rokur.health.port
      assert doc["server"]["health_path"] == rokur.health.path
    end

    test "follows a descriptor that declares a different port" do
      # The mutant this kills is a template that hardcodes 7658 and passes the
      # test above by coincidence. Move the descriptor; the file must move.
      catalogue = Parts.load!()
      rokur = catalogue["rokur"]
      moved = %{rokur | health: %{rokur.health | port: 7777, path: "/probe"}}

      doc = Toml.decode!(rokur_toml(catalogue: Map.put(catalogue, "rokur", moved)))

      assert doc["server"]["port"] == 7777
      assert doc["server"]["health_path"] == "/probe"
    end

    test "binds 0.0.0.0, because loopback in a container is a half-green" do
      # Bound to 127.0.0.1, the in-image healthcheck passes while every probe
      # through the published port fails: a green container, an unreachable gate.
      assert Toml.decode!(rokur_toml())["server"]["host"] == "0.0.0.0"
    end

    test "declares an empty required-secrets list and says it fails closed" do
      content = rokur_toml()

      assert Toml.decode!(content)["secrets"]["required"] == []

      # The previous template called this "the gate starts open". Rokur exits at
      # startup instead (main.js: fatalConfigurationError). A fail-open claim
      # about a fail-closed gate is the one error here that costs a deployment.
      assert content =~ "FAILS CLOSED"
      assert content =~ "does NOT mean the gate starts open"
      refute content =~ "tighten this before production"
    end

    test "names no banned runtime" do
      content = String.downcase(rokur_toml())

      for banned <- ~w(deno rescript typescript python) do
        refute content =~ banned, "rokur.toml names the banned runtime #{banned}"
      end
    end

    test "publishes no 8080-class port" do
      content = rokur_toml()

      for banned <- ~w(8080 8081 8000 3000) do
        refute content =~ banned, "rokur.toml carries the banned port #{banned}"
      end
    end
  end
end
