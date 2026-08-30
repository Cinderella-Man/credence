defmodule Credence.Pattern.NoMultiArityFnInStringReplace do
  @moduledoc """
  Detects `String.replace/3` calls where the replacement is a multi-arity
  anonymous function and rewrites them to `Regex.replace/3`.

  `String.replace/3` only accepts arity-1 function replacements (guard:
  `is_function(replacement, 1)`). A multi-arity callback used for regex
  capture groups compiles but always crashes at runtime with
  `FunctionClauseError`.

  `Regex.replace/3` natively supports multi-arity callbacks by passing
  the full match and captured groups as separate arguments. It also takes
  arguments in a different order: `(regex, string, replacement)` instead
  of `(string, pattern, replacement)`.

  ## Bad

      String.replace(str, ~r/([a-z]+)@([a-z]+)/, fn _, local, domain ->
        "\#{local}@\#{domain}"
      end)

  ## Good

      Regex.replace(~r/([a-z]+)@([a-z]+)/, str, fn _, local, domain ->
        "\#{local}@\#{domain}"
      end)
  """
  use Credence.Pattern.Rule
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _dot_meta, [{:__aliases__, _alias_meta, [:String]}, :replace]}, call_meta,
         [_str, pattern, {:fn, _, _} = fn_node]} = node,
        acc ->
          if not literal_binary?(pattern) and multi_arity_fn?(fn_node) do
            {node, [build_issue(call_meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, fn
      {{:., dot_meta, [{:__aliases__, alias_meta, [:String]}, :replace]}, call_meta,
       [str, pattern, {:fn, _, _} = fn_node]} = node ->
        if not literal_binary?(pattern) and multi_arity_fn?(fn_node) do
          {{:., dot_meta, [{:__aliases__, alias_meta, [:Regex]}, :replace]}, call_meta,
           [pattern, str, fn_node]}
        else
          node
        end

      node ->
        node
    end)
  end

  defp multi_arity_fn?({:fn, _, clauses}) do
    Enum.any?(clauses, fn
      # A guarded clause wraps its params in a `:when` node whose args are
      # the params followed by the guard expression.
      {:->, _, [[{:when, _, when_args}], _]} when length(when_args) >= 3 -> true
      {:->, _, [params, _]} when length(params) >= 2 -> true
      _ -> false
    end)
  end

  defp literal_binary?({:__block__, _, [value]}) when is_binary(value), do: true
  defp literal_binary?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_multi_arity_fn_in_string_replace,
      message:
        "`String.replace/3` only accepts arity-1 function replacements. " <>
          "A multi-arity callback crashes with `FunctionClauseError` at runtime. " <>
          "Use `Regex.replace/3` instead, which natively supports multi-arity callbacks " <>
          "by passing full match + captured groups as separate arguments.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
