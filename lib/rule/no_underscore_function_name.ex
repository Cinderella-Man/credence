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
  a single underscore.  Names starting with double underscores `__`)
  are excluded — those are legitimate Elixir/Erlang callbacks such as
  `__using__/1`, `__before_compile__/1`, and `__info__/1`.

  ## Auto-fix

  Renames the function definition and all call sites from `_name` to
  `do_name` throughout the module.
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, {_names, issues}} =
      Macro.postwalk(ast, {%{}, []}, fn
        {def_type, meta, [{:when, _, [{fn_name, _, args}, _guard]}, _body]} = node,
        {names, issues}
        when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) ->
          if underscore_prefixed?(fn_name) and not Map.has_key?(names, fn_name) do
            {node,
             {Map.put(names, fn_name, true),
              [build_issue(def_type, fn_name, length(args), meta) | issues]}}
          else
            {node, {names, issues}}
          end

        {def_type, meta, [{fn_name, _, args}, _body]} = node, {names, issues}
        when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) ->
          if underscore_prefixed?(fn_name) and not Map.has_key?(names, fn_name) do
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

  @impl true
  def fix(source, _opts) do
    ast = Sourceror.parse_string!(source)

    {_ast, names} =
      Macro.postwalk(ast, MapSet.new(), fn
        {def_type, _meta, [{:when, _, [{fn_name, _, args}, _guard]}, _body]} = node, names
        when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) ->
          if underscore_prefixed?(fn_name),
            do: {node, MapSet.put(names, fn_name)},
            else: {node, names}

        {def_type, _meta, [{fn_name, _, args}, _body]} = node, names
        when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) ->
          if underscore_prefixed?(fn_name),
            do: {node, MapSet.put(names, fn_name)},
            else: {node, names}

        node, names ->
          {node, names}
      end)

    if MapSet.size(names) == 0 do
      source
    else
      name_map =
        for name <- names, into: %{} do
          {name, suggested_name(name)}
        end

      renamed =
        Macro.postwalk(ast, fn
          {def_type, meta, [{:when, wm, [{fn_name, fm, args}, guard]}, body]} = node
          when def_type in [:def, :defp] ->
            case name_map do
              %{^fn_name => new_name} ->
                fm_new = Keyword.put(fm, :token, Atom.to_string(new_name))
                {def_type, meta, [{:when, wm, [{new_name, fm_new, args}, guard]}, body]}

              _ ->
                node
            end

          {def_type, meta, [{fn_name, fm, args}, body]} = node
          when def_type in [:def, :defp] ->
            case name_map do
              %{^fn_name => new_name} ->
                fm_new = Keyword.put(fm, :token, Atom.to_string(new_name))
                {def_type, meta, [{new_name, fm_new, args}, body]}

              _ ->
                node
            end

          {fn_name, meta, args} when is_atom(fn_name) and is_list(args) ->
            case name_map do
              %{^fn_name => new_name} ->
                meta_new = Keyword.put(meta, :token, Atom.to_string(new_name))
                {new_name, meta_new, args}

              _ ->
                {fn_name, meta, args}
            end

          atom when is_atom(atom) ->
            case name_map do
              %{^atom => new_name} -> new_name
              _ -> atom
            end

          node ->
            node
        end)

      renamed
      |> Sourceror.to_string()
    end
  end

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
