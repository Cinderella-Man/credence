defmodule Mix.Tasks.Credence.Gen.Rule do
  @shortdoc "Scaffold a new Credence rule and its (intentionally red) test files"

  @moduledoc """
  Generate a correctly-shaped rule plus its test files for a type.

      mix credence.gen.rule <Name> [--type pattern|syntax|semantic]

  `<Name>` may be `NoFooBar` or `no_foo_bar`. `--type` defaults to `pattern`.

  The generated tests are **intentionally red**: they carry real assertions that
  fail against the empty stub, so `mix test` shows you exactly what to fill in,
  while every structural meta gate (naming, positive+negative, whole-string fix,
  heredoc fixtures, …) already passes. No registration step — rules are
  auto-discovered by their `@behaviour`.

  If any target file already exists, the task writes nothing and aborts.
  """

  use Mix.Task

  alias Credence.RuleScaffold

  @types %{"pattern" => :pattern, "syntax" => :syntax, "semantic" => :semantic}

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: [type: :string])

    name = name!(args)
    type = type!(opts[:type] || "pattern")

    files = RuleScaffold.files(name, type)
    paths = Enum.map(files, &elem(&1, 0))

    abort_on_collision!(paths)

    Enum.each(files, fn {path, content} ->
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end)

    Mix.Task.run("format", paths)

    Mix.shell().info("""
    * created #{Enum.join(paths, "\n* created ")}

    The generated tests are intentionally RED until you fill them in (honest red).
    Run `mix test` to see exactly which assertions need real cases.
    """)
  end

  defp name!([name]), do: name

  defp name!(_),
    do: Mix.raise("Expected exactly one rule name, e.g. `mix credence.gen.rule NoFooBar`")

  defp type!(type) do
    Map.get(@types, type) ||
      Mix.raise("Invalid --type #{inspect(type)} (expected pattern, syntax, or semantic)")
  end

  defp abort_on_collision!(paths) do
    case Enum.filter(paths, &File.exists?/1) do
      [] ->
        :ok

      existing ->
        Mix.raise(
          "Refusing to overwrite existing file(s) — nothing written:\n  " <>
            Enum.join(existing, "\n  ")
        )
    end
  end
end
