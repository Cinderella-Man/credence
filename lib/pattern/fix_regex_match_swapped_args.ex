defmodule Credence.Pattern.FixRegexMatchSwappedArgs do
  @moduledoc """
  Rewrites `=~` calls where a regex (literal or module attribute) is on the
  **left** side — which crashes at runtime with `FunctionClauseError` because
  `Kernel.=~/2` requires `is_binary(left)`.

  The fix swaps the operands: `string =~ regex` is the call the author meant.

  Also detects module attributes holding a `~r` literal — e.g. `@re =~ string`
  where `@re` was defined as `~r/pattern/`.

  ## Bad

      @valid_identifier_regex ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/
      @valid_identifier_regex =~ name

      ~r/^prefix/ =~ string

  ## Good

      @valid_identifier_regex ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/
      name =~ @valid_identifier_regex

      string =~ ~r/^prefix/

  ## Safety

  Swapping the operands of `=~` changes the answer whenever the left side can
  be a binary (`"ab" =~ "a"` is a substring check and is not symmetric), so the
  rule fires only when the left side is **provably never a binary** — a certain
  `FunctionClauseError` — and the swap is a repair:

    * a `~r` sigil literal on the left always crashes;
    * a module attribute qualifies only when **every** `@attr value` assignment
      to that name in the file is a `~r` literal (a reassignment like
      `@re "text"` disqualifies the name everywhere — `@re =~ s` is then valid
      substring code at some use sites, and swapping it would change the
      answer);
    * any `Module.put_attribute`/`Module.register_attribute` call in the file
      disqualifies **all** attributes (values become invisible to this
      analysis);
    * `=~` occurrences inside `quote` blocks are never flagged via attributes —
      the attribute resolves in whatever module the quoted code is injected
      into, not this one.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    regex_attrs = collect_regex_attrs(ast)
    quoted = quoted_match_metas(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:=~, meta, [left, _right]} = node, issues ->
          if regex_on_left?(left, regex_attrs, meta, quoted) do
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
    quoted = quoted_match_metas(ast)

    RuleHelpers.patches_from_postwalk(ast, fn
      {:=~, meta, [left, right]} = node ->
        if regex_on_left?(left, regex_attrs, meta, quoted) do
          {:=~, meta, [right, left]}
        else
          node
        end

      node ->
        node
    end)
  end

  # Names of module attributes that provably hold a regex at every use site:
  # every `@name value` assignment in the file is a ~r literal, and no dynamic
  # attribute mutation (`Module.put_attribute`/`register_attribute`) exists
  # anywhere that could sneak in a non-regex value.
  defp collect_regex_attrs(ast) do
    {_ast, {regex, other, dynamic?}} =
      Macro.prewalk(ast, {MapSet.new(), MapSet.new(), false}, fn
        {:@, _meta, [{attr_name, _, [value]}]} = node, {regex, other, dynamic?}
        when is_atom(attr_name) ->
          case value do
            {:sigil_r, _, _} -> {node, {MapSet.put(regex, attr_name), other, dynamic?}}
            _ -> {node, {regex, MapSet.put(other, attr_name), dynamic?}}
          end

        node, {regex, other, dynamic?} ->
          {node, {regex, other, dynamic? or attr_mutation?(node)}}
      end)

    if dynamic?, do: MapSet.new(), else: MapSet.difference(regex, other)
  end

  defp attr_mutation?({{:., _, [{:__aliases__, _, [:Module]}, fun]}, _, _})
       when fun in [:put_attribute, :register_attribute],
       do: true

  # Bare calls after `import Module` — over-matches unrelated local functions
  # of the same name, which only makes the rule more conservative.
  defp attr_mutation?({fun, _, args})
       when fun in [:put_attribute, :register_attribute] and is_list(args),
       do: true

  defp attr_mutation?(_), do: false

  # Metas of every `=~` node that sits inside a `quote` block. Attribute reads
  # in quoted code resolve in the module the code is injected into, so this
  # file's attribute values say nothing about them.
  defp quoted_match_metas(ast) do
    {_ast, metas} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:quote, _, args} = node, acc when is_list(args) ->
          {_node, inner} =
            Macro.prewalk(node, [], fn
              {:=~, meta, [_, _]} = n, inner -> {n, [meta | inner]}
              n, inner -> {n, inner}
            end)

          {node, Enum.into(inner, acc)}

        node, acc ->
          {node, acc}
      end)

    metas
  end

  defp regex_on_left?({:sigil_r, _, _}, _regex_attrs, _meta, _quoted), do: true

  defp regex_on_left?({:@, _, [{attr_name, _, nil}]}, regex_attrs, meta, quoted),
    do: MapSet.member?(regex_attrs, attr_name) and not MapSet.member?(quoted, meta)

  defp regex_on_left?(_, _, _, _), do: false

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
