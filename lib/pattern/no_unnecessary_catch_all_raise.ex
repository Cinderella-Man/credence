defmodule Credence.Pattern.NoUnnecessaryCatchAllRaise do
  @moduledoc """
  Detects function clauses where every argument is a wildcard and the
  body does nothing but `raise`.

  ## Why this matters

  Elixir's `FunctionClauseError` is a first-class debugging tool.  When
  no clause matches, the runtime raises an error that names the function
  _and_ shows the exact arguments that failed to match.  A hand-written
  catch-all that raises a generic error actively degrades that signal:

      # Bad — hides the actual arguments from the error
      def missing_number(_), do: raise(ArgumentError, "expected a list")

      # Good — Elixir does this automatically, with better diagnostics
      # (just remove the catch-all clause entirely)

  LLMs generate these defensive catch-alls frequently because their
  training data includes Python / Java patterns where unhandled cases
  must be raised explicitly.  In Elixir the convention is to let
  non-matching calls crash naturally.

  ## Flagged patterns

  Any `def` / `defp` clause where:
  1. **Every** argument is a wildcard `_` or `_name`), and
  2. The body consists solely of a `raise` call.

  Guarded clauses are not flagged — the guard implies intentional
  matching logic even if the arguments are wildcards.

  ## Not flagged

  - Catch-all clauses that return a value (e.g. `{:error, :invalid}`)
  - Clauses with logic before the raise (logging, cleanup)
  - Zero-arity functions
  - Clauses with guard expressions

  ## Fix

  Removes the unnecessary catch-all clause, letting Elixir's built-in
  `FunctionClauseError` handle unmatched arguments with better diagnostics.
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {def_type, _meta, [{fn_name, _, args}, body]} = node, acc
        when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) ->
          if all_wildcards?(args) and body_only_raises?(body) do
            {node, [removal_patch(node) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  # Replace the def node — plus the trailing newline that follows it
  # on its own line — with the empty string. Same trick as
  # `binding_removal_patch/1` in `no_list_to_tuple_for_access.ex`.
  defp removal_patch(def_node) do
    range = Sourceror.get_range(def_node)

    %{
      range: %{
        start: [line: range.start[:line], column: 1],
        end: [line: range.end[:line] + 1, column: 1]
      },
      change: ""
    }
  end

  # NODE MATCHING
  defp check_node({def_type, meta, [{fn_name, _, args}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    if all_wildcards?(args) and body_only_raises?(body) do
      {:ok,
       %Issue{
         rule: :no_unnecessary_catch_all_raise,
         message: build_message(def_type, fn_name, length(args)),
         meta: %{line: Keyword.get(meta, :line)}
       }}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  # A zero-arity function cannot be a "catch-all".
  defp all_wildcards?([]), do: false
  defp all_wildcards?(args), do: Enum.all?(args, &wildcard?/1)

  defp wildcard?({:_, _, ctx}) when is_atom(ctx), do: true

  defp wildcard?({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    name |> Atom.to_string() |> String.starts_with?("_")
  end

  defp wildcard?(_), do: false

  defp body_only_raises?(body) when is_list(body) do
    case extract_do_body(body) do
      {:ok, {:raise, _, _}} -> true
      _ -> false
    end
  end

  defp body_only_raises?(_), do: false

  defp extract_do_body(body) do
    Enum.find_value(body, :error, fn
      {{:__block__, _, [:do]}, expr} -> {:ok, expr}
      _ -> nil
    end)
  end

  defp build_message(def_type, fn_name, arity) do
    """
    Unnecessary catch-all clause in `#{def_type} #{fn_name}/#{arity}`.
    This clause matches all remaining arguments only to raise an error.
    Elixir already raises a `FunctionClauseError` when no clause matches,
    and it includes the actual failing arguments in the error — which is
    more useful for debugging than a generic message.
    Remove this clause and let Elixir's built-in error handling do the work.
    """
  end
end
