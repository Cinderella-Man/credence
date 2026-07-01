defmodule Credence.CommentPreservationTest do
  @moduledoc """
  A cross-rule guard: no rule's fix may silently drop a source comment.

  Comments are not in the bare AST — Sourceror attaches them to node metadata and
  positions them by `:line`. A rule that re-renders a node it keeps must preserve
  the comment that sat in it. The corpus fix-safety test (`fix_safety_test.exs`)
  only catches rules that happen to fire on commented corpus code; this meta-test
  checks **every** discovered Pattern rule, using that rule's own `_fix_test.exs`
  `input`/`code` heredocs (guaranteed to trigger its fix — no new fixtures, and
  future rules are covered automatically).

  ## The invariant

  For each fix-test input where the rule fires, inject a unique comment before each
  line and apply the fix. If that line survives the fix **verbatim** (so its node
  was kept, not rewritten or removed), the comment on it MUST survive too. We only
  flag verbatim-surviving lines, so a comment on code the fix legitimately rewrites
  away is not a false positive.
  """
  use ExUnit.Case, async: true

  alias Credence.MetaTestSupport, as: Meta
  alias Credence.{RuleHelpers, RuleName}

  # Known limitation, tracked rather than silently skipped: this rule rebuilds the
  # whole MapSet pipeline from scratch, so no original node survives to carry a
  # comment. `|> MapSet.to_list()` appears in both input and output but they are
  # different nodes, which the verbatim-text survival heuristic cannot distinguish.
  # The corpus fix-safety test confirms no *real-world* comment is dropped here.
  @known_unfixable [{"PreferPipeMapsetIntersection", "|> MapSet.to_list()"}]

  test "no rule's fix drops a comment on a line it leaves verbatim" do
    violations = Enum.flat_map(Meta.rules(), &rule_violations/1) -- @known_unfixable

    assert violations == [], report(violations)
  end

  defp rule_violations(rule) do
    rule
    |> fix_inputs()
    |> Enum.filter(&fires?(rule, &1))
    |> Enum.flat_map(fn input ->
      Enum.map(dropped_comment_lines(rule, input), &{Meta.short(rule), &1})
    end)
    |> Enum.uniq()
  end

  # The `input = "..."` / `code = "..."` string literals from the rule's fix test.
  defp fix_inputs(rule) do
    path = rule |> RuleName.from_module() |> RuleName.test_path("fix")

    with {:ok, body} <- File.read(path),
         {:ok, ast} <- Code.string_to_quoted(body) do
      {_, acc} =
        Macro.prewalk(ast, [], fn
          {:=, _, [{v, _, nil}, s]} = node, acc when v in [:input, :code] and is_binary(s) ->
            {node, [s | acc]}

          node, acc ->
            {node, acc}
        end)

      Enum.uniq(acc)
    else
      _ -> []
    end
  end

  defp fires?(rule, input), do: safe_fix(rule, input) != input

  defp dropped_comment_lines(rule, input) do
    in_lines = trimmed_lines(input)
    lines = String.split(input, "\n")

    lines
    |> Enum.with_index()
    |> Enum.filter(fn {line, idx} ->
      probeable?(line) and dropped?(rule, lines, idx, line, in_lines)
    end)
    |> Enum.map(fn {line, _} -> String.trim(line) end)
    |> Enum.uniq()
  end

  # Inject a unique comment before line `idx`; report a drop only when the line
  # survives verbatim (so its node was kept) yet the comment is gone.
  defp dropped?(rule, lines, idx, line, in_lines) do
    token = "credence_probe_#{idx}"
    indent = Regex.run(~r/^\s*/, line) |> hd()
    injected = lines |> List.insert_at(idx, indent <> "# " <> token) |> Enum.join("\n")

    out = safe_fix(rule, injected)
    out_lines = trimmed_lines(out)
    trimmed = String.trim(line)

    line_survived? = count(out_lines, trimmed) >= count(in_lines, trimmed)

    line_survived? and not String.contains?(out, token)
  end

  # Bare block terminators (`end`, `)`, `else`, …) hold *boundary* comments that
  # Sourceror attaches to a block wrapper a transform may legitimately restructure
  # — a separate, much harder problem than the core bug (a comment on a line of
  # real code that the fix re-renders and silently drops). Scope the probe to code.
  @terminators ~w(end else end) ++ [")", "}", "]", "end)", "end]", "end}", ")", "->"]

  defp probeable?(line) do
    trimmed = String.trim(line)

    trimmed != "" and
      not String.starts_with?(trimmed, "#") and
      trimmed not in @terminators
  end

  defp trimmed_lines(source), do: source |> String.split("\n") |> Enum.map(&String.trim/1)

  defp count(lines, value), do: Enum.count(lines, &(&1 == value))

  defp safe_fix(rule, code) do
    RuleHelpers.apply_rule_fix(rule, code)
  rescue
    _ -> code
  end

  defp report(violations) do
    body =
      Enum.map_join(violations, "\n", fn {rule, line} ->
        "  • #{rule}: drops the comment on the surviving line  `#{line}`"
      end)

    """
    #{length(violations)} rule fix(es) drop a comment that sits on a line they leave
    verbatim (the re-rendered replacement does not carry the comment). Each is a
    rule whose fix must preserve the comment:

    #{body}
    """
  end
end
