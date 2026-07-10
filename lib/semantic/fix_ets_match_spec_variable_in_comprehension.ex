defmodule Credence.Semantic.FixEtsMatchSpecVariableInComprehension do
  @moduledoc """
  Fixes `undefined variable` errors caused by using Elixir variables inside
  `:ets.match` match specs.

  LLMs frequently write patterns like:

      for {name, _type, value} <- :ets.match(table, {name, :_, :"$1"}) do
        {name, value}
      end

  or in plain function bodies:

      [{evicted_key, _}] = :ets.match(data_table, {evicted_key, :"$1"})

  where an Elixir variable is used as if it were a match spec variable,
  causing `undefined variable "name"` compilation errors.

  For `for` comprehensions, the fix restructures as an `Enum.map` pipeline:

      :ets.match(table, {:"$1", :_, :"$2"})
      |> Enum.map(fn [name, value] -> {name, value} end)

  For plain assignments, the fix replaces the Elixir variables with match spec
  variables and adds extraction assignments:

      [{:"$1", _}] = :ets.match(data_table, {:"$1", :"$1"})
      evicted_key = :"$1"
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, "undefined variable \"")
  end

  def match?(_), do: false

  @doc false
  def should_report?(_diagnostic, source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> has_ets_match_with_elixir_var?(ast)
      _ -> false
    end
  end

  @impl true
  def to_issue(%{message: msg} = diagnostic) do
    %Issue{
      rule: :fix_ets_match_spec_variable_in_comprehension,
      message: msg,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: _msg}) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:for, _, [{:<-, _, [pattern, rhs]}, body_kw]} = node, acc ->
            case try_transform_for(pattern, rhs, body_kw) do
              {:ok, result} -> {result, true}
              :error -> {node, acc}
            end

          {:__block__, meta, stmts} = node, acc when is_list(stmts) ->
            case transform_block_stmts(stmts) do
              {:ok, new_stmts} -> {{:__block__, meta, new_stmts}, true}
              :error -> {node, acc}
            end

          {:=, assign_meta, [_, _]} = node, acc ->
            case try_transform_plain_stmt(node) do
              {:ok, new_stmt, new_assignments} ->
                {{:__block__, assign_meta, [new_stmt | new_assignments]}, true}

              :error ->
                {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # --- source inspection ---

  defp has_ets_match_with_elixir_var?(ast) do
    has_ets_match_in_for?(ast) or has_ets_match_in_plain?(ast)
  end

  defp has_ets_match_in_for?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:for, _, [{:<-, _, [_, rhs]}, _]} = node, acc ->
          if ets_match_call?(rhs), do: {node, true}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp has_ets_match_in_plain?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:=, _, [lhs, rhs]} = node, acc ->
          if ets_match_call?(rhs) and has_list_pattern?(lhs) do
            {node, true}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp has_list_pattern?({:__block__, _, [list]}) when is_list(list), do: true
  defp has_list_pattern?(list) when is_list(list), do: true
  defp has_list_pattern?(_), do: false

  defp ets_match_call?({{:., _, [{:__block__, _, [:ets]}, :match]}, _, _}), do: true
  defp ets_match_call?({{:., _, [{:__aliases__, _, [:ets]}, :match]}, _, _}), do: true
  defp ets_match_call?(_), do: false

  # --- fix helpers ---

  # Transform statements in a block, inserting new assignments after ets.match fixes
  defp transform_block_stmts(stmts) do
    {new_stmts, changed?} =
      Enum.reduce(stmts, {[], false}, fn stmt, {acc, changed} ->
        case try_transform_plain_stmt(stmt) do
          {:ok, transformed, new_assignments} ->
            {acc ++ [transformed | new_assignments], true}

          :error ->
            {acc ++ [stmt], changed}
        end
      end)

    if changed?, do: {:ok, new_stmts}, else: :error
  end

  # Unwrap single-statement __block__ wrappers (Sourceror wraps each statement)
  defp try_transform_plain_stmt({:__block__, _meta, [stmt]}) do
    try_transform_plain_stmt(stmt)
  end

  defp try_transform_plain_stmt({:=, assign_meta, [lhs, rhs]}) do
    with true <- ets_match_call?(rhs),
         list when is_list(list) <- extract_list_contents(lhs),
         [pattern_tuple_or_block] <- list,
         pattern_tuple = unwrap_single_block(pattern_tuple_or_block),
         true <- is_tuple_form?(pattern_tuple),
         pattern_elems = tuple_elements(pattern_tuple),
         {:ok, table, raw_match_spec} <- extract_ets_match(rhs),
         match_spec = unwrap_single_block(raw_match_spec),
         true <- is_tuple_form?(match_spec),
         match_elems = tuple_elements(match_spec),
         true <- length(pattern_elems) == length(match_elems) do
      {new_match_elems, captured_vars} = process_positions_plain(pattern_elems, match_elems)

      if captured_vars == [] do
        :error
      else
        name_to_dollar = Map.new(captured_vars, fn {num, name} -> {name, num} end)

        new_match_spec = rebuild_tuple(match_spec, new_match_elems)
        # Re-wrap match spec if original was __block__-wrapped
        wrapped_match_spec =
          case raw_match_spec do
            {:__block__, ms_meta, _} -> {:__block__, ms_meta, [new_match_spec]}
            _ -> new_match_spec
          end
        new_rhs = replace_call_args(rhs, [table, wrapped_match_spec])

        new_pattern_elems =
          Enum.map(pattern_elems, fn elem ->
            case extract_var_atom(elem) do
              nil ->
                elem

              var_name ->
                case Map.get(name_to_dollar, var_name) do
                  nil -> elem
                  dollar_num -> make_dollar_var(dollar_num)
                end
            end
          end)

        new_pattern_tuple = rebuild_tuple(pattern_tuple, new_pattern_elems)
        # Re-wrap if original was __block__-wrapped
        wrapped_pattern_tuple =
          case pattern_tuple_or_block do
            {:__block__, meta, _} -> {:__block__, meta, [new_pattern_tuple]}
            _ -> new_pattern_tuple
          end
        new_lhs = replace_list_contents(lhs, [wrapped_pattern_tuple])
        new_stmt = {:=, assign_meta, [new_lhs, new_rhs]}

        new_assignments =
          Enum.map(captured_vars, fn {num, var_name} ->
            {:=, assign_meta, [{var_name, [], nil}, make_dollar_var(num)]}
          end)

        {:ok, new_stmt, new_assignments}
      end
    else
      _ -> :error
    end
  end

  defp try_transform_plain_stmt(_), do: :error

  defp try_transform_for(pattern, rhs, body_kw) do
    with {:ok, table, match_spec} <- extract_ets_match(rhs),
         true <- is_tuple_form?(pattern),
         true <- is_tuple_form?(match_spec) do
      pattern_elems = tuple_elements(pattern)
      match_elems = tuple_elements(match_spec)

      if length(pattern_elems) != length(match_elems) do
        :error
      else
        {new_match_elems, captured_vars} =
          process_positions(pattern_elems, match_elems)

        if captured_vars == [] do
          :error
        else
          new_match_spec = rebuild_tuple(match_spec, new_match_elems)
          new_rhs = replace_call_args(rhs, [table, new_match_spec])
          lambda = build_lambda(captured_vars, body_kw)
          enum_map = build_enum_map_call(lambda)
          {:ok, {:|>, [newlines: 1], [new_rhs, enum_map]}}
        end
      end
    else
      _ -> :error
    end
  end

  defp extract_ets_match(
         {{:., _, [{:__block__, _, [:ets]}, :match]}, _, [table, match_spec]}
       ) do
    {:ok, table, match_spec}
  end

  defp extract_ets_match(
         {{:., _, [{:__aliases__, _, [:ets]}, :match]}, _, [table, match_spec]}
       ) do
    {:ok, table, match_spec}
  end

  defp extract_ets_match(_), do: :error

  defp is_tuple_form?({:{}, _, _}), do: true
  defp is_tuple_form?({_, _}), do: true
  defp is_tuple_form?(_), do: false

  defp tuple_elements({:{}, _, elems}), do: elems
  defp tuple_elements({a, b}), do: [a, b]

  defp rebuild_tuple({:{}, meta, _}, elems), do: {:{}, meta, elems}
  defp rebuild_tuple(_, [a, b]), do: {a, b}

  defp replace_call_args({{:., dot_meta, receiver}, call_meta, _}, args) do
    {{:., dot_meta, receiver}, call_meta, args}
  end

  defp extract_list_contents({:__block__, _, [list]}) when is_list(list), do: list
  defp extract_list_contents(list) when is_list(list), do: list
  defp extract_list_contents(_), do: nil

  defp replace_list_contents({:__block__, meta, [_list]}, new_list) do
    {:__block__, meta, [new_list]}
  end

  defp replace_list_contents(_list, new_list), do: new_list

  defp unwrap_single_block({:__block__, _, [node]}), do: node
  defp unwrap_single_block(node), do: node

  # For `for` comprehension case: renumber all dollar vars sequentially
  defp process_positions(pattern_elems, match_spec_elems) do
    pairs = Enum.zip(pattern_elems, match_spec_elems)

    {new_ms, captured, _next} =
      Enum.reduce(pairs, {[], [], 1}, fn {pat, ms}, {ms_acc, cap_acc, num} ->
        pat_var = extract_var_atom(pat)
        skip = underscore_prefix?(pat_var)

        case classify_match_spec_elem(ms) do
          :wildcard ->
            {[ms | ms_acc], cap_acc, num}

          {:dollar_var, _} ->
            new_ms = make_dollar_var(num)

            if skip do
              {[new_ms | ms_acc], cap_acc, num + 1}
            else
              {[new_ms | ms_acc], [{num, pat_var} | cap_acc], num + 1}
            end

          {:elixir_var, _} ->
            new_ms = make_dollar_var(num)

            if skip do
              {[new_ms | ms_acc], cap_acc, num + 1}
            else
              {[new_ms | ms_acc], [{num, pat_var} | cap_acc], num + 1}
            end

          :keep_as_is ->
            {[ms | ms_acc], cap_acc, num}
        end
      end)

    {Enum.reverse(new_ms), Enum.reverse(captured)}
  end

  # For plain assignment case: keep existing dollar vars, replace only Elixir vars
  defp process_positions_plain(pattern_elems, match_spec_elems) do
    pairs = Enum.zip(pattern_elems, match_spec_elems)

    {new_ms, captured, _next} =
      Enum.reduce(pairs, {[], [], 1}, fn {pat, ms}, {ms_acc, cap_acc, next} ->
        pat_var = extract_var_atom(pat)
        skip = underscore_prefix?(pat_var)

        case classify_match_spec_elem(ms) do
          :wildcard ->
            {[ms | ms_acc], cap_acc, next}

          {:dollar_var, _} ->
            # Keep existing dollar vars as-is in the match spec
            {[ms | ms_acc], cap_acc, next}

          {:elixir_var, _} ->
            new_ms = make_dollar_var(next)

            if skip do
              {[new_ms | ms_acc], cap_acc, next + 1}
            else
              {[new_ms | ms_acc], [{next, pat_var} | cap_acc], next + 1}
            end

          :keep_as_is ->
            {[ms | ms_acc], cap_acc, next}
        end
      end)

    {Enum.reverse(new_ms), Enum.reverse(captured)}
  end

  defp classify_match_spec_elem({:__block__, _, [atom]}) when is_atom(atom) do
    atom_str = Atom.to_string(atom)

    cond do
      atom == :_ ->
        :wildcard

      String.starts_with?(atom_str, "$") ->
        case Integer.parse(String.slice(atom_str, 1..-1//1)) do
          {_, ""} -> {:dollar_var, nil}
          _ -> :keep_as_is
        end

      true ->
        :keep_as_is
    end
  end

  defp classify_match_spec_elem({name, _, nil}) when is_atom(name) do
    {:elixir_var, name}
  end

  defp classify_match_spec_elem(_), do: :elixir_var

  defp extract_var_atom({name, _, nil}) when is_atom(name), do: name
  defp extract_var_atom(_), do: nil

  defp underscore_prefix?(nil), do: true

  defp underscore_prefix?(name) do
    String.starts_with?(Atom.to_string(name), "_")
  end

  defp make_dollar_var(n) do
    {:__block__, [delimiter: "\""], [String.to_atom("$#{n}")]}
  end

  defp build_lambda(captured_vars, body_kw) do
    body = extract_do_body_ast(body_kw)
    var_names = Enum.map(captured_vars, fn {_num, name} -> {name, [], nil} end)
    list_pattern = {:__block__, [], [var_names]}
    clause = {:->, [], [[list_pattern], body]}
    {:fn, [], [clause]}
  end

  defp extract_do_body_ast([{{:__block__, _, [:do]}, body}]), do: body
  defp extract_do_body_ast(_), do: {:__block__, [], []}

  defp build_enum_map_call(lambda) do
    enum_alias = {:__aliases__, [], [:Enum]}
    {{:., [], [enum_alias, :map]}, [], [lambda]}
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
