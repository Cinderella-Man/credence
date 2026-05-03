defmodule Credence.Rule.NoIsPrefixForNonGuard do
  @moduledoc """
  Detects `def`/`defp` functions with an `is_` prefix, which in Elixir
  is reserved for guard-safe functions defined with `defguard` or Erlang BIFs.

  ## Why this matters

  Elixir has a clear naming convention for boolean-returning functions:

  - `is_foo/1` → must be usable in guard clauses (`defguard`) or Erlang BIFs
  - `foo?/1` → regular boolean function (`def` / `defp`)

  LLMs generate `is_valid`, `is_palindrome`, etc., on virtually every boolean
  function because Python and JavaScript use `is_` freely. In Elixir, this
  misleads readers into thinking the function is guard-safe:

      # Flagged — misleading convention
      def is_palindrome(str), do: str == String.reverse(str)

      # Idiomatic — ? suffix for non-guard booleans
      def palindrome?(str), do: str == String.reverse(str)

  ## Exceptions

  Guard-safe BIFs from Erlang that legitimately use the `is_` prefix
  (like `is_list/1`, `is_binary/1`) are ignored so that user-defined wrapper
  functions shadowing them are not mistakenly flagged.
  """

  use Credence.Rule
  alias Credence.Issue

  # Guard-safe BIFs from Erlang that legitimately use the is_ prefix.
  @erlang_guards ~w(
    is_atom is_binary is_bitstring is_boolean is_exception is_float
    is_function is_integer is_list is_map is_map_key is_nil
    is_number is_pid is_port is_reference is_struct is_tuple
  )a

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

  # Guarded clause: must come first to avoid :when match
  defp check_node({def_type, meta, [{:when, _, [{fn_name, _, args}, _guard]}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    check_name(fn_name, def_type, length(args), meta)
  end

  # Unguarded clause (safeguarded with fn_name != :when)
  defp check_node({def_type, meta, [{fn_name, _, args}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) and fn_name != :when do
    check_name(fn_name, def_type, length(args), meta)
  end

  defp check_node(_), do: :error

  defp check_name(fn_name, def_type, arity, meta) do
    str = Atom.to_string(fn_name)

    if String.starts_with?(str, "is_") and not String.ends_with?(str, "?") and
         fn_name not in @erlang_guards do
      # Transforms "is_valid_foo" -> "valid_foo?"
      suggested = str |> String.trim_leading("is_") |> Kernel.<>("?")

      {:ok,
       %Issue{
         rule: :no_is_prefix_for_non_guard,
         message: build_message(def_type, fn_name, arity, suggested),
         meta: %{line: Keyword.get(meta, :line)}
       }}
    else
      :error
    end
  end

  defp build_message(def_type, fn_name, arity, suggested) do
    """
    `#{def_type} #{fn_name}/#{arity}` uses the `is_` prefix, which \
    in Elixir is reserved for guard-safe type checks (`defguard`).

    For regular boolean predicates, use the `?` suffix by convention:

        #{def_type} #{suggested}(...)
    """
  end
end
