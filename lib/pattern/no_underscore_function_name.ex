defmodule Credence.Pattern.NoUnderscoreFunctionName do
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
  a single underscore.  Names starting with double underscores `__`)
  are excluded — those are legitimate Elixir/Erlang callbacks such as
  `__using__/1`, `__before_compile__/1`, and `__info__/1`.

  ## Auto-fix

  Renames the function definition and all call sites from `_name` to
  `do_name` throughout the module.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    captured = captured_arity_names(ast)

    {_ast, {_names, issues}} =
      Macro.postwalk(ast, {%{}, []}, fn
        {def_type, meta, [{:when, _, [{fn_name, _, args}, _guard]}, _body]} = node,
        {names, issues}
        when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) ->
          if flaggable?(fn_name, names, captured) do
            {node,
             {Map.put(names, fn_name, true),
              [build_issue(def_type, fn_name, length(args), meta) | issues]}}
          else
            {node, {names, issues}}
          end

        {def_type, meta, [{fn_name, _, args}, _body]} = node, {names, issues}
        when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) ->
          if flaggable?(fn_name, names, captured) do
            {node,
             {Map.put(names, fn_name, true),
              [build_issue(def_type, fn_name, length(args), meta) | issues]}}
          else
            {node, {names, issues}}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  defp flaggable?(fn_name, names, captured) do
    underscore_prefixed?(fn_name) and not Map.has_key?(names, fn_name) and
      not MapSet.member?(captured, fn_name)
  end

  @impl true
  def fix_patches(ast, _opts) do
    name_map = collect_renames(ast)

    if map_size(name_map) == 0 do
      []
    else
      RuleHelpers.patches_from_postwalk(ast, &rename_node(&1, name_map))
    end
  end

  defp collect_renames(ast) do
    captured = captured_arity_names(ast)

    {_ast, names} =
      Macro.postwalk(ast, MapSet.new(), fn
        {def_type, _meta, [{:when, _, [{fn_name, _, args}, _guard]}, _body]} = node, names
        when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) ->
          if underscore_prefixed?(fn_name) and not MapSet.member?(captured, fn_name),
            do: {node, MapSet.put(names, fn_name)},
            else: {node, names}

        {def_type, _meta, [{fn_name, _, args}, _body]} = node, names
        when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) ->
          if underscore_prefixed?(fn_name) and not MapSet.member?(captured, fn_name),
            do: {node, MapSet.put(names, fn_name)},
            else: {node, names}

        node, names ->
          {node, names}
      end)

    for name <- names, into: %{}, do: {name, suggested_name(name)}
  end

  # Names referenced by an arity-style capture `&name/arity`. The capture's
  # name node is `{name, _, nil}` — indistinguishable from a bare variable, so
  # `rename_node/2` (which only rewrites call nodes whose args are a list)
  # leaves it untouched. Renaming the `defp` while leaving `&_name/arity`
  # pointing at the old name produces a dangling reference that fails to
  # compile, so such names are excluded from both flagging and the fix.
  defp captured_arity_names(ast) do
    {_ast, names} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:&, _, [{:/, _, [{name, _, ctx}, _arity]}]} = node, acc
        when is_atom(name) and is_atom(ctx) ->
          {node, MapSet.put(acc, name)}

        node, acc ->
          {node, acc}
      end)

    names
  end

  defp rename_node({fn_name, meta, args}, name_map)
       when is_atom(fn_name) and is_list(args) do
    case name_map do
      %{^fn_name => new_name} ->
        meta_new = Keyword.put(meta, :token, Atom.to_string(new_name))
        {new_name, meta_new, args}

      _ ->
        {fn_name, meta, args}
    end
  end

  defp rename_node(atom, name_map) when is_atom(atom) do
    case name_map do
      %{^atom => new_name} -> new_name
      _ -> atom
    end
  end

  defp rename_node(node, _name_map), do: node

  defp underscore_prefixed?(name) do
    str = Atom.to_string(name)
    String.starts_with?(str, "_") and not String.starts_with?(str, "__")
  end

  defp suggested_name(fn_name) do
    fn_name
    |> Atom.to_string()
    |> String.replace_leading("_", "do_")
    |> String.to_atom()
  end

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
