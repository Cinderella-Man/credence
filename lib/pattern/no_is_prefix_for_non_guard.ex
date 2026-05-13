defmodule Credence.Pattern.NoIsPrefixForNonGuard do
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

  ## Bad

      def is_palindrome(str), do: str == String.reverse(str)

      defp is_valid_email(str), do: String.contains?(str, "@")

  ## Good

      def palindrome?(str), do: str == String.reverse(str)

      defp valid_email?(str), do: String.contains?(str, "@")

  ## Exceptions

  Guard-safe BIFs from Erlang that legitimately use the `is_` prefix
  (like `is_list/1`, `is_binary/1`) are ignored so that user-defined wrapper
  functions shadowing them are not mistakenly flagged.

  ## Auto-fix

  The fix renames the function definition and all bare (unqualified) call sites
  within the same source file. `is_valid_foo` becomes `valid_foo?`.

  Pass `auto_fix_public: false` to restrict the rename to `defp` only.
  Useful when running file-by-file: external callers of a public function
  live in other files and aren't visible to a per-file rule, so renaming
  a `def` can leave imports / qualified calls referencing the old name.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  # Guard-safe BIFs from Erlang that legitimately use the is_ prefix.
  @erlang_guards ~w(
    is_atom is_binary is_bitstring is_boolean is_exception is_float
    is_function is_integer is_list is_map is_map_key is_nil
    is_number is_pid is_port is_reference is_struct is_tuple
  )a

  @impl true
  def fixable?, do: true

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

  @impl true
  def fix(source, opts) do
    ast = Sourceror.parse_string!(source)

    rename_map =
      ast
      |> collect_renames()
      |> maybe_drop_public(ast, Keyword.get(opts, :auto_fix_public, true))

    if map_size(rename_map) == 0 do
      source
    else
      ast
      |> Macro.postwalk(fn node -> apply_renames(node, rename_map) end)
      |> Sourceror.to_string()
    end
  end

  # ── Fix helpers ──────────────────────────────────────────────────────

  # First pass: walk defs to build %{is_foo => :foo?} rename map
  defp collect_renames(ast) do
    {_ast, renames} =
      Macro.prewalk(ast, %{}, fn
        {def_type, _meta, [{:when, _, [{fn_name, _, args}, _guard]}, _body]} = node, acc
        when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) ->
          {node, maybe_add_rename(acc, fn_name)}

        {def_type, _meta, [{fn_name, _, args}, _body]} = node, acc
        when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) and
               fn_name != :when ->
          {node, maybe_add_rename(acc, fn_name)}

        node, acc ->
          {node, acc}
      end)

    renames
  end

  defp maybe_add_rename(acc, fn_name) do
    str = Atom.to_string(fn_name)

    if String.starts_with?(str, "is_") and not String.ends_with?(str, "?") and
         fn_name not in @erlang_guards do
      new_name = str |> String.trim_leading("is_") |> Kernel.<>("?") |> String.to_atom()
      Map.put(acc, fn_name, new_name)
    else
      acc
    end
  end

  defp maybe_drop_public(rename_map, _ast, true), do: rename_map

  defp maybe_drop_public(rename_map, ast, false),
    do: Map.drop(rename_map, public_def_names(ast))

  defp public_def_names(ast) do
    {_ast, names} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:def, _, [{:when, _, [{name, _, _}, _]}, _]} = node, acc when is_atom(name) ->
          {node, MapSet.put(acc, name)}

        {:def, _, [{name, _, args}, _]} = node, acc
        when is_atom(name) and is_list(args) and name != :when ->
          {node, MapSet.put(acc, name)}

        node, acc ->
          {node, acc}
      end)

    names
  end

  # Second pass: rename every bare occurrence of old names
  # This covers: def heads, calls, recursive calls, captures, @spec, etc.
  defp apply_renames({fn_name, meta, args} = node, rename_map) when is_atom(fn_name) do
    case Map.get(rename_map, fn_name) do
      nil -> node
      new_name -> {new_name, meta, args}
    end
  end

  defp apply_renames(node, _rename_map), do: node

  # ── Check helpers ────────────────────────────────────────────────────

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
