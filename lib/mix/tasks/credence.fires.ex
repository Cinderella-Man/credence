defmodule Mix.Tasks.Credence.Fires do
  @shortdoc "Does one NAMED rule engage on this snippet? (FIRES | INERT | UNKNOWN)"

  @moduledoc """
  Single-rule reachability probe, for the harness's BUGFIX-lane evidence gate
  (docs/22 T4.2d).

      mix credence.fires Credence.Semantic.UndefinedFunction path/to/before.exs
      mix credence.fires undefined_function path/to/before.exs
      echo 'Enum.count(x)' | mix credence.fires no_enum_count_for_length

  A `BUGFIX_RULE` report accuses one rule of misbehaving on one snippet. If that
  rule does not engage with the snippet at all, the accusation cannot be about
  it, and the row costs a full implementer run to discover that. Three such rows
  in the 2026-07-06 run (escalation ledger 40, 50, 59) were live over-fires the
  harness talked itself out of for want of this check.

  Prints:

    * **`FIRES`** — the rule appears in `Credence.fix/2`'s applied trace under
      *any* outcome, or `Credence.analyze/2` attributes an issue to it. Any
      outcome counts on purpose: `:no_op`, `:reverted`, `:patch_rejected` and
      `:crashed` are all the rule *engaging*, and a crash is the report most
      worth keeping.
    * **`INERT`** — the rule was reachable and did nothing. This is the only
      answer that should fail a row.
    * **`UNKNOWN`** — the question could not be asked: no such rule, or the
      pipeline raised. **Never fail a row on this.** A gate that cannot tell
      must not render "we could not tell" as "refuted" — the inversion
      `Cev.Premise` was written to avoid.

  ## Why not `credence.covers`

  `covers` asks whether *any* rule engaged and deliberately names none, because
  it answers a novelty question. This asks about one named rule, and counts a
  no-op as engagement where `covers` must not — the two would give opposite
  answers on a snippet whose only claimant declines, and both would be right.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {rule_arg, rest} =
      case argv do
        [rule | rest] -> {rule, rest}
        [] -> Mix.raise("usage: mix credence.fires <RuleNameOrSnakeCase> [path]")
      end

    Mix.shell().info(verdict(rule_arg, read_source(rest)))
  end

  @doc "FIRES | INERT | UNKNOWN for `rule_arg` against `input`; exposed for tests."
  @spec verdict(String.t(), String.t()) :: String.t()
  def verdict(rule_arg, input) do
    case resolve(rule_arg) do
      nil -> "UNKNOWN"
      rule -> probe(rule, input)
    end
  end

  defp probe(rule, input) do
    if in_trace?(rule, input) or attributed?(rule, input) or self_reports?(rule, input) do
      "FIRES"
    else
      "INERT"
    end
  rescue
    _ -> "UNKNOWN"
  catch
    _, _ -> "UNKNOWN"
  end

  defp in_trace?(rule, input) do
    Credence.fix(input, analyze_after: false).applied_rules
    |> Enum.any?(fn
      {mod, _outcome} -> mod == rule
      mod -> mod == rule
    end)
  end

  defp attributed?(rule, input) do
    Credence.analyze(input).issues
    |> Enum.any?(&(&1.rule == derived_atom(rule)))
  end

  defp derived_atom(rule) do
    rule
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  # Pattern and Semantic issues carry a module-derived atom, so `attributed?/2`
  # finds them. A **Syntax** rule names its issue whatever its author chose
  # (T3.8), and the Syntax round only runs at all when the source fails to
  # parse — so ask the rule itself rather than trying to guess its atom or
  # relying on a phase that may never have run.
  defp self_reports?(rule, input) do
    function_exported?(rule, :analyze, 1) and rule.analyze(input) != []
  rescue
    _ -> false
  end

  @doc false
  # Accepts a full module name, a bare last segment, or the snake_case file name.
  @spec resolve(String.t()) :: module() | nil
  def resolve(arg) do
    want = arg |> String.trim() |> String.replace_prefix("Elixir.", "")

    Enum.find(all_rules(), fn mod ->
      last = mod |> Module.split() |> List.last()

      inspect(mod) == want or last == want or
        Macro.underscore(last) == Macro.underscore(want)
    end)
  end

  defp all_rules do
    Credence.Pattern.default_rules() ++
      Credence.Semantic.default_rules() ++ Credence.Syntax.default_rules()
  end

  defp read_source([path | _]), do: File.read!(path)
  defp read_source([]), do: IO.read(:stdio, :eof) |> to_string()
end
