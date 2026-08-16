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

  Prints **`COVERED`** iff:

    * `fix.code != input`  — an existing rule actually **rewrote** the snippet, OR
    * the snippet **COMPILES** and `analyze.issues` has a **non-parse-error**
      issue (a real check flagged an idiom in valid code).

  else **`NOVEL`**.

  🔴 Two traps this avoids — both produced false duplicates that silently dropped
  genuinely-novel rules (tunex docs/10):

    * The synthetic `:parse_error` issue is filtered: `Pattern.analyze` emits it
      for *any* non-parsing input, so a naive `issues != []` would read COVERED
      on every novel **syntax** snippet and kill all new-syntax-rule creation.
    * "A rule fired" must mean a rule **changed** the code, NOT merely matched. A
      non-compiling / incomplete `before` (e.g. one that calls a helper it forgot
      to include) makes a *brokenness* rule like `UndefinedFunction` or the
      defmodule-wrapper family **match without changing anything**, and its
      compile-error diagnostics surface as `analyze.issues`. That is the snippet
      being *broken*, not the proposed idiom being *covered*. So `applied_rules`
      (which counts no-op matches) is **not** used, and `analyze.issues` only
      counts when the snippet actually compiles.

  Still accepts non-parsing input (syntax-rule novelty) and names no rule.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    Mix.shell().info(verdict(read_source(argv)))
  end

  @doc "COVERED | NOVEL for `input` (the decision the task prints; exposed for tests)."
  @spec verdict(String.t()) :: String.t()
  def verdict(input) do
    fix = Credence.fix(input, analyze_after: false)
    %{issues: issues} = Credence.analyze(input)

    real_issue? = Enum.any?(issues, &(&1.rule != :parse_error))

    if fix.code != input or (Credence.RuleHelpers.compiles?(input) and real_issue?) do
      "COVERED"
    else
      "NOVEL"
    end
  end

  defp read_source([]), do: IO.read(:stdio, :eof) |> to_string()
  defp read_source([path | _]), do: File.read!(path)
end
