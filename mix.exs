defmodule Credence.MixProject do
  use Mix.Project

  def project do
    [
      app: :credence,
      version: "0.8.1",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # `:mix` carries the Mix.Task behaviour + Mix.{shell,raise}/Mix.Task.run
      # used by the credence.gen.rule task; `:ex_unit` carries ExUnit.start/1 +
      # ExUnit.CaptureIO used by the credence.equiv task. Without them Dialyzer
      # reports those as unknown functions.
      dialyzer: [plt_add_apps: [:mix, :ex_unit]],
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
      {:stream_data, "~> 1.0", only: :test},
      # Test-only, and only so four rules can witness their own failure mode
      # through the real pipeline (T1 / docs/22 T5.9). Each keys on a compiler
      # diagnostic that is only emitted when the library is actually present —
      # without them the rules are alive in the evolution harness workspace and
      # unwitnessable here, which is a property of this checkout, not of the
      # rules. Neither is a runtime dependency of Credence.
      {:plug, "~> 1.16", only: :test, runtime: false},
      {:nimble_csv, "~> 1.2", only: :test, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Cinderella-Man/credence"}
    ]
  end
end
