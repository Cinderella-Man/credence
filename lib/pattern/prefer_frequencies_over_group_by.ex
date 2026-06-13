defmodule Credence.Pattern.PreferFrequenciesOverGroupBy do
  @moduledoc """
  Detects `Enum.group_by/1` with an identity function piped into `Enum.map/2`
  that counts group lengths, then piped into `Enum.count/2` with a `> 1`
  predicate — a manual "count duplicate occurrences" pattern that
  `Enum.frequencies/0` followed by `Enum.count/2` handles more idiomatically.

  ## Bad

      input
      |> String.graphemes()
      |> Enum.group_by(fn char -> char end)
      |> Enum.map(fn {_key, values} -> length(values) end)
      |> Enum.count(fn count -> count > 1 end)

  ## Good

      input
      |> String.graphemes()
      |> Enum.frequencies()
      |> Enum.count(fn {_char, count} -> count > 1 end)
  """

  use Credence.Pattern.Rule

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn node ->
      case fix_node(node) do
        {:ok, replacement} -> replacement
        :error -> node
      end
    end)
  end

  # ── detection ──────────────────────────────────────────────────────────

  defp check_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    if length(steps) >= 3 do
      [s1, s2, s3] = Enum.take(steps, -3)

      if identity_group_by?(s1) and map_to_length?(s2) and count_gt_one?(s3) do
        {{:., meta, _}, _, _} = s1
        {:ok, build_issue(meta)}
      else
        :error
      end
    else
      :error
    end
  end

  defp check_node(_), do: :error

  # ── fix ────────────────────────────────────────────────────────────────

  defp fix_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    case find_pattern(steps) do
      {:ok, before, _group_by, _map, _count, after_steps} ->
        frequencies_step =
          {{:., [], [{:__aliases__, [], [:Enum]}, :frequencies]}, [], []}

        updated_count = build_updated_count()

        new_steps = before ++ [frequencies_step, updated_count] ++ after_steps

        replacement =
          case new_steps do
            [single] -> single
            _ -> rebuild_pipeline(new_steps)
          end

        {:ok, replacement}

      _ ->
        :error
    end
  end

  defp fix_node(_), do: :error

  # ── pattern matching helpers ───────────────────────────────────────────

  defp find_pattern(steps) do
    steps
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(fn {[s1, s2, s3], idx} ->
      if identity_group_by?(s1) and map_to_length?(s2) and count_gt_one?(s3) do
        before = Enum.take(steps, idx)
        after_steps = Enum.drop(steps, idx + 3)
        {:ok, before, s1, s2, s3, after_steps}
      end
    end)
  end

  # Enum.group_by(fn x -> x end) — piped, single arg (the key_fn)
  defp identity_group_by?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :group_by]}, _, [fn_ast]}
       ),
       do: identity_fn?(fn_ast)

  defp identity_group_by?(_), do: false

  # fn x -> x end
  defp identity_fn?({:fn, _, [{:->, _, [[{var, _, nil}], {var2, _, nil}]}]})
       when is_atom(var) and is_atom(var2) and var == var2,
       do: true

  # &(&1) — Sourceror wraps captures in an extra {:&, _, [...]} layer
  defp identity_fn?({:&, _, [{:&, _, [1]}]}), do: true
  defp identity_fn?({:&, _, [{:&, _, [{:__block__, _, [1]}]}]}), do: true

  defp identity_fn?(_), do: false

  # Enum.map(fn {_key, values} -> length(values) end) — piped, single arg
  defp map_to_length?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [fn_ast]}
       ),
       do: length_group_fn?(fn_ast)

  defp map_to_length?(_), do: false

  # Sourceror wraps 2-tuple patterns in {:__block__, _, [tuple]}
  defp length_group_fn?(
         {:fn, _,
          [
            {:->, _,
             [
               [{:__block__, _, [{_first, {v, _, nil}}]}],
               {:length, _, [{v, _, nil}]}
             ]}
          ]}
       )
       when is_atom(v),
       do: true

  # Without __block__ wrapper
  defp length_group_fn?(
         {:fn, _,
          [
            {:->, _,
             [
               [{_first, {v, _, nil}}],
               {:length, _, [{v, _, nil}]}
             ]}
          ]}
       )
       when is_atom(v),
       do: true

  defp length_group_fn?(_), do: false

  # Enum.count(fn count -> count > 1 end) — piped, single arg
  defp count_gt_one?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [fn_ast]}
       ),
       do: gt_one_fn?(fn_ast)

  defp count_gt_one?(_), do: false

  defp gt_one_fn?(
         {:fn, _,
          [
            {:->, _,
             [
               [{var, _, nil}],
               {:>, _, [{var, _, nil}, {:__block__, _, [1]}]}
             ]}
          ]}
       )
       when is_atom(var),
       do: true

  defp gt_one_fn?(_), do: false

  # ── build replacement ──────────────────────────────────────────────────

  # Enum.count(fn {_char, count} -> count > 1 end)
  defp build_updated_count do
    new_fn =
      {:fn, [],
       [
         {:->, [],
          [
            [{:__block__, [], [{{:_char, [], nil}, {:count, [], nil}}]}],
            {:>, [], [{:count, [], nil}, {:__block__, [], [1]}]}
          ]}
       ]}

    {{:., [], [{:__aliases__, [], [:Enum]}, :count]}, [], [new_fn]}
  end

  # ── pipeline helpers ───────────────────────────────────────────────────

  defp flatten_pipeline({:|>, _, [left, right]}),
    do: flatten_pipeline(left) ++ [right]

  defp flatten_pipeline(expr), do: [expr]

  defp rebuild_pipeline([first | rest]) do
    Enum.reduce(rest, first, fn step, acc ->
      {:|>, [], [acc, step]}
    end)
  end

  defp build_issue(meta) do
    %Credence.Issue{
      rule: :prefer_frequencies_over_group_by,
      message:
        "`Enum.group_by/1` with identity function piped into `Enum.map/2` counting group " <>
          "lengths and `Enum.count/2` is a manual frequency-count pattern. Use " <>
          "`Enum.frequencies/0` instead — it is clearer, avoids intermediate per-element " <>
          "lists, and is optimized internally.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
