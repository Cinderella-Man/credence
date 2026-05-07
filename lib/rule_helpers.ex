defmodule Credence.RuleHelpers do
  @moduledoc """
  Shared utilities used by all three Credence phases (Syntax, Semantic, Pattern).

  Provides rule discovery, diff computation, and change logging so the
  phase modules don't duplicate this plumbing.
  """

  require Logger

  # ── Rule discovery ───────────────────────────────────────────────

  @doc """
  Returns all modules implementing `behaviour`, sorted by priority
  (lower first) with module name as tiebreaker for determinism.

      iex> Credence.RuleHelpers.discover_rules(Credence.Pattern.Rule)
      [Credence.Pattern.SomeRule, ...]
  """
  @spec discover_rules(module()) :: [module()]
  def discover_rules(behaviour) do
    Application.spec(:credence, :modules)
    |> Enum.filter(&implements?(&1, behaviour))
    |> Enum.sort_by(&{&1.priority(), &1})
  end

  @doc """
  Returns `true` if `module` declares `behaviour` in its `@behaviour` attribute.
  """
  @spec implements?(module(), module()) :: boolean()
  def implements?(module, behaviour) do
    behaviour in Keyword.get(module.__info__(:attributes), :behaviour, [])
  end

  # ── Rule naming ──────────────────────────────────────────────────

  @doc """
  Returns the short name of a rule module for logging.

      iex> Credence.RuleHelpers.rule_name(Credence.Pattern.NoSortThenAt)
      "NoSortThenAt"
  """
  @spec rule_name(module()) :: String.t()
  def rule_name(module) do
    module |> Module.split() |> List.last()
  end

  # ── Diff ─────────────────────────────────────────────────────────

  @doc """
  Computes a line-by-line diff between two strings.

  Returns a list of `{:removed, line_no, text}` and `{:added, line_no, text}`
  tuples for every line that changed.
  """
  @spec diff_lines(String.t(), String.t()) :: [
          {:removed, pos_integer(), String.t()} | {:added, pos_integer(), String.t()}
        ]
  def diff_lines(before, after_fix) do
    before_lines = String.split(before, "\n")
    after_lines = String.split(after_fix, "\n")
    max_len = max(length(before_lines), length(after_lines))

    Enum.flat_map(0..(max_len - 1), fn i ->
      b = Enum.at(before_lines, i)
      a = Enum.at(after_lines, i)

      cond do
        b == a -> []
        is_nil(a) -> [{:removed, i + 1, b}]
        is_nil(b) -> [{:added, i + 1, a}]
        true -> [{:removed, i + 1, b}, {:added, i + 1, a}]
      end
    end)
  end

  @doc """
  Logs a before/after diff under a `[credence_fix]` prefix.

  Shows up to 10 changed lines; appends a count of remaining changes
  if the diff is larger.
  """
  @spec log_diff(String.t(), String.t(), String.t()) :: :ok
  def log_diff(label, before, after_fix) do
    changes = diff_lines(before, after_fix)
    shown = Enum.take(changes, 10)

    change_summary =
      Enum.map_join(shown, "\n", fn
        {:removed, line_no, text} -> "  L#{line_no} - #{String.trim(text)}"
        {:added, line_no, text} -> "  L#{line_no} + #{String.trim(text)}"
      end)

    remaining = length(changes) - length(shown)

    more =
      if remaining > 0,
        do: "\n  ... (#{remaining} more changes)",
        else: ""

    Logger.debug("[credence_fix] #{label}: source CHANGED:\n#{change_summary}#{more}")
  end
end
