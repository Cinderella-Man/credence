defmodule Credence.AttributeProbe do
  @moduledoc """
  Probes every fixable rule for module-attribute MANGLING: a fix that rewrites a
  function clause head can mistake a `@some_attr` pattern for an unused variable
  and underscore it into `@_some_attr` — an undefined attribute (evaluates to
  `nil`), silently breaking the match. (Observed in `prefer_guard_over_if`'s
  `underscore_unused_params`.)

  Rather than hope the corpus happens to place an attribute beside each rule's
  trigger, this harvests each rule's OWN fix-test fixtures (guaranteed firing
  inputs), injects a `@probe_attr` into mangling-prone positions, applies the
  fix, and flags any rule that introduces an `@_`-prefixed attribute the input
  never had.
  """

  @probe {:@, [], [{:probe_attr, [], nil}]}

  @doc "Every `{rule_module, fixture_code}` pair across all `*_fix_test.exs`."
  def fixtures do
    Path.wildcard(Path.join([__DIR__, "..", "pattern", "*_fix_test.exs"]))
    |> Enum.flat_map(fn file ->
      ast = Code.string_to_quoted!(File.read!(file))

      case rule_module(ast) do
        nil -> []
        rule -> Enum.map(codes(ast), &{rule, &1})
      end
    end)
  end

  defp rule_module(ast) do
    {_, found} =
      Macro.prewalk(ast, nil, fn
        {:fix, _, [{:__aliases__, _, parts} | _]} = node, nil -> {node, parts}
        node, acc -> {node, acc}
      end)

    case found do
      nil -> nil
      parts -> Module.concat([Credence, Pattern | List.delete(parts, :Pattern)])
    end
  end

  defp codes(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        {:=, _, [{:code, _, ctx}, bin]} = node, acc when is_atom(ctx) and is_binary(bin) ->
          {node, [bin | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  @doc "Attribute-injected AST variants of one fixture (head-param + per-variable)."
  def variants(code) do
    case Code.string_to_quoted(code) do
      {:ok, ast} -> [head_inject(ast) | var_injects(ast)] |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  # prepend `@probe_attr` as the first parameter of the first def/defp head
  defp head_inject(ast) do
    {new, changed} =
      Macro.prewalk(ast, false, fn
        {d, m, [head, body]}, false when d in [:def, :defp] ->
          {{d, m, [prepend_param(head), body]}, true}

        node, acc ->
          {node, acc}
      end)

    if changed, do: new, else: nil
  end

  defp prepend_param({:when, m, [call, g]}), do: {:when, m, [prepend_param(call), g]}
  defp prepend_param({name, m, args}) when is_list(args), do: {name, m, [@probe | args]}
  defp prepend_param(other), do: other

  # replace every reference to a free variable with `@probe_attr` (one variant each)
  defp var_injects(ast) do
    for v <- free_vars(ast) do
      Macro.prewalk(ast, fn
        {^v, _, ctx} when is_atom(ctx) or is_nil(ctx) -> @probe
        other -> other
      end)
    end
  end

  defp free_vars(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        {v, _, ctx} = node, acc when is_atom(v) and (is_atom(ctx) or is_nil(ctx)) ->
          s = Atom.to_string(v)

          if String.starts_with?(s, "_") or v in [nil, true, false],
            do: {node, acc},
            else: {node, [v | acc]}

        node, acc ->
          {node, acc}
      end)

    acc |> Enum.uniq() |> Enum.take(4)
  end

  defp mangled_attrs(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        {:@, _, [{name, _, ctx}]} = node, acc
        when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) ->
          {node, [name | acc]}

        node, acc ->
          {node, acc}
      end)

    acc |> Enum.filter(&String.starts_with?(Atom.to_string(&1), "_")) |> MapSet.new()
  end

  defp wrap(variant_ast) do
    "defmodule CredenceAttrProbe do\n  @probe_attr 1\n" <> Macro.to_string(variant_ast) <> "\nend"
  end

  @doc """
  Apply `rule`'s fix to an attribute-injected variant. Returns `:no_fire` (fix
  was a no-op), `:ok` (fired, attribute preserved), or `{:mangled, names, fixed}`.
  """
  def check(rule, variant_ast) do
    src = wrap(variant_ast)

    fixed =
      try do
        Credence.RuleHelpers.apply_rule_fix(rule, src)
      rescue
        _ -> src
      end

    cond do
      fixed == src ->
        :no_fire

      true ->
        with {:ok, fa} <- Code.string_to_quoted(fixed),
             {:ok, sa} <- Code.string_to_quoted(src) do
          new = MapSet.difference(mangled_attrs(fa), mangled_attrs(sa))
          if MapSet.size(new) > 0, do: {:mangled, MapSet.to_list(new), fixed}, else: :ok
        else
          _ -> :ok
        end
    end
  end

  @doc "Run the probe over every rule. Returns `{mangling, coverage}`."
  def run do
    results =
      for {rule, code} <- fixtures(), variant <- variants(code) do
        {rule, check(rule, variant)}
      end

    mangling =
      results
      |> Enum.flat_map(fn
        {rule, {:mangled, names, fixed}} -> [{rule, names, fixed}]
        _ -> []
      end)

    coverage = %{
      variants: length(results),
      fired: Enum.count(results, fn {_, r} -> r != :no_fire end),
      rules: results |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length()
    }

    {mangling, coverage}
  end
end
