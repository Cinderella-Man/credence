defmodule Credence.Pattern.NoKeywordGetWithAtomFirstArg do
  @moduledoc """
  Detects `Keyword.get` called with a bare atom literal as the first argument.

  `Keyword.get/2` and `Keyword.get/3` require a keyword list as the first
  argument. Passing an atom literal (e.g. `:clock`) as the first argument
  always crashes at runtime with `FunctionClauseError` because atoms are not
  keyword lists.

  LLMs produce this when they confuse the argument order, writing
  `Keyword.get(:atom, default)` instead of `Keyword.get(opts, :atom, default)`.

  ## Bad

      Keyword.get(:clock, fn -> :default end)
      Keyword.get(:timeout, 5000)
      Keyword.get(:key, :lookup, :fallback)

  ## Good

      fn -> :default end
      5000
      :fallback

  ## Repair, not a rewrite

  This is a repair rule: `Keyword.get(:atom, ...)` crashes on every input
  because the first argument must be a keyword list. The fix extracts the
  default value (the last argument) which is what the code intended to return.

  Only 2- and 3-argument calls are flagged (the arities `Keyword.get` actually
  has). A call with four or more arguments is some other mistake — there is no
  "default" slot to extract — so it is left alone.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    if keyword_alias_shadowed?(ast) do
      []
    else
      piped = piped_get_positions(ast)

      {_ast, issues} =
        Macro.prewalk(ast, [], fn node, acc ->
          case detect(node, piped) do
            {:ok, meta} -> {node, [build_issue(meta) | acc]}
            :skip -> {node, acc}
          end
        end)

      Enum.reverse(issues)
    end
  end

  @impl true
  def fix_patches(ast, _opts) do
    if keyword_alias_shadowed?(ast) do
      []
    else
      piped = piped_get_positions(ast)

      ast
      |> Credence.RuleHelpers.patches_from_postwalk(fn
        # Direct call (not piped): Keyword.get(:atom, default) or Keyword.get(:atom, key, default)
        {{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, [first | rest]} = node ->
          if not MapSet.member?(piped, position(meta)) and atom_literal?(first) and
               length(rest) in 1..2 do
            preserve_evaluated_args(rest)
          else
            node
          end

        # Piped call: :atom |> Keyword.get(key) or :atom |> Keyword.get(key, default)
        {:|>, _, [pipe_lhs, {{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, _, args}]} = node ->
          if atom_literal?(pipe_lhs) and length(args) in 1..2 do
            preserve_evaluated_args(args)
          else
            node
          end

        node ->
          node
      end)
      |> Enum.map(fn patch ->
        if multi_expression?(patch.change) do
          %{patch | change: "(" <> patch.change <> ")"}
        else
          patch
        end
      end)
    end
  end

  defp keyword_alias_shadowed?(ast) do
    {_ast, shadowed?} =
      Macro.prewalk(ast, false, fn
        {:alias, _, [_module, opts]} = node, acc when is_list(opts) ->
          {node, acc or aliases_as_keyword?(opts)}

        node, acc ->
          {node, acc}
      end)

    shadowed?
  end

  defp aliases_as_keyword?(opts) do
    Enum.any?(opts, fn
      {{:__block__, _, [:as]}, alias_ast} -> keyword_alias?(alias_ast)
      {:as, alias_ast} -> keyword_alias?(alias_ast)
      _ -> false
    end)
  end

  defp keyword_alias?({:__aliases__, _, [:Keyword]}), do: true
  defp keyword_alias?(_), do: false

  # Direct call (not piped) where first arg is an atom literal
  defp detect(
         {{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, [first | rest]},
         piped
       ) do
    if not MapSet.member?(piped, position(meta)) and atom_literal?(first) and
         length(rest) in 1..2 do
      {:ok, meta}
    else
      :skip
    end
  end

  # Piped call where pipe LHS is an atom literal
  defp detect(
         {:|>, _, [pipe_lhs, {{:., meta, [{:__aliases__, _, [:Keyword]}, :get]}, _, args}]},
         _piped
       ) do
    if atom_literal?(pipe_lhs) and length(args) in 1..2 do
      {:ok, meta}
    else
      :skip
    end
  end

  defp detect(_, _), do: :skip

  # Positions of Keyword.get calls that are the RHS of a pipe
  defp piped_get_positions(ast) do
    {_ast, set} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, _}]} = node, acc ->
          {node, MapSet.put(acc, position(meta))}

        node, acc ->
          {node, acc}
      end)

    set
  end

  defp position(meta), do: {Keyword.get(meta, :line), Keyword.get(meta, :column)}

  defp atom_literal?({:__block__, _, [atom]}) when is_atom(atom), do: true
  defp atom_literal?(atom) when is_atom(atom), do: true
  defp atom_literal?(_), do: false

  defp preserve_evaluated_args([default]), do: default
  defp preserve_evaluated_args([key, default]), do: {:__block__, [], [key, default]}

  defp multi_expression?(change) do
    match?({:ok, {:__block__, _, [_, _]}}, Sourceror.parse_string(change))
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_keyword_get_with_atom_first_arg,
      message: message(),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp message do
    "`Keyword.get` called with an atom as the first argument — " <>
      "the first argument must be a keyword list. This always crashes " <>
      "with `FunctionClauseError` at runtime."
  end
end
