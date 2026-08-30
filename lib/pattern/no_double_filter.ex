defmodule Credence.Pattern.NoDoubleFilter do
  @moduledoc """
  Detects two **adjacent** `Enum.filter/2` calls on the **same** variable
  whose predicates are exact logical complements, which can be replaced
  with a single `Enum.split_with/2` pass.

  ## Bad

      non_neg = Enum.filter(numbers, &(&1 >= 0))
      neg = Enum.filter(numbers, &(&1 < 0))

  ## Good

      {non_neg, neg} = Enum.split_with(numbers, &(&1 >= 0))

  ### Why so narrow

  `Enum.split_with/2` derives the second list as the elements that *fail*
  the single predicate — so the rewrite is only behaviour-preserving when
  the second filter's predicate is the exact complement of the first's.
  Determining that for arbitrary predicates is undecidable, so this rule
  fires only on the shape it can prove: both predicates are captures
  `&(&1 <op> <operand>)` over the same simple `<operand>` (a literal or a
  bare variable, never a call — to rule out side-effecting double
  evaluation), with `<op>` pairs that partition every term under Elixir's
  total ordering:

    * `>=` / `<`
    * `>`  / `<=`
    * `==` / `!=`

  The two assignments must be adjacent (no statement between them) and bind
  distinct variables.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.SourceMask

  # Operator pairs that are exact complements for the *same* operand over
  # Elixir's total term ordering. `>=`/`<`, `>`/`<=` cover the whole order;
  # `==`/`!=` partition by structural equality. None of these ever raise.
  @complement %{
    :>= => :<,
    :< => :>=,
    :> => :<=,
    :<= => :>,
    :== => :!=,
    :!= => :==
  }

  @impl true
  def check(ast, _opts) do
    ast
    |> collect_pairs()
    |> Enum.map(fn %{v1: v1, v2: v2, src: {src_name, _, _}, line: line} ->
      %Issue{
        rule: :no_double_filter,
        message:
          "`#{v1}` and `#{v2}` are two complementary `Enum.filter/2` calls on " <>
            "`#{src_name}`. Use a single `Enum.split_with/2` pass instead.",
        meta: %{line: line}
      }
    end)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)

    ast
    |> collect_pairs()
    |> Enum.map(fn %{s1: s1, s2: s2, v1: v1, v2: v2, src: src, pred: pred} ->
      r1 = Sourceror.get_range(s1)
      r2 = Sourceror.get_range(s2)
      src_txt = slice(source, Sourceror.get_range(src))
      pred_txt = capture_slice(source, Sourceror.get_range(pred))

      %{
        range: %{start: r1.start, end: r2.end},
        change: "{#{v1}, #{v2}} = Enum.split_with(#{src_txt}, #{pred_txt})",
        preserve_indentation: false
      }
    end)
  end

  # Walks every block scope and scans its statement list for adjacent,
  # complementary filter pairs. Returns the full info each callback needs.
  defp collect_pairs(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {:__block__, _, statements} = node, acc when is_list(statements) ->
          {node, acc ++ scan(statements)}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  # Greedy, non-overlapping scan: on a match consume both statements and
  # continue after them, so three complementary filters in a row never emit
  # two overlapping patches.
  defp scan([s1, s2 | rest]) do
    case match_pair(s1, s2) do
      {:ok, info} -> [info | scan(rest)]
      :no -> scan([s2 | rest])
    end
  end

  defp scan(_), do: []

  defp match_pair(
         {:=, m1, [{v1, _, c1}, call1]} = s1,
         {:=, _m2, [{v2, _, c2}, call2]} = s2
       )
       when is_atom(v1) and is_atom(c1) and is_atom(v2) and is_atom(c2) and v1 != v2 do
    with {:ok, src1, pred1} <- filter_call(call1),
         {:ok, src2, pred2} <- filter_call(call2),
         true <- same_var?(src1, src2),
         {op1, operand1} <- pred_parts(pred1),
         {op2, operand2} <- pred_parts(pred2),
         true <- Map.get(@complement, op1) == op2,
         true <- simple_operand?(operand1),
         false <- same_var?({v1, [], c1}, src1),
         false <- same_var?({v1, [], c1}, operand1),
         true <- same_operand?(operand1, operand2) do
      {:ok, %{s1: s1, s2: s2, v1: v1, v2: v2, src: src1, pred: pred1, line: m1[:line]}}
    else
      _ -> :no
    end
  end

  defp match_pair(_, _), do: :no

  defp filter_call({{:., _, [{:__aliases__, _, [:Enum]}, :filter]}, _, [src, pred]}),
    do: {:ok, src, pred}

  defp filter_call(_), do: :error

  defp same_var?({n, _, c}, {n, _, c}) when is_atom(n) and is_atom(c), do: true
  defp same_var?(_, _), do: false

  # Captures of the form `&(&1 <op> operand)` with a recognized operator.
  defp pred_parts({:&, _, [{op, _, [arg, operand]}]}) when is_map_key(@complement, op) do
    if capture_arg1?(arg), do: {op, operand}, else: :error
  end

  defp pred_parts(_), do: :error

  defp capture_arg1?({:&, _, [1]}), do: true
  defp capture_arg1?({:&, _, [{:__block__, _, [1]}]}), do: true
  defp capture_arg1?(_), do: false

  # The operand must be a plain literal or a bare variable — never a call —
  # so the two filters and the single split_with evaluate it identically and
  # without re-running side effects.
  defp simple_operand?({:__block__, _, [lit]})
       when is_number(lit) or is_binary(lit) or is_atom(lit),
       do: true

  defp simple_operand?(lit) when is_number(lit) or is_binary(lit) or is_atom(lit), do: true
  defp simple_operand?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp simple_operand?(_), do: false

  defp same_operand?(o1, o2), do: strip_meta(o1) == strip_meta(o2)

  defp strip_meta(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} when is_list(meta) -> {form, [], args}
      other -> other
    end)
  end

  defp slice(source, %Sourceror.Range{start: s, end: e}) do
    {:ok, start_offset} = SourceMask.byte_offset(source, s[:line], s[:column])
    {:ok, end_offset} = SourceMask.byte_offset(source, e[:line], e[:column])
    binary_part(source, start_offset, end_offset - start_offset)
  end

  defp capture_slice(source, %Sourceror.Range{start: s}) do
    {:ok, start_offset} = SourceMask.byte_offset(source, s[:line], s[:column])
    shadow = SourceMask.mask(source)
    end_offset = capture_end(shadow, start_offset + 1, 0)
    binary_part(source, start_offset, end_offset - start_offset)
  end

  defp capture_end(shadow, offset, depth) do
    case :binary.at(shadow, offset) do
      ?( -> capture_end(shadow, offset + 1, depth + 1)
      ?) when depth == 1 -> offset + 1
      ?) -> capture_end(shadow, offset + 1, depth - 1)
      _ -> capture_end(shadow, offset + 1, depth)
    end
  end
end
