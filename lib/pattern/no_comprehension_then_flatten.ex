defmodule Credence.Pattern.NoComprehensionThenFlatten do
  @moduledoc """
  Detects `for` comprehension piped to or wrapped by `List.flatten/1`.

  When a comprehension builds nested lists and immediately flattens them,
  `Enum.flat_map/2` does the same work in a single pass and is the
  idiomatic Elixir idiom.  LLMs frequently produce this pattern when
  the body conditionally returns a scalar or a list.

  ## Bad

      for divisor <- 1..n, rem(n, divisor) == 0 do
        if divisor == div(n, divisor), do: divisor, else: [divisor, div(n, divisor)]
      end
      |> List.flatten()

      List.flatten(for x <- list, do: f(x))

  ## Good

      Enum.flat_map(1..n, fn divisor ->
        if rem(n, divisor) == 0, do: [divisor, div(n, divisor)], else: []
      end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Piped: for ... do ... end |> List.flatten()
        {:|>, _,
         [
           {:for, _, _} = for_node,
           {{:., _, [{:__aliases__, _, [:List]}, :flatten]}, flatten_meta, []}
         ]} = node,
        acc ->
          if comprehension_mapped?(for_node) do
            {node, [build_issue(flatten_meta) | acc]}
          else
            {node, acc}
          end

        # Nested: List.flatten(for ... do ... end)
        {{:., _, [{:__aliases__, _, [:List]}, :flatten]}, flatten_meta,
         [
           {:for, _, _} = for_node
         ]} = node,
        acc ->
          if comprehension_mapped?(for_node) do
            {node, [build_issue(flatten_meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # A "mapped" comprehension is one without :reduce or :into — it builds
  # a list from the body expression.  Comprehensions with :reduce or :into
  # have different semantics and should not be flagged.
  #
  # Sourceror wraps keyword keys in {:__block__, [format: :keyword], [:atom]},
  # so we check for those structures rather than plain Keyword.has_key?/2.
  defp comprehension_mapped?({:for, _, args}) do
    not Enum.any?(args, &comprehension_option?/1)
  end

  defp comprehension_option?(opts) when is_list(opts) do
    Enum.any?(opts, fn
      {key_ast, _value} -> keyword_key?(key_ast, :reduce) or keyword_key?(key_ast, :into)
      _ -> false
    end)
  end

  defp comprehension_option?(_), do: false

  defp keyword_key?({:__block__, meta, [atom]}, name)
      when is_list(meta) and is_atom(atom) do
    Keyword.get(meta, :format) == :keyword and atom == name
  end

  defp keyword_key?(_, _), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_comprehension_then_flatten,
      message:
        "`for` comprehension piped to `List.flatten/1` creates an unnecessary " <>
          "intermediate nested list. Use `Enum.flat_map/2` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
