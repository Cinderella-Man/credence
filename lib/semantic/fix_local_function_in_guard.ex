defmodule Credence.Semantic.FixLocalFunctionInGuard do
  @moduledoc """
  Fixes the compile error caused by calling a local function inside a guard.

  LLMs sometimes define a helper like `defp is_range(x), do: is_map(x)` and
  then use it in a guard clause (`when is_range(x)`). The Elixir compiler
  rejects this because only macros (not local functions) can be invoked inside
  guards:

      "cannot find or invoke local is_range/1 inside a guard. Only macros can
       be invoked inside a guard and they must be defined before their
       invocation. Called as: is_range(length_range)"

  The deterministic fix replaces the local function call in the guard with
  `is_map/1` (ranges are maps in Elixir), preserving the clause dispatch
  semantics.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "cannot find or invoke local is_range/1 inside a guard"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_local_function_in_guard,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:when, when_meta, [fn_head, guard]}, acc ->
            {new_guard, guard_changed} = replace_local_fn_in_guard(guard)

            if guard_changed do
              {{:when, when_meta, [fn_head, new_guard]}, true}
            else
              {{:when, when_meta, [fn_head, guard]}, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Replace `is_range(x)` with `is_map(x)` in a guard expression tree.
  defp replace_local_fn_in_guard({:is_range, meta, args}) do
    {{:is_map, meta, args}, true}
  end

  defp replace_local_fn_in_guard({op, meta, args}) when is_list(args) do
    {new_args, changed} =
      Enum.map_reduce(args, false, fn arg, acc ->
        {new_arg, arg_changed} = replace_local_fn_in_guard(arg)
        {new_arg, acc || arg_changed}
      end)

    {{op, meta, new_args}, changed}
  end

  defp replace_local_fn_in_guard(node), do: {node, false}

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
