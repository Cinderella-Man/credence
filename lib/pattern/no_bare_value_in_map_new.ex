defmodule Credence.Pattern.NoBareValueInMapNew do
  @moduledoc """
  Repairs `Map.new/2` whose mapper returns a bare (non-`{key, value}`) value.

  `Map.new(enum, fun)` requires `fun` to return a `{key, value}` tuple for every
  element — the results are handed to `:maps.from_list/1`. LLMs frequently write
  a mapper that returns a bare value instead, e.g. building an adjacency list:

      Map.new(0..(n - 1), fn _k -> [] end)

  This compiles but raises `ArgumentError` (`:maps.from_list/1`) on **every**
  non-empty input — there is no value of `enum` for which it produces a map. The
  intended map is `%{element => value}`, so the repair pairs the element (the
  mapper's parameter) with the value:

  ## Bad

      Map.new(0..(n - 1), fn _k -> [] end)
      Map.new(items, fn item -> 0 end)

  ## Good

      Map.new(0..(n - 1), fn k -> {k, []} end)
      Map.new(items, fn item -> {item, 0} end)

  ## Repair, not a rewrite

  This is a `mark_equivalence_repair` rule: it only matches a mapper whose body
  is a literal that can never be a 2-tuple (a list, number, string, atom, map, or
  a tuple of arity ≠ 2), so the original crashes on every input and there is no
  behaviour to preserve. A mapper that already returns a tuple, or returns a
  call/variable that *might* be a tuple, is never touched — so the rule cannot
  fire on working code.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect(node) do
          {:ok, _key, _body} -> {node, [build_issue(node) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect(node) do
          {:ok, key_var, body} -> {node, [patch(node, key_var, body) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(patches)
  end

  # Map.new(enum, fn <single bare var> -> <non-pair literal> end)
  defp detect(
         {{:., _, [{:__aliases__, _, [:Map]}, :new]}, _,
          [_enum, {:fn, _, [{:->, _, [[param], body]}]}]} = _node
       ) do
    with {:ok, param_name} <- bare_param(param),
         true <- definitely_not_pair?(body) do
      {:ok, key_name(param_name), body}
    else
      _ -> :no
    end
  end

  defp detect(_), do: :no

  defp bare_param({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: {:ok, name}
  defp bare_param(_), do: :error

  # The key reuses the mapper's parameter, with any leading underscore stripped
  # (the param was almost always `_k`-style precisely because the author forgot
  # to use it as the key). A bare `_` becomes `key`.
  defp key_name(name) do
    case Atom.to_string(name) |> String.trim_leading("_") do
      "" -> :key
      stripped -> String.to_atom(stripped)
    end
  end

  # A literal that can NEVER be a 2-tuple — so Map.new is guaranteed to crash.
  # Sourceror wraps scalar literals in {:__block__, _, [literal]}.
  defp definitely_not_pair?({:__block__, _, [inner]}), do: definitely_not_pair?(inner)
  # List literal `[...]`
  defp definitely_not_pair?(list) when is_list(list), do: true
  # Scalars: integer, float, atom (incl nil/true/false), string is a binary below
  defp definitely_not_pair?(lit) when is_integer(lit) or is_float(lit) or is_atom(lit), do: true
  defp definitely_not_pair?(lit) when is_binary(lit), do: true
  # Map literal `%{...}`
  defp definitely_not_pair?({:%{}, _, _}), do: true
  # String/charlist literal nodes built by Sourceror sometimes appear as binaries
  # above; an interpolated string is a `<<>>` node — also never a pair.
  defp definitely_not_pair?({:<<>>, _, _}), do: true
  # A tuple literal: only arity != 2 qualifies (a 2-tuple IS a valid pair).
  defp definitely_not_pair?({:{}, _, elems}) when length(elems) != 2, do: true
  # A raw 2-element AST tuple `{a, b}` is a valid pair — never flag it.
  defp definitely_not_pair?(_), do: false

  defp patch(node, key_var, body) do
    {_call, _meta, [enum, _fn]} = node
    enum_str = Sourceror.to_string(enum)
    body_str = Sourceror.to_string(body)
    key = Atom.to_string(key_var)

    %{
      range: Sourceror.get_range(node),
      change: "Map.new(#{enum_str}, fn #{key} -> {#{key}, #{body_str}} end)"
    }
  end

  defp build_issue(node) do
    {_, meta, _} = node

    %Issue{
      rule: :no_bare_value_in_map_new,
      message:
        "`Map.new/2`'s mapper must return a `{key, value}` tuple — a bare value " <>
          "raises ArgumentError. Pair the element with the value: `fn k -> {k, value} end`.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
