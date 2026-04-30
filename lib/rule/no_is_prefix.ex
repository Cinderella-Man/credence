defmodule Credence.Rule.NoIsPrefix do
  @moduledoc """
  Style rule: Detects functions named with an `is_` prefix that are not
  guard-safe BIFs.

  In Elixir, predicate functions use a trailing `?` by convention (e.g.
  `valid?/1`, `palindrome?/1`). The `is_` prefix is reserved for guard-safe
  type checks from Erlang (`is_list/1`, `is_integer/1`, etc.). User-defined
  functions named `is_foo` look like guards but aren't usable in guards,
  which misleads readers.

  ## Bad

      def is_valid_palindrome(s), do: ...
      defp is_empty(list), do: ...

  ## Good

      def valid_palindrome?(s), do: ...
      defp empty?(list), do: ...
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  # Guard-safe BIFs from Erlang that legitimately use is_ prefix.
  # We skip these so we don't flag wrapper functions that shadow them.
  @erlang_guards ~w(
    is_atom is_binary is_bitstring is_boolean is_exception is_float
    is_function is_integer is_list is_map is_map_key is_nil
    is_number is_pid is_port is_reference is_struct is_tuple
  )a

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # 1. Guarded: def is_foo(args) when ..., do: ...
        # (Matched first because it's more specific)
        {kind, meta, [{:when, _, [{name, _, _params}, _guard]}, _body]} = node, issues
        when kind in [:def, :defp] and is_atom(name) ->
          {node, maybe_flag(name, kind, meta, issues)}

        # 2. Unguarded: def is_foo(args), do: ...
        # (Added `name != :when` to prevent swallowing guarded functions)
        {kind, meta, [{name, _, _params}, _body]} = node, issues
        when kind in [:def, :defp] and is_atom(name) and name != :when ->
          {node, maybe_flag(name, kind, meta, issues)}

        node, issues ->
          {node, issues}
      end)

    # Deduplicate — multi-clause functions produce multiple AST nodes
    issues
    |> Enum.reverse()
    |> Enum.uniq_by(fn issue -> issue.message end)
  end

  defp maybe_flag(name, _kind, meta, issues) do
    name_str = Atom.to_string(name)

    if String.starts_with?(name_str, "is_") and name not in @erlang_guards do
      suggested = name_str |> String.trim_leading("is_") |> Kernel.<>("?")

      issue = %Issue{
        rule: :no_is_prefix,
        severity: :info,
        message:
          "Function `#{name_str}/` uses an `is_` prefix. In Elixir, predicates use a `?` suffix " <>
            "by convention (e.g. `#{suggested}`). The `is_` prefix is reserved for guard-safe type checks.",
        meta: %{line: Keyword.get(meta, :line)}
      }

      [issue | issues]
    else
      issues
    end
  end
end
