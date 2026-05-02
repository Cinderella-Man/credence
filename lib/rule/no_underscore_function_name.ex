defmodule Credence.Rule.NoUnderscoreFunctionName do
  @moduledoc """
  Detects function names that use a leading underscore to indicate privacy,
  a convention borrowed from Python that is non-idiomatic in Elixir.

  ## Why this matters

  In Python, `_private_method` signals "internal use."  In Elixir, `defp`
  is the privacy mechanism, and a leading underscore on a name signals
  "unused variable" — not "private function."  LLMs frequently generate
  helper functions like `_factorial`, `_do_find`, or `_fibonacci` because
  their training data mixes Python and Elixir conventions.

  The Elixir convention for recursive helpers is the `do_` prefix:

      # Flagged — Python convention
      defp _factorial(0, acc), do: acc
      defp _factorial(n, acc), do: _factorial(n - 1, n * acc)

      # Idiomatic — Elixir convention
      defp do_factorial(0, acc), do: acc
      defp do_factorial(n, acc), do: do_factorial(n - 1, n * acc)

  ## Detection scope

  Flags any `def` or `defp` clause where the function name starts with
  a single underscore.  Names starting with double underscores (`__`)
  are excluded — those are legitimate Elixir/Erlang callbacks such as
  `__using__/1`, `__before_compile__/1`, and `__info__/1`.
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
  # ------------------------------------------------------------

  # Guarded: def/defp name(args) when guard, do: body
  # Must come before the unguarded clause because {:when, _, _}
  # also matches {fn_name, _, args} where fn_name == :when.
  defp check_node({def_type, meta, [{:when, _, [{fn_name, _, args}, _guard]}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    if underscore_prefixed?(fn_name) do
      {:ok, build_issue(def_type, fn_name, length(args), meta)}
    else
      :error
    end
  end

  # Unguarded: def/defp name(args), do: body
  defp check_node({def_type, meta, [{fn_name, _, args}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    if underscore_prefixed?(fn_name) do
      {:ok, build_issue(def_type, fn_name, length(args), meta)}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  # ------------------------------------------------------------
  # HELPERS
  # ------------------------------------------------------------

  defp underscore_prefixed?(name) do
    str = Atom.to_string(name)
    String.starts_with?(str, "_") and not String.starts_with?(str, "__")
  end

  defp suggested_name(fn_name) do
    fn_name
    |> Atom.to_string()
    |> String.replace_leading("_", "do_")
  end

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

  defp build_issue(def_type, fn_name, arity, meta) do
    %Issue{
      rule: :no_underscore_function_name,
      message: build_message(def_type, fn_name, arity),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_message(def_type, fn_name, arity) do
    suggested = suggested_name(fn_name)

    """
    `#{def_type} #{fn_name}/#{arity}` uses a Python-style underscore prefix.

    In Elixir, `defp` already makes a function private. The leading \
    underscore convention signals "unused variable," not "private function."

    Use the `do_` prefix instead:

        defp #{suggested}(...)
    """
  end
end
