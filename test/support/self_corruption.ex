defmodule Credence.SelfCorruption do
  @moduledoc """
  The self-corruption oracle: feed every Syntax rule's `fix/1` its **own source
  file** and report which lines came back changed.

  ## Why a rule's own source is the right input

  A line-based Syntax rule matches a regex against source text. To be correct it
  needs a notion of where code stops and prose begins; to *look* correct it needs
  only fixtures that never mention its operator outside code. Every fixture in
  this repo is written by the same person who wrote the rule, so the two agree by
  construction — which is the shape docs/17 calls "the rule agrees with itself
  and ships dead", here in its opposite form: the rule agrees with itself and
  ships destructive.

  A rule's own source file is the one input nobody wrote to make it pass, and it
  is adversarial for free. A rule's moduledoc is *required* by the Rule Standard
  to contain `## Bad` and `## Good` examples — that is, the exact byte sequences
  the rule rewrites — sitting inside a heredoc, next to prose that names the
  operator in English, next to `#` comments explaining the pattern. A rule that
  rewrites its own documentation cannot tell code from prose. No fixture has to
  be authored, and the corpus cannot supply this: real-world Elixir does not
  document Python operators.

  This found `FixDivRem` masking one line at a time (whole-file state cannot be
  reconstructed from a single line) after that rule had already been reviewed,
  converted, changelogged and shipped as fixed.

  ## What a hit does and does not mean

  A hit means the rule rewrote a byte inside a string literal, a sigil, a
  charlist, a heredoc body or a comment — not code. That is always a defect: the
  output parses and compiles, so no downstream gate sees it, and the program
  simply does something its author did not write. It is the 4.6a "blast radius"
  family (docs/16 §3).

  A **clean** result is much weaker. It says only that this rule's own file does
  not happen to trip it. `Credence.SourceMask` is the actual repair; passing here
  is not evidence of masking.

  ## Scope: Syntax only, on purpose

  Only Syntax rules take `fix/1` over raw source. Pattern rules build patches
  from `Sourceror.get_range/1`, so a literal is a node with a range and there is
  nothing to confuse. Semantic rules take `fix/2` with a diagnostic, so there is
  no self-application to make. Line-based regex rewriting is a Syntax-phase
  practice, and this is a Syntax-phase oracle.
  """

  alias Credence.RuleName

  @type hit :: %{
          rule: module(),
          name: String.t(),
          path: String.t(),
          corrupted: non_neg_integer(),
          diff: [{pos_integer(), String.t(), String.t()}]
        }

  @doc """
  Runs every rule in `rules` (default: every live Syntax rule) over its own
  source file, returning one entry per rule with the number of lines the fix
  changed. A rule whose file it cannot read, or whose `fix/1` raises, is
  reported rather than skipped — either would otherwise read as clean.
  """
  @spec scan([module()]) :: [hit()]
  def scan(rules \\ Credence.Syntax.default_rules()) do
    Enum.map(rules, &scan_one/1)
  end

  @doc "The names of the rules in `entries` that rewrote their own source."
  @spec corrupting([hit()]) :: [String.t()]
  def corrupting(entries) do
    for e <- entries, e.corrupted > 0, do: e.name
  end

  @doc """
  A `%{name => line_count}` map of the rules that rewrote their own source, for
  comparison against a frozen ledger.
  """
  @spec counts([hit()]) :: %{String.t() => pos_integer()}
  def counts(entries) do
    for e <- entries, e.corrupted > 0, into: %{}, do: {e.name, e.corrupted}
  end

  @doc """
  The number of lines `rule`'s `fix/1` changes in `source`.

  `scan/1` is exactly this, over each rule's own file. It is exposed separately so
  the gate can *positively control the detection itself*: with the ledger empty,
  "no rule corrupts its own source" and "the differ stopped working" look
  identical from the outside, and only one of them is good news. Hand this a rule
  that is guaranteed to rewrite whatever it is given and the oracle has to say so.
  """
  @spec corrupted_lines(module(), String.t()) :: non_neg_integer()
  def corrupted_lines(rule, source) do
    case apply_fix(rule, source) do
      {:ok, fixed} -> length(diff(source, fixed))
      {:error, _reason} -> 1
    end
  end

  @doc "A human-readable rendering of one entry's first `max` changed lines."
  @spec render(hit(), pos_integer()) :: String.t()
  def render(%{name: name, corrupted: n, diff: diff}, max \\ 3) do
    shown =
      diff
      |> Enum.take(max)
      |> Enum.map_join("\n", fn {ln, before, aft} ->
        "      :#{ln}  - #{clip(before)}\n           + #{clip(aft)}"
      end)

    rest = if n > max, do: "\n      … #{n - max} more line(s)", else: ""

    "    #{name} — #{n} line(s) of its own source\n#{shown}#{rest}"
  end

  defp scan_one(rule) do
    %{snake: name, rule_path: path} = RuleName.from_module(rule)

    with {:ok, source} <- File.read(path),
         {:ok, fixed} <- apply_fix(rule, source) do
      %{
        rule: rule,
        name: name,
        path: path,
        corrupted: length(diff(source, fixed)),
        diff: diff(source, fixed)
      }
    else
      # A rule whose file cannot be read or whose fix raises is a hit, not a
      # skip. Both would otherwise be indistinguishable from "clean" and the
      # gate would go quiet exactly where something is wrong.
      {:error, reason} ->
        %{rule: rule, name: name, path: path, corrupted: 1, diff: [{0, path, inspect(reason)}]}
    end
  end

  defp apply_fix(rule, source) do
    {:ok, rule.fix(source)}
  rescue
    e -> {:error, e}
  end

  defp diff(source, fixed) do
    Enum.zip(String.split(source, "\n"), String.split(fixed, "\n"))
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{a, b}, ln} -> if a == b, do: [], else: [{ln, a, b}] end)
  end

  defp clip(line), do: line |> String.trim() |> String.slice(0, 96)
end
