defmodule Mix.Tasks.Credence.Covers do
  @shortdoc "Does any existing rule already engage on this snippet? (COVERED | NOVEL)"

  @moduledoc """
  Behavioural novelty check (Tunex `07` §3.7): run a snippet through
  `Credence.fix/2` + `Credence.analyze/2` in the **default (helpful)
  `assumptions:` mode** (the same mode solve's Validator runs — never `:strict`,
  else a switch-gated pattern reads NOVEL here but COVERED in solve), and decide
  whether a **real rule already engaged**:

      mix credence.covers path/to/snippet.exs
      echo 'Enum.map(x, & &1)' | mix credence.covers

  Prints **`COVERED`** iff any of:

    * `fix.code != input`            — an existing rule auto-fixed it,
    * `fix.applied_rules != []`      — a rule fired,
    * `analyze.issues` has a **non-parse-error** issue (a check flagged it).

  else **`NOVEL`**.

  🔴 The synthetic `:parse_error` issue is filtered: `Pattern.analyze` emits it
  for *any* non-parsing input, so a naive `issues != []` would read COVERED on
  every novel **syntax** snippet and kill all new-syntax-rule creation. Coverage
  must mean "a real rule engaged", never the bare parse-error pseudo-issue. The
  task therefore accepts **non-parsing** input and names no rule.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    input = read_source(argv)

    fix = Credence.fix(input)
    %{issues: issues} = Credence.analyze(input)

    real_issue? = Enum.any?(issues, &(&1.rule != :parse_error))

    verdict =
      if fix.code != input or fix.applied_rules != [] or real_issue? do
        "COVERED"
      else
        "NOVEL"
      end

    Mix.shell().info(verdict)
  end

  defp read_source([]), do: IO.read(:stdio, :eof) |> to_string()
  defp read_source([path | _]), do: File.read!(path)
end
