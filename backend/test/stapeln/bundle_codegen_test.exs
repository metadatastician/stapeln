# SPDX-License-Identifier: MPL-2.0

defmodule Stapeln.BundleCodegenTest do
  use ExUnit.Case, async: true

  alias Stapeln.BundleCodegen

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
    test "emits exactly the nine bundle files" do
      {:ok, bundle} = BundleCodegen.generate(@sample_stack, @required)

      assert Enum.sort(Map.keys(bundle)) == BundleCodegen.bundle_files()
      assert map_size(bundle) == 9
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
      for name <- BundleCodegen.bundle_files(), name != "stapeln.design.json" do
        path = Path.join(BundleCodegen.template_dir(), name)
        assert File.exists?(path), "missing template: #{path}"
      end
    end
  end
end
