defmodule Credence.Pattern.HallucinatedGuard do
  @moduledoc """
  Fixes calls to guard functions that don't exist in Elixir.

  LLMs sometimes hallucinate guard names from Erlang typespecs or other
  languages. This rule detects known hallucinated guards and replaces
  them with their correct Elixir equivalents.

  ## Replacements

      is_pos_integer(x)      →  is_integer(x) and x > 0
      is_non_neg_integer(x)  →  is_integer(x) and x >= 0
      is_neg_integer(x)      →  is_integer(x) and x < 0
      is_non_pos_integer(x)  →  is_integer(x) and x <= 0

  ## Bad

      defmodule MHG do
        def valid?(x), do: is_pos_integer(x)
      end

  ## Good

      defmodule MHG do
        def valid?(x), do: is_integer(x) and x > 0
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @hallucinated_guards %{
    is_pos_integer: {:>, 0},
    is_non_neg_integer: {:>=, 0},
    is_neg_integer: {:<, 0},
    is_non_pos_integer: {:<=, 0}
  }

  @guard_names Map.keys(@hallucinated_guards)

  @impl true
  def check(ast, _opts) do
    protected = protected_calls(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {name, meta, [_arg]} = node, issues when is_atom(name) ->
          if name in @guard_names and call_key(name, meta) not in protected do
            {node, [build_issue(name, meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    do_fix(ast)
  end

  defp do_fix(ast) do
    protected = protected_calls(ast)

    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {name, meta, [arg]} = node when is_atom(name) ->
        case Map.get(@hallucinated_guards, name) do
          {op, bound} ->
            if call_key(name, meta) in protected do
              node
            else
              {:and, [], [{:is_integer, [], [arg]}, {op, [], [arg, bound]}]}
            end

          nil ->
            node
        end

      node ->
        node
    end)
  end

  # Record calls whose name can resolve in their own lexical module. This must
  # be module-local: a directive or definition in a sibling module has no effect.
  defp protected_calls(ast) do
    root_names = protected_names(ast)

    {_ast, {_scopes, protected}} =
      Macro.traverse(
        ast,
        {[root_names], MapSet.new()},
        fn
          {:defmodule, _, args} = node, {scopes, protected} ->
            {node, {[protected_names(module_body(args)) | scopes], protected}}

          {name, meta, [_arg]} = node, {[names | _] = scopes, protected}
          when is_atom(name) ->
            protected =
              if name in names, do: MapSet.put(protected, call_key(name, meta)), else: protected

            {node, {scopes, protected}}

          node, acc ->
            {node, acc}
        end,
        fn
          {:defmodule, _, _args} = node, {[_module | scopes], protected} ->
            {node, {scopes, protected}}

          node, acc ->
            {node, acc}
        end
      )

    protected
  end

  defp protected_names(ast) do
    {_ast, {_nested, names}} =
      Macro.traverse(
        ast,
        {0, MapSet.new()},
        fn
          {:defmodule, _, _} = node, {nested, names} ->
            {node, {nested + 1, names}}

          {definition, _, [head | _]} = node, {0, names}
          when definition in [:def, :defp, :defguard, :defguardp] ->
            names =
              case guard_head(head) do
                {name, 1} when name in @guard_names -> MapSet.put(names, name)
                _ -> names
              end

            {node, {0, names}}

          {:use, _, [_ | _]} = node, {0, _names} ->
            {node, {0, MapSet.new(@guard_names)}}

          {:import, _, args} = node, {0, names} ->
            {node, {0, MapSet.union(names, imported_names(args))}}

          node, acc ->
            {node, acc}
        end,
        fn
          {:defmodule, _, _} = node, {nested, names} -> {node, {nested - 1, names}}
          node, acc -> {node, acc}
        end
      )

    names
  end

  defp imported_names([_module, opts]) when is_list(opts) do
    cond do
      only = ast_keyword_get(opts, :only) ->
        MapSet.new(
          for entry <- ast_list(only),
              import_entry(entry) in Enum.map(@guard_names, &{&1, 1}),
              do: elem(import_entry(entry), 0)
        )

      except = ast_keyword_get(opts, :except) ->
        excluded = for entry <- ast_list(except), {name, 1} = import_entry(entry), do: name
        MapSet.new(@guard_names -- excluded)

      true ->
        MapSet.new(@guard_names)
    end
  end

  defp imported_names([_module]), do: MapSet.new(@guard_names)

  defp ast_keyword_get(keywords, wanted) do
    Enum.find_value(keywords, fn
      {^wanted, value} -> value
      {{:__block__, _, [^wanted]}, value} -> value
      _ -> nil
    end)
  end

  defp import_entry({name, arity}) when is_atom(name) and is_integer(arity), do: {name, arity}

  defp import_entry({{:__block__, _, [name]}, {:__block__, _, [arity]}}),
    do: {name, arity}

  defp ast_list({:__block__, _, [list]}) when is_list(list), do: list
  defp ast_list(list) when is_list(list), do: list

  defp module_body([_name, keywords]) do
    Enum.find_value(keywords, fn
      {:do, body} -> body
      {{:__block__, _, [:do]}, body} -> body
      _ -> nil
    end)
  end

  # Sourceror's patch walk normalizes column metadata, while line metadata is
  # stable between the parsed tree and the patch callback.
  defp call_key(name, meta), do: {name, Keyword.get(meta, :line)}

  # The `name/arity` a `defguard(p)` head defines, stripping the `when` guard.
  defp guard_head({:when, _, [call, _guard]}), do: guard_head(call)
  defp guard_head({name, _, args}) when is_atom(name) and is_list(args), do: {name, length(args)}
  defp guard_head(_), do: nil

  defp build_issue(name, meta) do
    %Issue{
      rule: :hallucinated_guard,
      message:
        "`#{name}/1` does not exist in Elixir. " <>
          "Replace with the equivalent guard expression.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
