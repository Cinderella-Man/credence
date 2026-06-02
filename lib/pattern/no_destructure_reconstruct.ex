defmodule Credence.Pattern.NoDestructureReconstruct do
  @moduledoc """
  Detects patterns where a list, cons, or binary is destructured into
  individual variables and then immediately reassembled into the same
  structure.

  ## Why this matters

  LLMs destructure lists element-by-element because they think in terms
  of individual values, then reconstruct the list to pass to an Enum
  function.  The reader sees named variables and expects them to be used
  individually, only to discover they're re-wrapped:

      # Flagged — destructure then reconstruct
      case String.split(ip, ".") do
        [p1, p2, p3, p4] ->
          Enum.all?([p1, p2, p3, p4], &valid_octet?/1)
      end

      # Idiomatic — bind as a whole, pattern match for length
      case String.split(ip, ".") do
        [_, _, _, _] = parts ->
          Enum.all?(parts, &valid_octet?/1)
      end

  Similarly for binaries — LLMs destructure a binary into segments only
  to reconstruct the same binary:

      # Flagged — binary destructure then reconstruct
      def process(<<char, rest::binary>>) do
        string = <<char, rest::binary>>
        String.length(string)
      end

      # Idiomatic — bind as a whole
      def process(<<_, _::binary>> = string) do
        String.length(string)
      end

  ## Auto-fix strategy

  **Lists:** bind the whole list with `= items` on the pattern, replace
  the reconstructed list `[a, b, c]` in the body with `items`, and
  replace unused variables with `_` in the pattern.

  **Binaries:** bind the whole binary with `= string` on the pattern,
  replace the reconstructed binary in the body with `string`, and
  replace unused segment variables with `_` in the pattern.

  ## Flagged patterns

  - A list pattern `[a, b, c, ...]` in a `case` branch or function head
    where the body contains a list literal `[a, b, c, ...]` with the
    exact same variables in the same order.
  - A cons pattern `[h | t]` where the body reconstructs the same cons.
  - A binary pattern `<<a, rest::binary>>` where the body reconstructs
    the same binary using the same segment variables.

  Only flagged when the pattern contains 2 or more simple variables
  (not literals, patterns, or underscore-prefixed names).
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, new_issues} -> {node, new_issues ++ issues}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  defp check_node({:case, _meta, [_expr, kw_list]}) when is_list(kw_list) do
    with {:ok, clauses} <- RuleHelpers.extract_do_body(kw_list),
         true <- is_list(clauses) do
      issues =
        Enum.flat_map(clauses, fn
          {:->, meta, [[pattern], body]} -> check_pattern_body(pattern, body, meta)
          _ -> []
        end)

      if issues == [], do: :error, else: {:ok, issues}
    else
      _ -> :error
    end
  end

  defp check_node({def_type, _meta, [{:when, _, [{_fn_name, _, args}, _guard]}, body]})
       when def_type in [:def, :defp] and is_list(args) do
    issues = Enum.flat_map(args, fn arg -> check_pattern_body(arg, body, []) end)
    issues = drop_multi_arg_cons_issues(issues, args, body)
    if issues == [], do: :error, else: {:ok, issues}
  end

  defp check_node({def_type, _meta, [{_fn_name, _, args}, body]})
       when def_type in [:def, :defp] and is_list(args) do
    issues = Enum.flat_map(args, fn arg -> check_pattern_body(arg, body, []) end)
    issues = drop_multi_arg_cons_issues(issues, args, body)
    if issues == [], do: :error, else: {:ok, issues}
  end

  defp check_node(_), do: :error

  defp check_pattern_body(pattern, body, meta) do
    list_issues =
      case extract_var_names(pattern) do
        {:ok, var_names} when length(var_names) >= 2 ->
          if body_contains_same_list?(body, var_names) do
            [build_issue(var_names, meta)]
          else
            []
          end

        _ ->
          []
      end

    cons_issues =
      case extract_cons_names(pattern) do
        {:ok, head_name, tail_name} ->
          if body_contains_same_cons?(body, head_name, tail_name) do
            [build_cons_issue(head_name, tail_name, meta)]
          else
            []
          end

        _ ->
          []
      end

    binary_issues =
      case extract_binary_segment_names(pattern) do
        {:ok, var_names} when length(var_names) >= 2 ->
          if body_contains_same_binary?(body, var_names) do
            [build_binary_issue(var_names, meta)]
          else
            []
          end

        _ ->
          []
      end

    list_issues ++ cons_issues ++ binary_issues
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite/1)
  end

  defp maybe_rewrite({:case, case_meta, [expr, kw_list]} = node) when is_list(kw_list) do
    with {:ok, clauses} <- RuleHelpers.extract_do_body(kw_list),
         true <- is_list(clauses),
         fixed_clauses <- Enum.map(clauses, &fix_case_clause/1),
         true <- fixed_clauses != clauses do
      {:case, case_meta, [expr, RuleHelpers.replace_do_body(kw_list, fixed_clauses)]}
    else
      _ -> node
    end
  end

  defp maybe_rewrite(
         {def_type, def_meta, [{:when, when_meta, [{fn_name, head_meta, args}, guard]}, body]} =
           node
       )
       when def_type in [:def, :defp] and is_list(args) do
    case rewrite_args_and_body(args, body, guard) do
      {:changed, new_args, new_body} ->
        {def_type, def_meta,
         [{:when, when_meta, [{fn_name, head_meta, new_args}, guard]}, new_body]}

      :unchanged ->
        node
    end
  end

  defp maybe_rewrite({def_type, def_meta, [{fn_name, head_meta, args}, body]} = node)
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    case rewrite_args_and_body(args, body, nil) do
      {:changed, new_args, new_body} ->
        {def_type, def_meta, [{fn_name, head_meta, new_args}, new_body]}

      :unchanged ->
        node
    end
  end

  defp maybe_rewrite(node), do: node

  defp rewrite_args_and_body(args, body, extra_ast) do
    # When multiple arguments have their cons pattern reconstructed in the
    # body, the fix would bind each to the same `= list` variable, forcing
    # the arguments to be equal — a semantic error.  Skip the fix entirely.
    if multi_arg_cons_reconstruction?(args, body) do
      :unchanged
    else
      {new_args, new_body, changed?} =
        Enum.reduce(args, {[], body, false}, fn arg, {acc, cur_body, changed} ->
          case fix_pattern_body(arg, cur_body, extra_ast) do
            {:fixed, new_arg, new_body} -> {acc ++ [new_arg], new_body, true}
            :no_fix -> {acc ++ [arg], cur_body, changed}
          end
        end)

      if changed?, do: {:changed, new_args, new_body}, else: :unchanged
    end
  end

  defp multi_arg_cons_reconstruction?(args, body) do
    count =
      Enum.count(args, fn arg ->
        case extract_cons_names(arg) do
          {:ok, head_name, tail_name} ->
            body_contains_same_cons?(body, head_name, tail_name)

          _ ->
            false
        end
      end)

    count >= 2
  end

  defp fix_case_clause({:->, meta, [[pattern], body]}) do
    case fix_pattern_body(pattern, body) do
      {:fixed, new_pattern, new_body} -> {:->, meta, [[new_pattern], new_body]}
      :no_fix -> {:->, meta, [[pattern], body]}
    end
  end

  defp fix_case_clause(other), do: other

  defp fix_pattern_body(pattern, body, extra_ast \\ nil) do
    case fix_list_pattern_body(pattern, body, extra_ast) do
      {:fixed, _, _} = result -> result

      :no_fix ->
        case fix_cons_pattern_body(pattern, body, extra_ast) do
          {:fixed, _, _} = result -> result
          :no_fix -> fix_binary_pattern_body(pattern, body, extra_ast)
        end
    end
  end

  defp fix_list_pattern_body(pattern, body, extra_ast) do
    with {:ok, elements, list_node} <- RuleHelpers.unwrap_list(pattern),
         {:ok, var_names} when length(var_names) >= 2 <- extract_names_from_elements(elements),
         true <- body_contains_same_list?(body, var_names) do
      binding_var = {:items, [], nil}
      new_body = replace_reconstructed_list(body, var_names, binding_var)

      used = collect_variable_names(new_body)

      used =
        if extra_ast, do: MapSet.union(used, collect_variable_names(extra_ast)), else: used

      new_elements =
        Enum.map(elements, fn
          {name, meta, ctx} when is_atom(name) and is_atom(ctx) ->
            if MapSet.member?(used, name), do: {name, meta, ctx}, else: {:_, meta, ctx}

          other ->
            other
        end)

      new_list = RuleHelpers.rewrap_list(list_node, new_elements)
      {:fixed, {:=, [], [new_list, binding_var]}, new_body}
    else
      _ -> :no_fix
    end
  end

  defp fix_cons_pattern_body(pattern, body, extra_ast) do
    with {:ok, {h_name, _, h_ctx} = head, {t_name, _, t_ctx} = tail} <- extract_cons_vars(pattern),
         true <- is_atom(h_name) and is_atom(t_name),
         true <- (is_nil(h_ctx) or is_atom(h_ctx)) and (is_nil(t_ctx) or is_atom(t_ctx)),
         false <- String.starts_with?(Atom.to_string(h_name), "_"),
         false <- String.starts_with?(Atom.to_string(t_name), "_"),
         true <- body_contains_same_cons?(body, h_name, t_name) do
      binding_var = {:list, [], nil}
      new_body = replace_reconstructed_cons(body, h_name, t_name, binding_var)

      used = collect_variable_names(new_body)

      used =
        if extra_ast, do: MapSet.union(used, collect_variable_names(extra_ast)), else: used

      head_used = MapSet.member?(used, h_name)
      tail_used = MapSet.member?(used, t_name)

      new_head = if(head_used, do: head, else: {:_, [], nil})
      new_tail = if(tail_used, do: tail, else: {:_, [], nil})

      # Wrap in Sourceror list syntax so it renders as [h | _] not (h | _)
      new_cons = {:__block__, [], [[{:|, [], [new_head, new_tail]}]]}

      {:fixed, {:=, [], [new_cons, binding_var]}, new_body}
    else
      _ -> :no_fix
    end
  end

  defp replace_reconstructed_cons(body, head_name, tail_name, replacement) do
    do_replace_cons_outside_tail(body, head_name, tail_name, replacement)
  end

  # Replace matching cons in "outside tail" context.
  defp do_replace_cons_outside_tail(node, h_name, t_name, replacement) do
    if cons_match?(node, h_name, t_name) do
      replacement
    else
      case node do
        {:|, meta, [head, tail]} ->
          new_head = do_replace_cons_outside_tail(head, h_name, t_name, replacement)

          new_tail =
            do_replace_cons_in_tail(tail, h_name, t_name, replacement)

          if new_head == head and new_tail == tail,
            do: node,
            else: {:|, meta, [new_head, new_tail]}

        list when is_list(list) ->
          replace_list_outside_tail(list, h_name, t_name, replacement)

        tuple when is_tuple(tuple) ->
          new_elements =
            tuple
            |> Tuple.to_list()
            |> Enum.map(&do_replace_cons_outside_tail(&1, h_name, t_name, replacement))

          original_elements = Tuple.to_list(tuple)
          if new_elements == original_elements, do: tuple, else: List.to_tuple(new_elements)

        _ ->
          node
      end
    end
  end

  # Inside a cons tail — do NOT replace this node (it's not a reconstruction).
  defp do_replace_cons_in_tail(node, h_name, t_name, replacement) do
    case node do
      {:|, meta, [head, tail]} ->
        new_head = do_replace_cons_outside_tail(head, h_name, t_name, replacement)

        new_tail =
          do_replace_cons_in_tail(tail, h_name, t_name, replacement)

        if new_head == head and new_tail == tail,
          do: node,
          else: {:|, meta, [new_head, new_tail]}

      list when is_list(list) ->
        replace_list_outside_tail(list, h_name, t_name, replacement)

      tuple when is_tuple(tuple) ->
        new_elements =
          tuple
          |> Tuple.to_list()
          |> Enum.map(&do_replace_cons_outside_tail(&1, h_name, t_name, replacement))

        original_elements = Tuple.to_list(tuple)
        if new_elements == original_elements, do: tuple, else: List.to_tuple(new_elements)

      _ ->
        node
    end
  end

  # Replace matching cons in a list. If the list has a trailing cons
  # (e.g. [a, h | t] stored as [a, {:|, _, [h, t]}]), the trailing cons
  # is NOT a standalone reconstruction.
  defp replace_list_outside_tail(list, h_name, t_name, replacement) do
    case List.last(list) do
      {:|, _, _} when length(list) > 1 ->
        prefix = Enum.drop(list, -1)
        trailing = List.last(list)
        new_prefix = Enum.map(prefix, &do_replace_cons_outside_tail(&1, h_name, t_name, replacement))
        new_trailing = do_replace_cons_in_tail(trailing, h_name, t_name, replacement)
        new_list = new_prefix ++ [new_trailing]
        if new_list == list, do: list, else: new_list

      _ ->
        new_list = Enum.map(list, &do_replace_cons_outside_tail(&1, h_name, t_name, replacement))
        if new_list == list, do: list, else: new_list
    end
  end

  defp replace_reconstructed_list(body, target_var_names, replacement) do
    # Prewalk so we hit the `:__block__` wrapper before descending into
    # the inner list — replacing the inner list alone leaves the
    # bracket-carrying wrapper behind, which re-renders as `[items]`.
    Macro.prewalk(body, fn
      {:__block__, _, [elements]} = node when is_list(elements) ->
        case extract_names_from_elements(elements) do
          {:ok, ^target_var_names} -> replacement
          _ -> node
        end

      node ->
        node
    end)
  end

  defp body_contains_same_list?(body, target_var_names) do
    {_, found} =
      Macro.prewalk(body, false, fn
        node, true ->
          {node, true}

        node, false ->
          case RuleHelpers.unwrap_list(node) do
            {:ok, elements, _} ->
              case extract_names_from_elements(elements) do
                {:ok, ^target_var_names} -> {node, true}
                _ -> {node, false}
              end

            :error ->
              {node, false}
          end
      end)

    found
  end

  defp collect_variable_names(ast) do
    {_, names} =
      Macro.postwalk(ast, MapSet.new(), fn
        {name, _, ctx} = node, acc when is_atom(name) and is_atom(ctx) ->
          {node, MapSet.put(acc, name)}

        node, acc ->
          {node, acc}
      end)

    names
  end

  defp extract_var_names(pattern) do
    with {:ok, elements, _} <- RuleHelpers.unwrap_list(pattern) do
      extract_names_from_elements(elements)
    end
  end

  defp extract_names_from_elements(elements) when is_list(elements) do
    names =
      Enum.map(elements, fn
        {name, _, ctx} when is_atom(name) and is_atom(ctx) ->
          str = Atom.to_string(name)
          if String.starts_with?(str, "_"), do: :skip, else: name

        _ ->
          :skip
      end)

    if Enum.any?(names, &(&1 == :skip)), do: :error, else: {:ok, names}
  end

  defp extract_names_from_elements(_), do: :error

  # Cons pattern helpers

  defp extract_cons_names(pattern) do
    with {:ok, {h_name, _, h_ctx}, {t_name, _, t_ctx}} <- extract_cons_vars(pattern),
         true <- is_atom(h_name) and is_atom(t_name),
         true <- (is_nil(h_ctx) or is_atom(h_ctx)) and (is_nil(t_ctx) or is_atom(t_ctx)),
         false <- String.starts_with?(Atom.to_string(h_name), "_"),
         false <- String.starts_with?(Atom.to_string(t_name), "_") do
      {:ok, h_name, t_name}
    else
      _ -> :error
    end
  end

  defp extract_cons_vars({:|, _, [head, tail]}), do: {:ok, head, tail}

  defp extract_cons_vars({:__block__, _, [[{:|, _, [head, tail]}]]}),
    do: {:ok, head, tail}

  defp extract_cons_vars(_), do: :error

  defp body_contains_same_cons?(body, head_name, tail_name) do
    search_cons_outside_tail(body, head_name, tail_name)
  end

  # Search for a matching cons in "outside tail" context — a match here means
  # the cons is used as a standalone value (legitimate reconstruction).
  defp search_cons_outside_tail(node, h_name, t_name) do
    if cons_match?(node, h_name, t_name) do
      true
    else
      case node do
        # Cons node: head is outside tail, tail is inside tail
        {:|, _, [head, tail]} ->
          search_cons_outside_tail(head, h_name, t_name) or
            search_cons_in_tail(tail, h_name, t_name)

        list when is_list(list) ->
          search_list_outside_tail(list, h_name, t_name)

        tuple when is_tuple(tuple) ->
          tuple |> Tuple.to_list() |> Enum.any?(&search_cons_outside_tail(&1, h_name, t_name))

        _ ->
          false
      end
    end
  end

  # Inside a cons tail — the node itself is NOT a reconstruction (e.g. the
  # `[h | t]` inside `[a, h | t]` builds a new list, so do NOT match it).
  # Still recurse: the head of a nested cons resets to outside-tail context.
  defp search_cons_in_tail(node, h_name, t_name) do
    case node do
      {:|, _, [head, tail]} ->
        search_cons_outside_tail(head, h_name, t_name) or
          search_cons_in_tail(tail, h_name, t_name)

      list when is_list(list) ->
        search_list_outside_tail(list, h_name, t_name)

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&search_cons_outside_tail(&1, h_name, t_name))

      _ ->
        false
    end
  end

  # Search a list for matching cons. If the list has a trailing cons
  # (e.g. [a, h | t] stored as [a, {:|, _, [h, t]}]), the trailing cons
  # is NOT a standalone reconstruction — it builds the list's tail.
  defp search_list_outside_tail(list, h_name, t_name) do
    case List.last(list) do
      {:|, _, _} = trailing_cons when length(list) > 1 ->
        # Check all elements except the last
        prefix = Enum.drop(list, -1)
        Enum.any?(prefix, &search_cons_outside_tail(&1, h_name, t_name)) or
          search_cons_in_tail(trailing_cons, h_name, t_name)

      _ ->
        Enum.any?(list, &search_cons_outside_tail(&1, h_name, t_name))
    end
  end

  defp cons_match?({:|, _, [{h, _, h_ctx}, {t, _, t_ctx}]}, head_name, tail_name)
       when is_atom(h) and is_atom(t) and (is_nil(h_ctx) or is_atom(h_ctx)) and
              (is_nil(t_ctx) or is_atom(t_ctx)) do
    h == head_name and t == tail_name
  end

  defp cons_match?(
         {:__block__, _, [[{:|, _, [{h, _, h_ctx}, {t, _, t_ctx}]}]]},
         head_name,
         tail_name
       )
       when is_atom(h) and is_atom(t) and (is_nil(h_ctx) or is_atom(h_ctx)) and
              (is_nil(t_ctx) or is_atom(t_ctx)) do
    h == head_name and t == tail_name
  end

  defp cons_match?(_, _, _), do: false

  # When multiple function arguments have their cons pattern reconstructed
  # in the body, the auto-fix would bind each to the same `= list`
  # variable, which forces the arguments to be equal — a semantic error.
  # Drop cons issues when two or more args would be affected.
  defp drop_multi_arg_cons_issues(issues, args, _body) when length(args) <= 1, do: issues

  defp drop_multi_arg_cons_issues(issues, args, body) do
    args_with_cons_reconstruction =
      Enum.count(args, fn arg ->
        case extract_cons_names(arg) do
          {:ok, head_name, tail_name} ->
            body_contains_same_cons?(body, head_name, tail_name)

          _ ->
            false
        end
      end)

    if args_with_cons_reconstruction >= 2 do
      Enum.reject(issues, &(&1.rule == :no_destructure_reconstruct and cons_issue?(&1)))
    else
      issues
    end
  end

  defp cons_issue?(%{message: msg}), do: String.starts_with?(msg, "Cons")

  defp build_cons_issue(head_name, tail_name, meta) do
    %Issue{
      rule: :no_destructure_reconstruct,
      message: """
      Cons `[#{head_name} | #{tail_name}]` is destructured and then reassembled \
      into the same cons.

      Bind the list as a whole and use a binding:

          [_ | _] = list\
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_issue(var_names, meta) do
    vars_str = Enum.map_join(var_names, ", ", &to_string/1)
    count = length(var_names)

    %Issue{
      rule: :no_destructure_reconstruct,
      message: """
      List `[#{vars_str}]` is destructured and then reassembled \
      into the same list.

      Bind the list as a whole and pattern match for length:

          [#{String.duplicate("_, ", count - 1)}_] = parts\
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  # ---- Binary pattern helpers ----

  defp extract_binary_segment_names({:<<>>, _, segments}) when is_list(segments) do
    do_extract_binary_segment_names(segments)
  end

  defp extract_binary_segment_names({:__block__, _, [{:<<>>, _, segments}]})
       when is_list(segments) do
    do_extract_binary_segment_names(segments)
  end

  defp extract_binary_segment_names(_), do: :error

  defp do_extract_binary_segment_names(segments) do
    names =
      Enum.map(segments, fn
        {name, _, ctx} when is_atom(name) and is_atom(ctx) ->
          str = Atom.to_string(name)
          if String.starts_with?(str, "_"), do: :skip, else: name

        {:"::", _, [{name, _, ctx} | _rest]} when is_atom(name) and is_atom(ctx) ->
          str = Atom.to_string(name)
          if String.starts_with?(str, "_"), do: :skip, else: name

        _ ->
          :skip
      end)

    if Enum.any?(names, &(&1 == :skip)), do: :error, else: {:ok, names}
  end

  defp body_contains_same_binary?(body, target_var_names) do
    {_, found} =
      Macro.prewalk(body, false, fn
        node, true ->
          {node, true}

        node, false ->
          case extract_binary_segment_names(node) do
            {:ok, ^target_var_names} -> {node, true}
            _ -> {node, false}
          end
      end)

    found
  end

  defp build_binary_issue(var_names, meta) do
    vars_str = Enum.map_join(var_names, ", ", &to_string/1)

    %Issue{
      rule: :no_destructure_reconstruct,
      message: """
      Binary `<<#{vars_str}>>` is destructured and then reassembled \
      into the same binary.

      Use a plain parameter binding instead of destructuring and \
      reconstructing the binary.\
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp fix_binary_pattern_body(pattern, body, extra_ast) do
    with {:ok, var_names} when length(var_names) >= 2 <-
           extract_binary_segment_names(pattern),
         true <- body_contains_same_binary?(body, var_names) do
      binding_var = {:string, [], nil}
      new_body = replace_reconstructed_binary(body, var_names, binding_var)

      used = collect_variable_names(new_body)

      used =
        if extra_ast, do: MapSet.union(used, collect_variable_names(extra_ast)), else: used

      {:<<>>, bin_meta, segments} = pattern

      new_segments =
        Enum.map(segments, fn
          {name, meta, ctx} = node when is_atom(name) and is_atom(ctx) ->
            str = Atom.to_string(name)
            if String.starts_with?(str, "_") or MapSet.member?(used, name),
              do: node,
              else: {:_, meta, ctx}

          {:"::", meta, [{name, nmeta, nctx} | rest] = seg} when is_atom(name) and
                                                                    is_atom(nctx) ->
            str = Atom.to_string(name)

            if String.starts_with?(str, "_") or MapSet.member?(used, name),
              do: {:"::", meta, seg},
              else: {:"::", meta, [{:_, nmeta, nctx} | rest]}

          other ->
            other
        end)

      new_pattern = {:<<>>, bin_meta, new_segments}
      {:fixed, {:=, [], [new_pattern, binding_var]}, new_body}
    else
      _ -> :no_fix
    end
  end

  defp replace_reconstructed_binary(body, target_var_names, replacement) do
    Macro.prewalk(body, fn
      {:<<>>, _, _} = node ->
        case extract_binary_segment_names(node) do
          {:ok, ^target_var_names} -> replacement
          _ -> node
        end

      {:__block__, _, [{:<<>>, _, _} = inner]} = node ->
        case extract_binary_segment_names(inner) do
          {:ok, ^target_var_names} -> replacement
          _ -> node
        end

      node ->
        node
    end)
  end
end
