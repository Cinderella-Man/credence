defmodule Credence.Pattern.FixRegexMatchSwappedArgs do
  @moduledoc """
  Rewrites `=~` calls where a regex (literal or module attribute) is on the
  **left** side — which crashes at runtime with `FunctionClauseError` because
  `Kernel.=~/2` requires `is_binary(left)`.

  The fix swaps the operands. This is safe because `left =~ right` and
  `right =~ left` return identical booleans when `left` is a string and
  `right` is a regex.

  Also detects module attributes assigned a `~r` literal earlier in the same
  module — e.g. `@re =~ string` where `@re` was defined as `~r/pattern/`.

  ## Bad

      @valid_identifier_regex ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/
      @valid_identifier_regex =~ name

      ~r/^prefix/ =~ string

  ## Good

      @valid_identifier_regex ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/
      name =~ @valid_identifier_regex

      string =~ ~r/^prefix/
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    regex_attrs = collect_regex_attrs(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:=~, meta, [left, _right]} = node, issues ->
          if regex_on_left?(left, regex_attrs) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    regex_attrs = collect_regex_attrs(ast)

    RuleHelpers.patches_from_postwalk(ast, fn
      {:=~, meta, [left, right]} = node ->
        if regex_on_left?(left, regex_attrs) do
          {:=~, meta, [right, left]}
        else
          node
        end

      node ->
        node
    end)
  end

  # Collect names of module attributes assigned a ~r literal.
  defp collect_regex_attrs(ast) do
    {_ast, attrs} =
      Macro.prewalk(ast, [], fn
        {:@, _meta,
         [
           {attr_name, _,
            [{:sigil_r, _, _}]}
         ]} = node,
        acc ->
          {node, [attr_name | acc]}

        node, acc ->
          {node, acc}
      end)

    MapSet.new(attrs)
  end

  defp regex_on_left?({:sigil_r, _, _}, _regex_attrs), do: true

  defp regex_on_left?({:@, _, [{attr_name, _, nil}]}, regex_attrs),
    do: MapSet.member?(regex_attrs, attr_name)

  defp regex_on_left?(_, _), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :fix_regex_match_swapped_args,
      message:
        "A regex on the left side of `=~` crashes at runtime because `Kernel.=~/2` requires " <>
          "`is_binary(left)`. Swap the operands: `string =~ regex`.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
