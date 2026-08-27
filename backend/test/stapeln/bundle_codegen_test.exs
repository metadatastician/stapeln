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
