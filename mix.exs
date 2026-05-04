defmodule Credence.MixProject do
  use Mix.Project

  def project do
    [
      app: :credence,
      version: "0.2.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "An Elixir semantic linter that detects performance issues and non-idiomatic code via AST analysis.",
      package: package()
    ]
  end

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
      {:sourceror, "~> 1.11"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Cinderella-Man/credence"}
    ]
  end
end
