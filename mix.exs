defmodule ExTerm.MixProject do
  use Mix.Project

  @development [:dev, :test]

  def project do
    [
      app: :ex_term,
      version: "0.2.1",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(Mix.env()),
      deps: deps(),
      description: "liveview terminal module",
      package: package(),
      source_url: "https://github.com/E-xyza/ex_term",
      docs: [
        main: "ExTerm",
        extras: ["README.md"],
        filter_modules: fn module, _ -> match?(["ExTerm" | _], Module.split(module)) end
      ]
    ]
  end

  def application do
    application =
      if Mix.env() in @development, do: ExTerm.DevApplication, else: ExTerm.Application

    [
      mod: {application, []},
      extra_applications: [:logger, :runtime_tools, :iex]
    ]
  end

  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(:test), do: ["lib", "dev", "test/_support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    in_dev = Mix.env() in @development

    [
      {:phoenix, "~> 1.7.10"},
      {:phoenix_html, "~> 4.0", override: true},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.4.1", only: :dev},
      {:phoenix_live_view, "~> 0.20"},
      {:phoenix_view, "~> 2.0"},
      {:match_spec, "~> 0.3.1"},
      {:floki, ">= 0.30.0", only: :test},
      {:mox, "~> 1.0", only: :test},
      {:esbuild, "~> 0.4", runtime: Mix.env() == :dev},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5", optional: !in_dev},
      {:mix_test_watch, "~> 1.1", only: :dev, runtime: false},
      {:ex_doc, "> 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases(env) do
    List.wrap(
      if env in @development do
        [
          setup: ["deps.get"],
          "assets.deploy": ["esbuild default --minify", "phx.digest"]
        ]
      end
    )
  end

  defp package do
    [
      # These are the default files included in the package
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/E-xyza/ex_term"}
    ]
  end
end
