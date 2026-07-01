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
  def check(ast, opts) do
    source = Keyword.get(opts, :source, "")

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:=, meta, [{var_name, _, nil}, {:&, _, [{:/, _, [{fn_name, _, nil}, arity_block]}]}]} =
            node,
        issues
        when is_atom(var_name) and is_atom(fn_name) ->
          case extract_integer(arity_block) do
            {:ok, arity} when arity > 0 ->
              if fixable_capture?(ast, source, var_name, arity, node) do
                issue = %Issue{
                  rule: :no_redundant_local_capture,
                  message:
                    "Redundant capture of local function #{fn_name}/#{arity}. " <>
                      "Call #{fn_name}() directly instead of capturing and applying via #{var_name}().()",
                  meta: %{line: Keyword.get(meta, :line)}
                }

                {node, [issue | issues]}
              else
                {node, issues}
              end

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

    assignments = collect_assignments(ast, source)

    if assignments == %{} do
      []
    else
      assignment_patches = assignment_removal_patches(assignments, source)
      usage_patches = usage_replacement_patches(ast, assignments)
      assignment_patches ++ usage_patches
    end
  end

  defp collect_assignments(ast, source) do
    {_ast, assignments} =
      Macro.prewalk(ast, %{}, fn
        {:=, _meta, [{var_name, _, nil}, {:&, _, [{:/, _, [{fn_name, _, nil}, arity_block]}]}]} =
            node,
        acc
        when is_atom(var_name) and is_atom(fn_name) ->
          case extract_integer(arity_block) do
            {:ok, arity} when arity > 0 ->
              if fixable_capture?(ast, source, var_name, arity, node) do
                {node, Map.put(acc, var_name, {fn_name, arity, node})}
              else
                {node, acc}
              end

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

  # A capture is fixable only when removing it and inlining its calls is both
  # behaviour-preserving and renders cleanly:
  #   * exclusively_applied? — every reference to `var` is a `var.(args)` of the
  #     captured arity (never passed/used as a value);
  #   * single_capture? — the name is captured exactly ONCE in the module, so the
  #     module-wide rewrite can't pick the wrong target across scopes (two
  #     `f = &foo/1` / `f = &bar/1` would otherwise collapse to one entry and
  #     mis-rewrite the other scope's calls);
  #   * alone_on_line? — the assignment is the only thing on its source line, so
  #     removing the whole line drops no neighbouring statement's side effect.
  defp fixable_capture?(ast, source, var, arity, assign_node) do
    exclusively_applied?(ast, var, arity) and single_capture?(ast, var) and
      alone_on_line?(assign_node, source)
  end

  defp single_capture?(ast, var) do
    {_ast, n} =
      Macro.prewalk(ast, 0, fn
        {:=, _, [{^var, _, nil}, {:&, _, [{:/, _, _}]}]} = node, acc -> {node, acc + 1}
        node, acc -> {node, acc}
      end)

    n == 1
  end

  # The assignment occupies its own line (only whitespace before its start column
  # and after its end column). The fix removes the whole line, so anything else
  # sharing the line would be lost.
  defp alone_on_line?(assign_node, source) do
    case Sourceror.get_range(assign_node) do
      %Sourceror.Range{start: [line: sl, column: sc], end: [line: el, column: ec]}
      when sl == el ->
        line = source |> String.split("\n") |> Enum.at(sl - 1, "")
        before = String.slice(line, 0, max(sc - 1, 0))
        rest = String.slice(line, (ec - 1)..-1//1)
        String.trim(before) == "" and String.trim(rest) == ""

      _ ->
        false
    end
  end

  # True if `var` is used somewhere AND every one of its references is the
  # function position of a `var.(args)` application with the captured arity — it
  # is never passed or used as a plain value. Only then is removing the capture
  # and inlining the calls behavior-preserving and still-compiling. (Capturing a
  # local just to pass it to a higher-order function — `&f(recorder, &1)` — is
  # idiomatic, and the rule must leave it alone.)
  defp exclusively_applied?(ast, var, arity) do
    refs = count_var_refs(ast, var)
    refs > 0 and refs == count_applied(ast, var, arity)
  end

  # References to `var` as a plain variable, NOT counting the capture
  # assignment's own LHS (those subtrees are skipped).
  defp count_var_refs(ast, var) do
    {_ast, n} =
      Macro.prewalk(ast, 0, fn
        {:=, _, [{^var, _, nil}, {:&, _, [{:/, _, _}]}]}, acc -> {:__skip__, acc}
        {^var, _, nil} = node, acc -> {node, acc + 1}
        node, acc -> {node, acc}
      end)

    n
  end

  # `var.(args)` applications whose arity matches the captured arity.
  defp count_applied(ast, var, arity) do
    {_ast, n} =
      Macro.prewalk(ast, 0, fn
        {{:., _, [{^var, _, nil}]}, _, args} = node, acc
        when is_list(args) and length(args) == arity ->
          {node, acc + 1}

        node, acc ->
          {node, acc}
      end)

    n
  end
end
