defmodule Credence.MixProject do
  use Mix.Project

  def project do
    [
      app: :credence,
      version: "0.7.1",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # `:mix` carries the Mix.Task behaviour + Mix.{shell,raise}/Mix.Task.run
      # used by the credence.gen.rule task; without it Dialyzer reports those
      # as unknown functions.
      dialyzer: [plt_add_apps: [:mix]],
      description:
        "An Elixir semantic linter that detects performance issues and non-idiomatic code via AST analysis.",
      package: package()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:sourceror, "~> 1.11"},
      {:stream_data, "~> 1.0", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Cinderella-Man/credence"}
    ]
  end
end
