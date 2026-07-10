defmodule Credence.Semantic.FixRegexInGuard do
  @moduledoc """
  Fixes the compile error caused by using regex structs in guard expressions.

  LLMs commonly write `when content =~ ~r/^\s*$/` in a guard, causing:

      "escaped Regex structs are not allowed in match or guards"

  The deterministic fix strips the regex match from the guard and rewrites it
  as a `Regex.match?/2` call in the function body.  When multiple clauses for
  the same function carry regex guards, the fix chains them through private
  helper functions so that clause-dispatch semantics are preserved.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "escaped Regex structs are not allowed in match or guards"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_regex_in_guard,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} = transform_ast(ast)
      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # ---- AST transformation ------------------------------------------------

  defp transform_ast(ast) do
    Macro.prewalk(ast, false, fn
      {:defmodule, mod_meta, [alias, [do_block]]}, acc ->
        {{:__block__, do_meta, [:do]}, body} = do_block
        {new_body, body_changed} = transform_module_body(body)

        if body_changed do
          {{:defmodule, mod_meta, [alias, [{{:__block__, do_meta, [:do]}, new_body}]]}, true}
        else
          {{:defmodule, mod_meta, [alias, [do_block]]}, acc}
        end

      node, acc ->
        {node, acc}
    end)
  end

  defp transform_module_body({:__block__, meta, statements}) do
    groups =
      statements
      |> Enum.group_by(&get_fn_key/1)
      |> Map.delete(nil)

    regex_groups =
      groups
      |> Enum.filter(fn {_key, clauses} -> has_regex_in_any_guard?(clauses) end)
      |> Map.new()

    if map_size(regex_groups) == 0 do
      {{:__block__, meta, statements}, false}
    else
      {new_statements, _emitted} =
        Enum.reduce(statements, {[], MapSet.new()}, fn stmt, {acc, emitted} ->
          case get_fn_key(stmt) do
            nil ->
              {[stmt | acc], emitted}

            key ->
              if MapSet.member?(emitted, key) do
                {acc, emitted}
              else
                case Map.get(regex_groups, key) do
                  nil ->
                    {[stmt | acc], emitted}

                  clauses ->
                    transformed = transform_fn_group(key, clauses)
                    {Enum.reverse(transformed) ++ acc, MapSet.put(emitted, key)}
                end
              end
          end
        end)

      {{:__block__, meta, Enum.reverse(new_statements)}, true}
    end
  end

  # Single def clause (not wrapped in __block__)
  defp transform_module_body({:def, _, [{:when, _, [_, guard]}, _]} = clause) do
    if has_regex?(guard) do
      result =
        case transform_fn_group(get_fn_key(clause), [clause]) do
          [single] -> single
          multiple -> {:__block__, [], multiple}
        end

      {result, true}
    else
      {clause, false}
    end
  end

  defp transform_module_body(body), do: {body, false}

  # ---- Clause grouping ----------------------------------------------------

  defp get_fn_key({:def, _, [{:when, _, [{name, _, args} | _]} | _]})
       when is_atom(name) and is_list(args),
       do: {name, length(args)}

  defp get_fn_key({:def, _, [{name, _, args} | _]})
       when is_atom(name) and is_list(args),
       do: {name, length(args)}

  defp get_fn_key(_), do: nil

  defp has_regex_in_any_guard?(clauses) do
    Enum.any?(clauses, fn
      {:def, _, [{:when, _, [_, guard]}, _]} -> has_regex?(guard)
      _ -> false
    end)
  end

  # ---- Regex detection ----------------------------------------------------

  defp has_regex?({:=~, _, [_, {:sigil_r, _, _}]}), do: true
  defp has_regex?({:=~, _, [{:sigil_r, _, _}, _]}), do: true

  defp has_regex?({_, _, args}) when is_list(args) do
    Enum.any?(args, &has_regex?/1)
  end

  defp has_regex?(_), do: false

  # ---- Guard surgery ------------------------------------------------------

  defp extract_regex_from_guard(guard) do
    case find_and_remove_regex(guard) do
      {:found, regex, var, remaining} -> {:ok, regex, var, remaining}
      :not_found -> :no_regex
    end
  end

  defp find_and_remove_regex({:=~, _, [var, {:sigil_r, _, _} = regex]}) do
    {:found, regex, var, nil}
  end

  defp find_and_remove_regex({:=~, _, [{:sigil_r, _, _} = regex, var]}) do
    {:found, regex, var, nil}
  end

  defp find_and_remove_regex({:and, meta, [left, right]}) do
    case find_and_remove_regex(right) do
      {:found, regex, var, remaining_right} ->
        new_guard = if remaining_right, do: {:and, meta, [left, remaining_right]}, else: left
        {:found, regex, var, new_guard}

      :not_found ->
        case find_and_remove_regex(left) do
          {:found, regex, var, remaining_left} ->
            new_guard = if remaining_left, do: {:and, meta, [remaining_left, right]}, else: right
            {:found, regex, var, new_guard}

          :not_found ->
            :not_found
        end
    end
  end

  defp find_and_remove_regex(_), do: :not_found

  # ---- Clause transformation ----------------------------------------------

  defp transform_fn_group({name, _arity}, clauses) do
    {regex_clauses, other_clauses} =
      Enum.split_with(clauses, fn
        {:def, _, [{:when, _, [_, guard]}, _]} -> has_regex?(guard)
        _ -> false
      end)

    case regex_clauses do
      [] ->
        clauses

      [_single] ->
        catch_all_body = extract_catch_all_body(other_clauses)
        [transform_single_clause(hd(regex_clauses), catch_all_body)]

      _ ->
        catch_all_body = extract_catch_all_body(other_clauses)
        transform_multi_clauses(name, regex_clauses, catch_all_body)
    end
  end

  defp extract_catch_all_body(clauses) when is_list(clauses) do
    case List.last(clauses) do
      {:def, _, [_, do_block]} -> extract_body(do_block)
      _ -> nil
    end
  end

  defp extract_catch_all_body(_), do: nil

  defp transform_single_clause(clause, catch_all_body) do
    {:def, meta, [{:when, when_meta, [head, guard]}, do_block]} = clause
    {:ok, regex, var, remaining_guard} = extract_regex_from_guard(guard)

    new_head =
      if remaining_guard,
        do: {:when, when_meta, [head, remaining_guard]},
        else: head

    original_body = extract_body(do_block)
    fallback = catch_all_body || nil_literal()
    new_body = build_if_regex_match(regex, var, original_body, fallback)
    {:def, meta, [new_head, replace_body(do_block, new_body)]}
  end

  defp transform_multi_clauses(name, regex_clauses, catch_all_body) do
    n = length(regex_clauses)
    fallback = catch_all_body || nil_literal()

    # Build helper functions for clauses 1..n-1
    helpers =
      regex_clauses
      |> Enum.drop(1)
      |> Enum.with_index()
      |> Enum.map(fn {clause, idx} ->
        helper_name = :"#{name}_#{idx}"

        next_fallback =
          if idx < n - 2,
            do: build_fn_call(:"#{name}_#{idx + 1}", get_fn_args_from_clause(clause)),
            else: fallback

        build_helper_fn(helper_name, clause, next_fallback)
      end)

    # Build first clause (public function)
    first_fallback =
      if helpers != [],
        do: build_fn_call(:"#{name}_0", get_fn_args_from_clause(hd(regex_clauses))),
        else: fallback

    transformed_first = transform_first_clause(hd(regex_clauses), first_fallback)
    [transformed_first | helpers]
  end

  defp transform_first_clause(clause, fallback) do
    {:def, meta, [{:when, when_meta, [head, guard]}, do_block]} = clause
    {:ok, regex, var, remaining_guard} = extract_regex_from_guard(guard)

    new_head =
      if remaining_guard,
        do: {:when, when_meta, [head, remaining_guard]},
        else: head

    original_body = extract_body(do_block)
    new_body = build_if_regex_match(regex, var, original_body, fallback)
    {:def, meta, [new_head, replace_body(do_block, new_body)]}
  end

  defp build_helper_fn(helper_name, clause, fallback) do
    {:def, clause_meta, [{:when, _, [head, guard]}, do_block]} = clause
    {:ok, regex, var, _} = extract_regex_from_guard(guard)

    {_orig_name, name_meta, _orig_args} = head
    args = get_fn_args(head)
    helper_head = {helper_name, name_meta, args}

    original_body = extract_body(do_block)
    new_body = build_if_regex_match(regex, var, original_body, fallback)
    {:defp, clause_meta, [helper_head, replace_body(do_block, new_body)]}
  end

  # ---- Helpers ------------------------------------------------------------

  defp get_fn_args({:when, _, [head, _]}), do: get_fn_args(head)
  defp get_fn_args({_, _, args}) when is_list(args), do: args

  defp get_fn_args_from_clause({:def, _, [{:when, _, [head, _]}, _]}),
    do: get_fn_args(head)

  defp get_fn_args_from_clause({:def, _, [head, _]}),
    do: get_fn_args(head)

  defp build_fn_call(fn_name, args) do
    {fn_name, [], args}
  end

  defp nil_literal do
    {:__block__, [], [nil]}
  end

  defp extract_body([{{:__block__, _meta, [:do]}, body}]), do: body
  defp extract_body([do: body]), do: body

  defp replace_body([{{:__block__, meta, [:do]}, _body}], new_body),
    do: [{{:__block__, meta, [:do]}, new_body}]

  defp replace_body([do: _body], new_body), do: [do: new_body]

  defp build_if_regex_match(regex, var, body, fallback) do
    {:if, [],
     [
       {{:., [], [{:__aliases__, [], [:Regex]}, :match?]}, [], [regex, var]},
       [
         {{:__block__, [format: :keyword], [:do]}, body},
         {{:__block__, [format: :keyword], [:else]}, fallback}
       ]
     ]}
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
