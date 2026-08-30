defmodule Credence.DispatchContention do
  @moduledoc """
  Which live Semantic rules claim the same captured diagnostic — the G3 residue
  the pipeline-witness gate (T1) does not cover.

  T1 proves each rule *can* win its slot with its own fixture. It cannot see the
  case where two rules both accept the same diagnostic: `lib/semantic.ex`
  dispatches with `Enum.find` over `discover_rules/1`'s ordering, so the second
  claimant does not run at all. docs/20 §2 is the rule this exists to enforce —
  **alphabetical order may not be load-bearing** — because
  `Enum.sort_by(&{&1.priority(), &1})` falls back to the module atom, and 275 of
  290 rules sit at the default 500. A rename reorders dispatch silently, and in
  Semantic reordering does not delay a rule, it disables one.

  Every function takes its rule list as an argument rather than reading
  `default_rules/0`, so the gate's own machinery can be exercised against
  fabricated rules. A gate that can only be run against the live set is one
  nobody can prove still works once the live set is clean.
  """

  alias Credence.PipelineWitness
  alias Credence.RuleHelpers

  # `compile_and_capture/1` synthesizes this when it refuses to finish a compile
  # (see `RuleHelpers`). It is credence talking about itself, not a compiler
  # diagnostic about the source, so it must never be offered to a rule's
  # `match?/1` — and it exists precisely because one witness candidate does not
  # terminate.
  @self_reported "credence: compilation aborted"

  @doc """
  Every distinct diagnostic that `rules`' own witness fixtures actually produce.

  Distinct by severity and message: the same defect in twenty fixtures is one
  dispatch question, and the module name embedded in a diagnostic would
  otherwise make twenty of them. Severity remains part of the question because
  rules may accept only warnings or only errors.
  """
  @spec captured_diagnostics([module()]) :: [map()]
  def captured_diagnostics(rules) do
    rules
    |> Enum.flat_map(fn rule ->
      rule
      |> PipelineWitness.candidates()
      |> Enum.flat_map(&diagnostics_of/1)
    end)
    |> Enum.reject(&String.starts_with?(&1.message, @self_reported))
    |> Enum.uniq_by(&{&1.severity, &1.message})
  end

  defp diagnostics_of(source) do
    case RuleHelpers.compile_and_capture(source) do
      {:ok, diagnostics} -> Enum.filter(diagnostics, &(&1.severity in [:warning, :error]))
      {:error, diagnostics} -> Enum.filter(diagnostics, &(&1.severity == :error))
    end
  end

  @doc """
  `[{diagnostic, claimers}]` for every diagnostic more than one rule claims,
  claimers in dispatch order — so `hd/1` is the rule that actually runs.
  """
  @spec contentions([module()], [map()]) :: [{map(), [module()]}]
  def contentions(rules, diagnostics) do
    diagnostics
    |> Enum.map(&{&1, claimers(rules, &1)})
    |> Enum.filter(fn {_diagnostic, claimers} -> length(claimers) > 1 end)
  end

  @doc """
  The rules whose `match?/1` accepts `diagnostic`, in dispatch order.

  Exceptions propagate, matching the Semantic dispatcher's predicate calls.
  """
  @spec claimers([module()], map()) :: [module()]
  def claimers(rules, diagnostic) do
    Enum.filter(rules, & &1.match?(diagnostic))
  end

  @doc "Dispatch order for `rules` — the same ordering `discover_rules/1` applies."
  @spec dispatch_order([module()]) :: [module()]
  def dispatch_order(rules), do: Enum.sort_by(rules, &{&1.priority(), &1})
end
