defmodule Credence.Pattern.NoUnusedComputation do
  @moduledoc """
  Removes a dead `_`-prefixed assignment of a **total, provably-typed** call.

  An assignment like `_n = length(chars)` computes a value that is discarded
  (the `_` prefix signals intent). Removing it looks safe — but a "pure"
  function is not necessarily **total**: `length/1` raises on a non-list,
  `String.length/1` on a non-binary, `abs/1` on a non-number. Deleting a
  discarded call that *would have raised* on some input changes behaviour
  (the original crashes; the rewrite does not). So we only remove the call
  when both:

    * the function is **total given its argument type** (`length` on any list,
      `String.graphemes` on any binary, `abs` on any number, …) — partial
      functions like `div`/`rem` (÷0), `hd`/`tl` (`[]`), `elem` (index),
      `String.to_integer` (non-numeric) are never removed; and
    * the argument is **provably that type** — a literal, a `++`/`<>`/`%{}`
      expression, a type-returning call (`String.graphemes`, `Enum.map`, …), or
      a variable bound earlier in the same block to such an expression.

  A bare variable of unknown type, or a partial function, is left untouched.
  The **last** expression of a block is never removed (it is the block's value).

  ## Bad

      chars = String.graphemes(s)
      _n = length(chars)
      Enum.with_index(chars)

  ## Good

      chars = String.graphemes(s)
      Enum.with_index(chars)
  """

  use Credence.Pattern.Rule
  # CONSERVATIVE. The rule rewrites no construct — it deletes a whole non-last
  # `_v = <total call>` statement from a `__block__` — but a block of statements
  # with `=` bindings is exactly what a `defn` body is, so the matcher is NOT
  # structurally out of reach of nx_defn (Ash expr and Ecto query expressions
  # admit neither blocks nor `=`, so those two are settled). Inside a defn, `x =
  # a + b` types `x` as :number via expr_type's `[:+, :-, :*, :/]` clause, and
  # `_n = abs(x)` is then deletable — dropping an `abs`/`+` node from what Nx
  # traces. I believe the removed node is dead in the Nx expression graph (the
  # graph is reachability from the returned value, and every whitelisted call is
  # pure), but that is a semantic argument about Nx, not a structural one about
  # the matcher. Declared rather than allowlisted because the deciding check
  # needs the DSL itself as a dependency, which this repo does not carry;
  # declaring costs a missed fix inside the block, allowlisting would cost a
  # wrong rewrite.
  @impl true
  def unsafe_in_dsl, do: [:nx_defn]
  alias Credence.Issue

  # `{module_or_nil, fun} => required arg type`. TOTAL when the argument has that
  # type, so deleting a discarded call cannot drop a crash. Functions partial
  # even on the right type (div/rem ÷0, hd/tl [], elem index, Enum.sum non-number,
  # Enum.min/max [], String.to_integer non-numeric) are deliberately excluded.
  @total_given_type %{
    {nil, :length} => :list,
    {nil, :byte_size} => :binary,
    {nil, :bit_size} => :binary,
    {nil, :tuple_size} => :tuple,
    {nil, :map_size} => :map,
    {nil, :abs} => :number,
    {nil, :ceil} => :number,
    {nil, :floor} => :number,
    {nil, :round} => :number,
    {nil, :trunc} => :number,
    {String, :length} => :binary,
    {String, :graphemes} => :binary,
    {String, :codepoints} => :binary,
    {String, :reverse} => :binary,
    {String, :upcase} => :binary,
    {String, :downcase} => :binary,
    {String, :trim} => :binary,
    {String, :to_charlist} => :binary,
    {Enum, :reverse} => :list,
    {Enum, :count} => :list,
    {Enum, :uniq} => :list,
    {Enum, :frequencies} => :list,
    {Enum, :with_index} => :list,
    {Enum, :to_list} => :list,
    {Map, :keys} => :map,
    {Map, :values} => :map,
    {Map, :to_list} => :map,
    {Map, :size} => :map,
    {Tuple, :to_list} => :tuple
  }

  # `{module_or_nil, fun} => type the call RESULT has` — used to infer a binding's
  # type so `chars = String.graphemes(s)` marks `chars` a list.
  @returns %{
    {Enum, :map} => :list,
    {Enum, :filter} => :list,
    {Enum, :reject} => :list,
    {Enum, :sort} => :list,
    {Enum, :sort_by} => :list,
    {Enum, :uniq} => :list,
    {Enum, :uniq_by} => :list,
    {Enum, :reverse} => :list,
    {Enum, :take} => :list,
    {Enum, :drop} => :list,
    {Enum, :to_list} => :list,
    {Enum, :with_index} => :list,
    {Enum, :flat_map} => :list,
    {Enum, :concat} => :list,
    {Enum, :dedup} => :list,
    {Enum, :chunk_every} => :list,
    {Map, :keys} => :list,
    {Map, :values} => :list,
    {String, :graphemes} => :list,
    {String, :codepoints} => :list,
    {String, :split} => :list,
    {String, :to_charlist} => :list,
    {List, :flatten} => :list,
    {List, :wrap} => :list,
    {List, :duplicate} => :list,
    {String, :upcase} => :binary,
    {String, :downcase} => :binary,
    {String, :trim} => :binary,
    {String, :trim_leading} => :binary,
    {String, :trim_trailing} => :binary,
    {String, :reverse} => :binary,
    {String, :slice} => :binary,
    {String, :replace} => :binary,
    {String, :capitalize} => :binary,
    {String, :duplicate} => :binary,
    {Integer, :to_string} => :binary,
    {nil, :abs} => :number,
    {nil, :ceil} => :number,
    {nil, :floor} => :number,
    {nil, :round} => :number,
    {nil, :trunc} => :number,
    {nil, :length} => :number,
    {nil, :byte_size} => :number,
    {nil, :tuple_size} => :number,
    {nil, :map_size} => :number,
    {Enum, :count} => :number,
    {Enum, :sum} => :number,
    {Enum, :product} => :number,
    {String, :length} => :number,
    {Map, :size} => :number,
    {Map, :new} => :map,
    {Map, :put} => :map,
    {Map, :merge} => :map,
    {Map, :delete} => :map,
    {Enum, :frequencies} => :map,
    {Enum, :group_by} => :map
  }

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _, stmts} = node, acc when is_list(stmts) ->
          {node, Enum.map(deletable(stmts), &issue_for/1) ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source) || Sourceror.to_string(ast)

    Credence.RuleHelpers.patches_from_ast_transform(ast, source, fn ast ->
      Macro.prewalk(ast, fn
        {:__block__, meta, stmts} = node when is_list(stmts) ->
          case deletable(stmts) do
            [] -> node
            dead -> {:__block__, meta, stmts -- dead}
          end

        node ->
          node
      end)
    end)
  end

  # The non-last statements that are dead discarded computations, threading a
  # `var => type` map built from preceding bindings.
  defp deletable(stmts) when length(stmts) <= 1, do: []

  defp deletable(stmts) do
    {non_last, _last} = Enum.split(stmts, length(stmts) - 1)

    {dead, _bindings} =
      Enum.reduce(non_last, {[], %{}}, fn stmt, {dead, bindings} ->
        cond do
          dead_computation?(stmt, bindings) -> {[stmt | dead], bindings}
          (b = binding(stmt, bindings)) != nil -> {dead, b}
          true -> {dead, bindings}
        end
      end)

    Enum.reverse(dead)
  end

  # `_v = func(arg)` where func is total-given-type T and arg is provably type T.
  defp dead_computation?({:=, _, [lhs, rhs]}, bindings) do
    type = total_given_type_call(rhs)
    underscore_var?(lhs) and type != nil and arg_type_of(rhs, bindings) == type
  end

  defp dead_computation?(_, _), do: false

  # `var = <typed expr>` (non-underscore) → updated bindings, else nil.
  defp binding({:=, _, [{name, _, ctx}, rhs]}, bindings)
       when is_atom(name) and is_atom(ctx) and name != :_ do
    case expr_type(rhs, bindings) do
      nil -> nil
      type -> Map.put(bindings, name, type)
    end
  end

  defp binding(_, _), do: nil

  defp total_given_type_call({{:., _, [{:__aliases__, _, [mod]}, fun]}, _, [_ | _]}),
    do: Map.get(@total_given_type, {Module.concat([mod]), fun})

  defp total_given_type_call({fun, _, [_ | _]}) when is_atom(fun),
    do: Map.get(@total_given_type, {nil, fun})

  defp total_given_type_call(_), do: nil

  defp arg_type_of({{:., _, _}, _, [arg | _]}, bindings), do: expr_type(arg, bindings)
  defp arg_type_of({fun, _, [arg | _]}, bindings) when is_atom(fun), do: expr_type(arg, bindings)
  defp arg_type_of(_, _), do: nil

  defp expr_type({:__block__, _, [inner]}, b), do: expr_type(inner, b)
  defp expr_type(list, _b) when is_list(list), do: :list
  defp expr_type(bin, _b) when is_binary(bin), do: :binary
  defp expr_type(n, _b) when is_number(n), do: :number
  defp expr_type({:++, _, [_, _]}, _b), do: :list
  defp expr_type({:<>, _, [_, _]}, _b), do: :binary
  defp expr_type({:%{}, _, _}, _b), do: :map
  defp expr_type({:{}, _, _}, _b), do: :tuple
  defp expr_type({op, _, [_, _]}, _b) when op in [:+, :-, :*, :/], do: :number

  defp expr_type({{:., _, [{:__aliases__, _, [mod]}, fun]}, _, _}, _b),
    do: Map.get(@returns, {Module.concat([mod]), fun})

  defp expr_type({name, _, ctx}, b) when is_atom(name) and is_atom(ctx), do: Map.get(b, name)

  defp expr_type({fun, _, args}, _b) when is_atom(fun) and is_list(args),
    do: Map.get(@returns, {nil, fun})

  defp expr_type(_, _), do: nil

  defp underscore_var?({:_, _, ctx}) when is_atom(ctx), do: true

  defp underscore_var?({name, _, ctx}) when is_atom(name) and is_atom(ctx),
    do: name != :__block__ and String.starts_with?(Atom.to_string(name), "_")

  defp underscore_var?(_), do: false

  defp issue_for({:=, meta, [lhs, rhs]}) do
    %Issue{
      rule: :no_unused_computation,
      message: build_message(lhs, rhs),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_message(lhs, _rhs) do
    var =
      case lhs do
        {:_, _, _} -> "_"
        {name, _, _} -> Atom.to_string(name)
      end

    "Dead assignment to `#{var}` — its result is unused and the call is total on " <>
      "a provably-typed argument. Remove this line."
  end
end
