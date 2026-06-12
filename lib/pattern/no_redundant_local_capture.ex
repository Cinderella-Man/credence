defmodule Credence.Pattern.NoRedundantLocalCapture do
  @moduledoc """
  Detects redundant capture of a local function with immediate call.

  Capturing a local function reference (`var = &fn/arity`) and then calling
  it via `var.(args)` is non-idiomatic. Directly calling the function
  (`fn(args)`) is clearer and avoids creating an unnecessary anonymous function.

  ## Bad

      factorial = &factorial/1
      div(factorial.(2 * n), factorial.(n))

  ## Good

      div(factorial(2 * n), factorial(n))
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:=, meta, [{var_name, _, nil}, {:&, _, [{:/, _, [{fn_name, _, nil}, arity_block]}]}]} =
            node,
        issues
        when is_atom(var_name) and is_atom(fn_name) ->
          case extract_integer(arity_block) do
            {:ok, arity} when arity > 0 ->
              issue = %Issue{
                rule: :no_redundant_local_capture,
                message:
                  "Redundant capture of local function #{fn_name}/#{arity}. " <>
                    "Call #{fn_name}() directly instead of capturing and applying via #{var_name}().()",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | issues]}

            _ ->
              {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source, "")

    assignments = collect_assignments(ast)

    if assignments == %{} do
      []
    else
      assignment_patches = assignment_removal_patches(assignments, source)
      usage_patches = usage_replacement_patches(ast, assignments)
      assignment_patches ++ usage_patches
    end
  end

  defp collect_assignments(ast) do
    {_ast, assignments} =
      Macro.prewalk(ast, %{}, fn
        {:=, _meta, [{var_name, _, nil}, {:&, _, [{:/, _, [{fn_name, _, nil}, arity_block]}]}]} =
            node,
        acc
        when is_atom(var_name) and is_atom(fn_name) ->
          case extract_integer(arity_block) do
            {:ok, arity} when arity > 0 ->
              {node, Map.put(acc, var_name, {fn_name, arity, node})}

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    assignments
  end

  defp usage_replacement_patches(ast, assignments) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{var_name, _, nil}]}, call_meta, args} = node, patches
        when is_atom(var_name) and is_list(args) ->
          case Map.get(assignments, var_name) do
            {fn_name, arity, _assign_node} when length(args) == arity ->
              # Build the direct call AST
              direct_call = {fn_name, call_meta, args}
              replacement = Sourceror.to_string(direct_call)

              # Use Sourceror.get_range for the full var.(args) node
              case Sourceror.get_range(node) do
                %Sourceror.Range{} = range ->
                  patch = %{range: range, change: replacement}
                  {node, [patch | patches]}

                _ ->
                  {node, patches}
              end

            _ ->
              {node, patches}
          end

        node, patches ->
          {node, patches}
      end)

    patches
  end

  defp assignment_removal_patches(assignments, source) do
    source_lines = String.split(source, "\n")

    Enum.map(assignments, fn {_var_name, {_fn_name, _arity, assign_node}} ->
      case Sourceror.get_range(assign_node) do
        %Sourceror.Range{start: start_pos} ->
          start_line = start_pos[:line]

          # Get the line text to find where the newline is
          line_text = Enum.at(source_lines, start_line - 1, "")
          line_char_count = String.length(line_text)

          # Remove the entire line: from column 1 to past the last char + newline.
          # start_col is always 1 to remove leading whitespace too.
          actual_end_col = line_char_count + 2

          full_range = %Sourceror.Range{
            start: [line: start_line, column: 1],
            end: [line: start_line, column: actual_end_col]
          }

          %{range: full_range, change: ""}

        _ ->
          # Fallback: use the node's AST range directly
          %{
            range: Sourceror.get_range(assign_node),
            change: ""
          }
      end
    end)
  end

  defp extract_integer({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp extract_integer(n) when is_integer(n), do: {:ok, n}
  defp extract_integer(_), do: :error
end
