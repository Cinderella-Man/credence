defmodule Credence.Rule.NoUnnecessaryCatchAllRaise do
  @moduledoc """
  Detects function clauses where every argument is a wildcard and the
  body does nothing but `raise`.

  ## Why this matters

  Elixir's `FunctionClauseError` is a first-class debugging tool.  When
  no clause matches, the runtime raises an error that names the function
  *and* shows the exact arguments that failed to match.  A hand-written
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

  1. **Every** argument is a wildcard (`_` or `_name`), and
  2. The body consists solely of a `raise` call.

  Guarded clauses are not flagged — the guard implies intentional
  matching logic even if the arguments are wildcards.

  ## Not flagged

  - Catch-all clauses that return a value (e.g. `{:error, :invalid}`)
  - Clauses with logic before the raise (logging, cleanup)
  - Zero-arity functions
  - Clauses with guard expressions
  """

  @behaviour Credence.Rule
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

  # ------------------------------------------------------------
  # NODE MATCHING
  #
  # Match def/defp WITHOUT a guard.  Guarded clauses have the shape
  # {def_type, meta, [{:when, _, [head, guard]}, body]} — those
  # won't match here because the first tuple element would be
  # {:when, ...} rather than {fn_name, ...} with an atom name.
  # ------------------------------------------------------------

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

  # ------------------------------------------------------------
  # WILDCARD DETECTION
  # ------------------------------------------------------------

  # A zero-arity function cannot be a "catch-all".
  defp all_wildcards?([]), do: false

  defp all_wildcards?(args), do: Enum.all?(args, &wildcard?/1)

  defp wildcard?({:_, _, ctx}) when is_atom(ctx), do: true

  defp wildcard?({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    name |> Atom.to_string() |> String.starts_with?("_")
  end

  defp wildcard?(_), do: false

  # ------------------------------------------------------------
  # BODY INSPECTION
  #
  # Only flag when the body is *exclusively* a raise call.
  # Bodies with logging, cleanup, or other expressions before
  # the raise are left alone — they may have a legitimate purpose.
  # ------------------------------------------------------------

  defp body_only_raises?(do: {:raise, _, _}), do: true
  defp body_only_raises?(_), do: false

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

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
