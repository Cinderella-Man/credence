defmodule Credence.Pattern.PreferChunkOverIndexedReduce do
  @moduledoc """
  Detects `Enum.reduce/3` over `with_index()` that accesses neighbours
  via `Enum.at/2` with `index - 1` / `index + 1`, and rewrites it to
  use `Enum.chunk_every/4` with a step of 1 for sliding-window access.

  `Enum.chunk_every/4` with `step: 1` and `:discard` trimming gives
  direct access to `[prev, current, next]` triplets — more idiomatic
  than repeated indexed traversal.

  ## Bad

      list
      |> Stream.with_index()
      |> Enum.reduce(0, fn {value, index}, acc ->
        cond do
          index == 0 ->
            if value > Enum.at(list, 1), do: acc + 1, else: acc

          index == length(list) - 1 ->
            if value > Enum.at(list, index - 1), do: acc + 1, else: acc

          true ->
            left = Enum.at(list, index - 1)
            right = Enum.at(list, index + 1)
            if value > left and value > right, do: acc + 1, else: acc
        end
      end)

  ## Good

      middle =
        list
        |> Enum.chunk_every(3, 1, :discard)
        |> Enum.count(fn [left, candidate, right] ->
          candidate > left and candidate > right
        end)

      first =
        case list do
          [first, second | _] when first > second -> 1
          _ -> 0
        end

      last =
        case Enum.reverse(list) do
          [last, second_last | _] when last > second_last -> 1
          _ -> 0
        end

      first + middle + last
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Piped form: ... |> Stream/Enum.with_index() |> Enum.reduce(...)
        {:|>, pipe_meta, [left, reduce_call]} = node, issues ->
          if with_index_piped?(left) and indexed_reduce_with_neighbor_at?(reduce_call) do
            {node, [build_issue(pipe_meta) | issues]}
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
    RuleHelpers.patches_from_postwalk(ast, fn
      # Piped form: ... |> Stream/Enum.with_index() |> Enum.reduce(...)
      {:|>, pipe_meta, [left, reduce_call]} = node ->
        if with_index_piped?(left) and indexed_reduce_with_neighbor_at?(reduce_call) do
          apply_chunk_fix(left, reduce_call, pipe_meta)
        else
          node
        end

      node ->
        node
    end)
  end

  # --- Piped form fix ---

  defp apply_chunk_fix(left, reduce_call, _pipe_meta) do
    list = extract_pipe_source(left)

    case extract_peak_fn(reduce_call) do
      {:ok, _value_var, comparison_body} ->
        build_chunk_solution(list, comparison_body)

      :error ->
        {:|>, [], [left, reduce_call]}
    end
  end

  # --- AST pattern matchers ---

  defp with_index_piped?({{:., _, [{:__aliases__, _, [:Stream]}, :with_index]}, _, _}), do: true
  defp with_index_piped?({{:., _, [{:__aliases__, _, [:Enum]}, :with_index]}, _, _}), do: true

  # Nested pipe: deeper |> Stream/Enum.with_index()
  defp with_index_piped?({:|>, _, [_, right]}), do: with_index_piped?(right)

  defp with_index_piped?(_), do: false

  defp indexed_reduce_with_neighbor_at?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _meta, [_initial_acc, fn_node]}
       ) do
    case fn_node do
      {:fn, _, [{:->, _, [args, body]}]} ->
        fn_args_match_tuple_pattern?(args) and has_neighbor_at_access?(body)

      _ ->
        false
    end
  end

  defp indexed_reduce_with_neighbor_at?(_), do: false

  defp fn_args_match_tuple_pattern?([tuple_arg, _acc_arg]) do
    case unwrap_block(tuple_arg) do
      {{:value, _, nil}, {:index, _, nil}} -> true
      _ -> false
    end
  end

  defp fn_args_match_tuple_pattern?(_), do: false

  defp unwrap_block({:__block__, _, [inner]}), do: inner
  defp unwrap_block(other), do: other

  defp has_neighbor_at_access?(body) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [_list, {:-, _, _}]} = node, _acc ->
          {node, true}

        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [_list, {:+, _, _}]} = node, _acc ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Extract the list variable being piped
  defp extract_pipe_source({:|>, _, [left, _]}), do: extract_pipe_source(left)
  defp extract_pipe_source({{:., _, _}, _, _} = node), do: node
  defp extract_pipe_source({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: {name, [], ctx}

  # Extract peak comparison from reduce function
  defp extract_peak_fn(
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [_initial_acc, fn_node]}
       ) do
    case fn_node do
      {:fn, _, [{:->, _, [args, body]}]} ->
        case args do
          [_tuple_arg, _acc_arg] ->
            case extract_cond_true_branch(body) do
              {:ok, comparison} ->
                value_var = {:value, [], nil}
                {:ok, value_var, comparison}

              :error ->
                :error
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp extract_peak_fn(_), do: :error

  # Extract the true branch from a cond expression
  defp extract_cond_true_branch({:cond, _, [clauses_kw]}) do
    Enum.find_value(clauses_kw, :error, fn
      # Sourceror format: [do: [clauses_list]]
      {{:__block__, _, [:do]}, clauses_list} ->
        extract_true_clause(clauses_list)

      _ ->
        nil
    end)
  end

  defp extract_cond_true_branch(_), do: :error

  defp extract_true_clause(clauses_list) when is_list(clauses_list) do
    Enum.find_value(clauses_list, :error, fn
      {:->, _, [[{:__block__, _, [true]}], body]} ->
        extract_comparison_from_body(body)

      _ ->
        nil
    end)
  end

  defp extract_true_clause(_), do: :error

  defp extract_comparison_from_body({:__block__, _, stmts}) do
    # Pattern: left = Enum.at(...); right = Enum.at(...); if value > left and value > right...
    if_expr = Enum.find(stmts, &match?({:if, _, _}, &1))

    case if_expr do
      {:if, _, [condition, [_, _]]} ->
        {:ok, condition}

      _ ->
        :error
    end
  end

  defp extract_comparison_from_body({:if, _, [condition, [_, _]]}) do
    {:ok, condition}
  end

  defp extract_comparison_from_body(_), do: :error

  # --- Build the chunk solution AST ---

  defp build_chunk_solution(list, comparison_body) do
    list_var = extract_list_from_pipe(list)
    transformed_comparison = transform_comparison(comparison_body)

    middle_assign = build_middle_assign(list_var, transformed_comparison)
    first_assign = build_first_assign(list_var)
    last_assign = build_last_assign(list_var)
    sum_expr = build_sum_expr()

    {:__block__, [], [middle_assign, first_assign, last_assign, sum_expr]}
  end

  defp extract_list_from_pipe({:|>, _, [left, _]}), do: extract_list_from_pipe(left)
  defp extract_list_from_pipe({{:., _, _}, _, _} = node), do: node
  defp extract_list_from_pipe({name, _, ctx}) when is_atom(name), do: {name, [], ctx}
  defp extract_list_from_pipe(node), do: node

  defp transform_comparison(body) do
    # Replace references to :value with :candidate
    Macro.prewalk(body, fn
      {:value, _, ctx} when is_atom(ctx) -> {:candidate, [], nil}
      {:left, _, ctx} when is_atom(ctx) -> {:left, [], nil}
      {:right, _, ctx} when is_atom(ctx) -> {:right, [], nil}
      node -> node
    end)
  end

  defp build_middle_assign(list_var, comparison) do
    chunk_fn =
      {:fn, [],
       [
         {:->, [],
          [
            [
              {:__block__, [],
               [
                 [
                   {:left, [], nil},
                   {:candidate, [], nil},
                   {:right, [], nil}
                 ]
               ]}
            ],
            comparison
          ]}
       ]}

    chunk_pipe =
      {:|>, [],
       [
         {:|>, [],
          [
            list_var,
            {{:., [], [{:__aliases__, [], [:Enum]}, :chunk_every]}, [],
             [
               {:__block__, [token: "3"], [3]},
               {:__block__, [token: "1"], [1]},
               {:__block__, [], [:discard]}
             ]}
          ]},
        {{:., [], [{:__aliases__, [], [:Enum]}, :count]}, [], [chunk_fn]}
       ]}

    {:=, [], [{:middle, [], nil}, chunk_pipe]}
  end

  defp build_first_assign(list_var) do
    case_body = [
      {{:__block__, [], [:do]},
       [
         {:->, [],
          [
            [
              {:when, [],
               [
                 {:__block__, [],
                  [
                    [
                      {:first, [], nil},
                      {:|, [], [{:second, [], nil}, {:_, [], nil}]}
                    ]
                  ]},
                {:>, [], [{:first, [], nil}, {:second, [], nil}]}
              ]}
            ],
            {:__block__, [token: "1"], [1]}
          ]},
         {:->, [], [[{:_, [], nil}], {:__block__, [token: "0"], [0]}]}
       ]}
    ]

    {:=, [], [{:first, [], nil}, {:case, [do: [line: 1, column: 1]], [list_var, case_body]}]}
  end

  defp build_last_assign(list_var) do
    reverse_call = {{:., [], [{:__aliases__, [], [:Enum]}, :reverse]}, [], [list_var]}

    case_body = [
      {{:__block__, [], [:do]},
       [
         {:->, [],
          [
            [
              {:when, [],
               [
                 {:__block__, [],
                  [
                    [
                      {:last, [], nil},
                      {:|, [], [{:second_last, [], nil}, {:_, [], nil}]}
                    ]
                  ]},
                {:>, [], [{:last, [], nil}, {:second_last, [], nil}]}
              ]}
            ],
            {:__block__, [token: "1"], [1]}
          ]},
         {:->, [], [[{:_, [], nil}], {:__block__, [token: "0"], [0]}]}
       ]}
    ]

    {:=, [], [{:last, [], nil}, {:case, [do: [line: 1, column: 1]], [reverse_call, case_body]}]}
  end

  defp build_sum_expr do
    {:+, [], [{:+, [], [{:first, [], nil}, {:middle, [], nil}]}, {:last, [], nil}]}
  end

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_chunk_over_indexed_reduce,
      message:
        "`Enum.reduce/3` with `with_index()` and `Enum.at/2` for neighbour access " <>
          "is a sliding-window anti-pattern. " <>
          "Use `Enum.chunk_every(3, 1, :discard)` for direct `[prev, current, next]` triplets.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
