defmodule Credence.Rule.NoIsPrefixForNonGuard do
  @moduledoc """
  Detects `def`/`defp` functions with an `is_` prefix, which in Elixir
  is reserved for guard-safe functions defined with `defguard`.

  ## Why this matters

  Elixir has a clear naming convention for boolean-returning functions:

  - `is_foo/1` → must be usable in guard clauses (`defguard`)
  - `foo?/1` → regular boolean function (`def` / `defp`)

  LLMs generate `is_valid`, `is_palindrome`, `is_prime`, etc. on
  virtually every boolean function because Python and JavaScript use
  `is_` freely.  In Elixir this misleads readers into thinking the
  function is guard-safe:

      # Flagged — misleading convention
      def is_palindrome(str), do: str == String.reverse(str)

      # Idiomatic — ? suffix for non-guard booleans
      def palindrome?(str), do: str == String.reverse(str)

  ## Detection scope

  Only `def` and `defp` clauses are flagged.  `defguard`, `defguardp`,
  and `defmacro` are excluded since `is_` is correct for those.

  ## Severity

  `:warning`
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

    issues
    |> Enum.uniq_by(fn issue -> {issue.meta[:line], issue.message} end)
    |> Enum.reverse()
  end

  # ------------------------------------------------------------
  # NODE MATCHING
  # ------------------------------------------------------------

  # Guarded clause: must come first to avoid :when match
  defp check_node({def_type, meta, [{:when, _, [{fn_name, _, args}, _guard]}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    check_name(fn_name, def_type, length(args), meta)
  end

  # Unguarded clause
  defp check_node({def_type, meta, [{fn_name, _, args}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    check_name(fn_name, def_type, length(args), meta)
  end

  defp check_node(_), do: :error

  # ------------------------------------------------------------
  # NAME CHECK
  # ------------------------------------------------------------

  defp check_name(fn_name, def_type, arity, meta) do
    str = Atom.to_string(fn_name)

    if String.starts_with?(str, "is_") and not String.ends_with?(str, "?") do
      suggested = suggest_name(str)

      {:ok,
       %Issue{
         rule: :no_is_prefix_for_non_guard,
         severity: :warning,
         message: build_message(def_type, fn_name, arity, suggested),
         meta: %{line: Keyword.get(meta, :line)}
       }}
    else
      :error
    end
  end

  # ------------------------------------------------------------
  # NAME SUGGESTION
  # ------------------------------------------------------------

  defp suggest_name("is_valid_" <> rest), do: "valid_#{rest}?"
  defp suggest_name("is_" <> rest), do: "#{rest}?"

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

  defp build_message(def_type, fn_name, arity, suggested) do
    """
    `#{def_type} #{fn_name}/#{arity}` uses the `is_` prefix, which \
    in Elixir is reserved for guard-safe functions (`defguard`).

    For regular boolean functions, use the `?` suffix instead:

        #{def_type} #{suggested}(...)
    """
  end
end
