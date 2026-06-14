defmodule Credence.Semantic.AvoidRemoteFunctionInGuard do
  @moduledoc """
  Fixes compiler errors about remote function calls inside guards.

  The Elixir compiler forbids remote function calls (e.g. `MapSet.size/1`)
  inside guard clauses. When it encounters one, it emits:

      cannot invoke remote function Module.function/arity inside a guard

  The fix detects two consecutive `defp` clauses for the same function where:

    1. The first has a `when` guard that contains a remote function call.
    2. The second is a plain fallback clause (no guard) with the same name/arity.

  It merges them into a single clause whose body is an `if/else`:

      # Before (compiler error — remote call in guard)
      defp foo(args) when Module.fun(x) == value do
        body1
      end

      defp foo(args) do
        body2
      end

      # After (compiles cleanly)
      defp foo(args) do
        if Module.fun(x) == value do
          body1
        else
          body2
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, "cannot invoke remote function") and
      String.contains?(msg, "inside a guard")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :avoid_remote_function_in_guard,
      message: "Remote function call in guard — merging with fallback clause",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case parse(source) do
      {:ok, ast} ->
        apply_fix(source, ast, transform(ast))

      :error ->
        source
    end
  end

  defp apply_fix(source, ast, transformed) when transformed == ast, do: source

  defp apply_fix(source, ast, transformed) do
    rendered = Sourceror.to_string(transformed)

    case Sourceror.parse_string(rendered) do
      {:ok, re_parsed} ->
        apply_patches(source, Credence.RuleHelpers.patches_from_diff(ast, re_parsed))

      {:error, _} ->
        source
    end
  end

  defp apply_patches(source, []), do: source

  defp apply_patches(source, patches) do
    result = Sourceror.patch_string(source, patches)
    if result == source, do: source, else: result
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line

  defp parse(source) do
    {:ok, Sourceror.parse_string!(source)}
  rescue
    _ -> :error
  end

  # Walk the AST looking for defmodule blocks and transform their bodies.
  defp transform(ast) do
    Macro.postwalk(ast, fn
      {:defmodule, dm_meta, [alias_ast, body_kw]} = node ->
        case extract_do_body(body_kw) do
          {:ok, body} ->
            new_body = transform_module_body(body)

            if new_body == body do
              node
            else
              {:defmodule, dm_meta, [alias_ast, replace_do_body(body_kw, new_body)]}
            end

          :error ->
            node
        end

      node ->
        node
    end)
  end

  # In a module body (which may be a :__block__ of statements or a single
  # statement), find consecutive defp pairs to merge.
  defp transform_module_body({:__block__, meta, stmts}) do
    new_stmts = merge_consecutive_defps(stmts)
    {:__block__, meta, new_stmts}
  end

  defp transform_module_body(other), do: other

  # Walk a list of statements, merging consecutive defp pairs where the
  # first has a when-guard with a remote function call.
  defp merge_consecutive_defps([]), do: []
  defp merge_consecutive_defps([single]), do: [single]

  defp merge_consecutive_defps([first, second | rest]) do
    case try_merge_defp_pair(first, second) do
      {:ok, merged} ->
        # Continue scanning: there might be more pairs after the merged clause
        merge_consecutive_defps([merged | rest])

      :error ->
        [first | merge_consecutive_defps([second | rest])]
    end
  end

  # Try to merge two consecutive defp clauses.
  # Returns {:ok, merged_defp} or :error.
  defp try_merge_defp_pair(
         {:defp, meta1, [{:when, _when_meta, [head1, guard]}, body_kw1]},
         {:defp, _meta2, [head2, body_kw2]}
       ) do
    with true <- same_function?(head1, head2),
         true <- guard_has_remote_call?(guard),
         {:ok, body1} <- extract_do_body(body_kw1),
         {:ok, body2} <- extract_do_body(body_kw2) do
      # Build the if/else expression from the guard and both bodies
      if_expr =
        {:if, [do: [line: 1, column: 1], end: [line: 1, column: 1]],
         [
           guard,
           [
             {{:__block__, [line: 1, column: 1], [:do]}, body1},
             {{:__block__, [line: 1, column: 1], [:else]}, body2}
           ]
         ]}

      # Build the merged defp: use head1 (without when) + if body
      new_body_kw = [{{:__block__, [], [:do]}, if_expr}]
      {:ok, {:defp, meta1, [head1, new_body_kw]}}
    else
      _ -> :error
    end
  end

  defp try_merge_defp_pair(_, _), do: :error

  # Check if two function heads refer to the same function (same name and arity).
  defp same_function?({name, _, args1}, {name, _, args2})
       when is_atom(name) and is_list(args1) and is_list(args2),
       do: length(args1) == length(args2)

  defp same_function?(_, _), do: false

  # Check if a guard expression contains a remote function call.
  # A remote call looks like: Module.function(args)
  # In AST: {{:., _, [{:__aliases__, _, [:Module]}, :function]}, _, args}
  defp guard_has_remote_call?(guard) do
    {_ast, found} =
      Macro.prewalk(guard, false, fn
        {{:., _, [{:__aliases__, _, [_module]}, _fun]}, _, _} = node, _acc ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Extract the do-body from a keyword list body.
  # Handles both `[do: body]` and Sourceror's `[{{:__block__, _, [:do]}, body}]` forms.
  defp extract_do_body(kw) when is_list(kw) do
    Enum.find_value(kw, :error, fn
      {{:__block__, _, [:do]}, body} -> {:ok, body}
      {:do, body} -> {:ok, body}
      _ -> nil
    end)
  end

  defp extract_do_body(_), do: :error

  # Replace the do-body in a keyword list body.
  defp replace_do_body(kw, new_body) when is_list(kw) do
    Enum.map(kw, fn
      {{:__block__, meta, [:do]}, _} -> {{:__block__, meta, [:do]}, new_body}
      {:do, _} -> {:do, new_body}
      other -> other
    end)
  end
end
