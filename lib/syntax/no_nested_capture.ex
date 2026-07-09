defmodule Credence.Syntax.NoNestedCapture do
  @moduledoc """
  Repairs nested captures — `&(expr)` inside another `&(expr)`.

  LLMs frequently generate nested captures (e.g., `&func(&1, &(&1+1))`),
  which is a compile-time error in Elixir: "nested captures are not allowed".
  The fix replaces inner captures with anonymous functions, enabling compilation.

  ## Bad (won't compile)

      &Map.update(&1, 0, &(&1 + 1))

  ## Good

      &Map.update(&1, 0, fn x -> x + 1 end)
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @var_names [:x, :y, :z, :w, :v, :u, :t, :s, :r, :q]

  @impl true
  def analyze(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        find_nested_captures(ast)
        |> Enum.map(fn node ->
          meta = elem(node, 1)
          line = Keyword.get(meta, :line, 0)

          %Issue{
            rule: :no_nested_capture,
            message:
              "Nested captures are not allowed in Elixir. " <>
                "Use `fn` for the inner capture instead.",
            meta: %{line: line}
          }
        end)

      {:error, _} ->
        []
    end
  end

  @impl true
  def fix(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        nested = find_nested_captures(ast)

        case nested do
          [] ->
            source

          _ ->
            patches =
              Enum.map(nested, fn node ->
                range = Sourceror.get_range(node)
                replacement = build_fn_replacement(node)
                %{range: range, change: replacement}
              end)

            Sourceror.patch_string(source, patches)
        end

      {:error, _} ->
        source
    end
  end

  # Walk the AST tracking capture depth. A `&(expr)` (non-integer arg) that
  # appears at depth > 0 is nested inside another capture and must be fixed.
  defp find_nested_captures(ast) do
    {_ast, {_depth, nested}} =
      Macro.traverse(
        ast,
        {0, []},
        fn
          {:&, _meta, [arg]} = node, {depth, acc} when not is_integer(arg) ->
            new_acc = if depth > 0, do: [node | acc], else: acc
            {node, {depth + 1, new_acc}}

          node, {depth, acc} ->
            {node, {depth, acc}}
        end,
        fn
          {:&, _meta, [arg]} = node, {depth, acc} when not is_integer(arg) ->
            {node, {depth - 1, acc}}

          node, {depth, acc} ->
            {node, {depth, acc}}
        end
      )

    Enum.reverse(nested)
  end

  # Build the `fn x, y, ... -> body end` replacement string for a nested capture.
  defp build_fn_replacement({:&, _meta, [body]}) do
    max_var = find_max_capture_var(body)

    if max_var == 0 do
      # No capture variables: fn -> body end (0-arity)
      body_str = Sourceror.to_string(body)
      "fn -> #{body_str} end"
    else
      params = for i <- 1..max_var, do: var_name(i)
      param_str = Enum.join(params, ", ")
      new_body = replace_capture_vars(body)
      body_str = Sourceror.to_string(new_body)
      "fn #{param_str} -> #{body_str} end"
    end
  end

  # Find the highest &N reference in an AST subtree.
  defp find_max_capture_var(ast) do
    {_, max} =
      Macro.prewalk(ast, 0, fn
        {:&, _, [n]}, acc when is_integer(n) and n > 0 ->
          {nil, max(n, acc)}

        node, acc ->
          {node, acc}
      end)

    max
  end

  # Replace every &N with the corresponding named variable.
  defp replace_capture_vars(ast) do
    {new_ast, _} =
      Macro.prewalk(ast, nil, fn
        {:&, _meta, [n]}, _acc when is_integer(n) and n > 0 ->
          {{var_name(n), [], nil}, nil}

        node, acc ->
          {node, acc}
      end)

    new_ast
  end

  defp var_name(n) when n <= 10, do: Enum.at(@var_names, n - 1)
  defp var_name(n), do: :"v#{n}"
end
