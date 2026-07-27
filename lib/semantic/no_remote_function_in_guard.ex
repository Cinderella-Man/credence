defmodule Credence.Semantic.NoRemoteFunctionInGuard do
  @moduledoc """
  Fixes `cannot invoke remote function ... inside a guard` compile errors.

  LLMs repeatedly place non-guard-safe remote functions (e.g.
  `System.monotonic_time/1`, `DateTime.utc_now/0`) in `when` guard clauses.
  The Elixir compiler rejects this with:

      "cannot invoke remote function System.monotonic_time/1 inside a guard"

  The deterministic fix extracts the guarded `defp` clause's condition into an
  `if` inside the function body and merges any same-name/arity fallback clause
  into the `else` branch, eliminating the guard entirely.

  ## Before

      defp loop(start_time, timeout)
           when System.monotonic_time(:millisecond) - start_time >= timeout do
        :timeout
      end

      defp loop(start_time, timeout) do
        Process.sleep(10)
        loop(start_time, timeout)
      end

  ## After

      defp loop(start_time, timeout) do
        if System.monotonic_time(:millisecond) - start_time >= timeout do
          :timeout
        else
          Process.sleep(10)
          loop(start_time, timeout)
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "cannot invoke remote function "

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @match_prefix) and String.ends_with?(msg, " inside a guard")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_remote_function_in_guard,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, module, function} <- extract_remote_fn(diagnostic.message) do
      fn_alias = {:__aliases__, [], [module]}
      fn_capture = {:., [], [fn_alias, function]}
      diag_line = line(diagnostic)

      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:__block__, meta, stmts} = node, acc ->
            case transform_stmts(stmts, fn_capture, diag_line) do
              {:ok, new_stmts} -> {{:__block__, meta, new_stmts}, true}
              :error -> {node, acc}
            end

          {:case, case_meta, [subject, case_body]} = node, acc ->
            case transform_case(case_body, fn_capture, diag_line) do
              {:ok, new_body} -> {{:case, case_meta, [subject, new_body]}, true}
              :error -> {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Extract the module and function atoms from the diagnostic message.
  # "cannot invoke remote function System.monotonic_time/1 inside a guard"
  # => {:System, :monotonic_time}
  defp extract_remote_fn(msg) do
    case Regex.run(~r/cannot invoke remote function (\w+(?:\.\w+)*)\.(\w+[?!]?)\/\d+ inside a guard/, msg) do
      [_, mod_str, fun_str] ->
        module = mod_str |> String.split(".") |> Enum.map(&String.to_atom/1) |> List.last()
        {:ok, module, String.to_atom(fun_str)}

      _ ->
        :error
    end
  end

  # Transform case clauses: find a `when` guard with the remote function,
  # decompose the compound guard, and hoist the remote call into an `if`.
  defp transform_case([{{:__block__, do_meta, [:do]}, clauses}], fn_capture, diag_line) do
    wildcard_body = find_wildcard_body(clauses)

    case transform_case_clauses(clauses, fn_capture, diag_line, wildcard_body) do
      {:ok, new_clauses} -> {:ok, [{{:__block__, do_meta, [:do]}, new_clauses}]}
      :error -> :error
    end
  end

  defp transform_case(_, _, _), do: :error

  defp find_wildcard_body([]), do: :error

  defp find_wildcard_body([{:->, _, [[{:_ , _, _}], body]} | _]), do: {:ok, body}

  defp find_wildcard_body([{:->, _, [[{:__block__, _, [{:_ , _, _}]}], body]} | _]),
    do: {:ok, body}

  defp find_wildcard_body([_ | rest]), do: find_wildcard_body(rest)

  defp transform_case_clauses([], _, _, _), do: :error

  defp transform_case_clauses([clause | rest], fn_capture, diag_line, wildcard_body) do
    case try_merge_case_clause(clause, fn_capture, diag_line, wildcard_body) do
      {:ok, new_clause} -> {:ok, [new_clause | rest]}

      :error ->
        case transform_case_clauses(rest, fn_capture, diag_line, wildcard_body) do
          {:ok, new_rest} -> {:ok, [clause | new_rest]}
          :error -> :error
        end
    end
  end

  defp try_merge_case_clause(
         {:->, clause_meta, [[{:when, when_meta, [pattern, guard]}], body]},
         fn_capture,
         diag_line,
         wildcard_body
       ) do
    unless guard_contains?(guard, fn_capture) and on_line?(when_meta, diag_line) do
      throw(:no_match)
    end

    case wildcard_body do
      :error -> throw(:no_match)
      {:ok, fallback} ->
        {safe_guard, if_condition} = decompose_guard(guard, fn_capture)

        # Build the `if` around the clause body.
        # Sourceror needs :do/:end metadata to render block-style (not inline commas).
        base_meta = Keyword.take(clause_meta, [:line, :column])
        if_meta =
          base_meta
          |> Keyword.put(:do, base_meta)
          |> Keyword.put(:end, base_meta)

        if_node =
          {:if,
           if_meta,
           [
             if_condition,
             [
               {{:__block__, [], [:do]}, body},
               {{:__block__, [], [:else]}, fallback}
             ]
           ]}

        new_head =
          case safe_guard do
            nil -> pattern
            _ -> {:when, when_meta, [pattern, safe_guard]}
          end

        {:ok, {:->, clause_meta, [[new_head], if_node]}}
    end
  catch
    :no_match -> :error
  end

  defp try_merge_case_clause(_, _, _, _), do: :error

  # Try to transform a list of sibling statements (def/defp clauses).
  defp transform_stmts(stmts, fn_capture, diag_line) do
    case do_transform(stmts, fn_capture, diag_line) do
      {:ok, new_stmts} -> {:ok, new_stmts}
      :error -> :error
    end
  end

  defp do_transform([], _fn_capture, _diag_line), do: :error

  defp do_transform([stmt | rest], fn_capture, diag_line) do
    case try_struct_pattern_transform(stmt, fn_capture, diag_line) do
      {:ok, transformed} ->
        {:ok, [transformed | rest]}

      :error ->
        case try_merge(stmt, rest, fn_capture, diag_line) do
          {:ok, merged, remaining} ->
            {:ok, [merged | remaining]}

          :error ->
            case do_transform(rest, fn_capture, diag_line) do
              {:ok, new_rest} -> {:ok, [stmt | new_rest]}
              :error -> :error
            end
        end
    end
  end

  # Try to merge `clause` (a guarded def/defp) with a matching fallback clause.
  defp try_merge({kind, meta, [{:when, when_meta, [fn_head, guard]}, body_kw]}, rest, fn_capture, diag_line)
       when kind in [:def, :defp] do
    unless guard_contains?(guard, fn_capture) and on_line?(when_meta, diag_line) do
      throw(:no_match)
    end

    {name, arity} = fn_name_arity(fn_head)

    case pop_fallback(rest, kind, name, arity) do
      {:ok, fallback_body, remaining} ->
        {safe_guard, if_condition} = decompose_guard(guard, fn_capture)
        merged = build_merged(kind, meta, when_meta, fn_head, safe_guard, if_condition, body_kw, fallback_body)
        # When the safe guard is non-nil the merged clause still carries a
        # `when`, so the original fallback clause must remain to catch values
        # that do not satisfy it.  Only consume the fallback when the entire
        # guard was extracted (safe_guard == nil) — then the single merged
        # clause already matches every argument.
        kept = if safe_guard != nil, do: rest, else: remaining
        {:ok, merged, kept}

      :error ->
        throw(:no_match)
    end
  catch
    :no_match -> :error
  end

  defp try_merge(_clause, _rest, _fn_capture, _diag_line), do: :error

  # Find and remove the first clause of `kind` with matching name/arity and no guard.
  defp pop_fallback([], _kind, _name, _arity), do: :error

  defp pop_fallback([{kind, clause_meta, [fn_head, body_kw]} | rest], kind, name, arity) do
    case fn_head do
      {^name, _, args} when is_list(args) and length(args) == arity ->
        {:ok, body_kw, rest}

      {:when, _, [{^name, _, args}, _guard]} when is_list(args) and length(args) == arity ->
        case pop_fallback(rest, kind, name, arity) do
          {:ok, fallback_body, remaining} ->
            {:ok, fallback_body, [{kind, clause_meta, [fn_head, body_kw]} | remaining]}
          :error -> :error
        end

      _ ->
        case pop_fallback(rest, kind, name, arity) do
          {:ok, fallback_body, remaining} ->
            {:ok, fallback_body, [{kind, clause_meta, [fn_head, body_kw]} | remaining]}
          :error -> :error
        end
    end
  end

  defp pop_fallback([other | rest], kind, name, arity) do
    case pop_fallback(rest, kind, name, arity) do
      {:ok, fallback_body, remaining} -> {:ok, fallback_body, [other | remaining]}
      :error -> :error
    end
  end

  # Decompose a compound guard, separating the safe parts (to stay in `when`)
  # from the part containing the remote call (to become the `if` condition).
  #
  # For `and`: keep the safe side in `when`, extract the remote side to `if`.
  # For `or`: can't split safely — move the whole guard to `if`.
  # Leaf with remote call: no safe part remains — move entirely to `if`.
  defp decompose_guard({:and, meta, [left, right]}, fn_capture) do
    left_has = guard_contains?(left, fn_capture)
    right_has = guard_contains?(right, fn_capture)

    cond do
      left_has and not right_has ->
        {right, left}

      right_has and not left_has ->
        {left, right}

      # Both sides have remote calls, or neither (shouldn't happen since
      # guard_contains? already confirmed the compound has it) — can't split.
      true ->
        {nil, {:and, meta, [left, right]}}
    end
  end

  defp decompose_guard({:or, meta, [left, right]}, fn_capture) do
    if guard_contains?(left, fn_capture) or guard_contains?(right, fn_capture) do
      {nil, {:or, meta, [left, right]}}
    else
      {{:or, meta, [left, right]}, nil}
    end
  end

  defp decompose_guard(guard, fn_capture) do
    if guard_contains?(guard, fn_capture) do
      {nil, guard}
    else
      {guard, nil}
    end
  end

  # Build the merged clause with decomposed guard.
  # `safe_guard` stays in the `when` clause (nil if entire guard was extracted).
  # `if_condition` becomes the `if` condition (the remote call part).
  defp build_merged(kind, meta, when_meta, fn_head, safe_guard, if_condition, body_kw, fallback_body_kw) do
    original_body = extract_do(body_kw)
    fallback_body = extract_do(fallback_body_kw)

    # Sourceror needs :do and :end on the :if node to emit block layout.
    base = Keyword.take(meta, [:line, :column])
    if_meta =
      base
      |> Keyword.put(:do, base)
      |> Keyword.put(:end, base)

    if_node =
      {:if, if_meta,
       [
         if_condition,
         [
           {{:__block__, [format: :keyword], [:do]}, original_body},
           {{:__block__, [format: :keyword], [:else]}, fallback_body}
         ]
       ]}

    clean_head = strip_when(fn_head)

    # Re-attach the safe part of the guard if there is one.
    final_head =
      case safe_guard do
        nil -> clean_head
        _ -> {:when, when_meta, [clean_head, safe_guard]}
      end

    # Force block-style function body (not inline `do:` keyword) when the
    # output contains an `if` block.  Carry over comment metadata.
    out_meta =
      base
      |> Keyword.put(:trailing_comments, Keyword.get(meta, :trailing_comments, []))
      |> Keyword.put(:leading_comments, Keyword.get(meta, :leading_comments, []))
      |> Keyword.put(:do, base)
      |> Keyword.put(:end, base)

    new_body = [{{:__block__, [], [:do]}, if_node}]
    {kind, out_meta, [final_head, new_body]}
  end

  # Extract the body from a Sourceror keyword list [{{:__block__, _, [:do]}, body}]
  defp extract_do([{{:__block__, _, [:do]}, body} | _]), do: body
  defp extract_do(body), do: body

  # Strip the `when` from a function head: {:when, _, [actual_head, _guard]} -> actual_head
  defp strip_when({:when, _, [head, _guard]}), do: head
  defp strip_when(head), do: head

  # Get {name, arity} from a function head
  defp fn_name_arity({name, _, args}) when is_list(args), do: {name, length(args)}
  defp fn_name_arity({:when, _, [{name, _, args}, _]}) when is_list(args), do: {name, length(args)}

  # --- Struct pattern rewrite (Map.get(var, :__struct__) == Module → %Module{} = var) ---

  # Try to transform a guarded def/defp clause that uses Map.get/2 for struct
  # identity checking into one that uses a struct pattern in the function head.
  # This does NOT require a fallback clause — the guard is removed entirely.
  defp try_struct_pattern_transform(
         {kind, meta, [{:when, when_meta, [fn_head, guard]}, body_kw]},
         fn_capture,
         diag_line
       )
       when kind in [:def, :defp] do
    unless on_line?(when_meta, diag_line), do: throw(:no_struct_match)

    case fn_capture do
      {_, _, [{:__aliases__, _, [:Map]}, :get]} ->
        case extract_struct_pattern_from_guard(guard) do
          {:ok, var, module, remaining_guard} ->
            new_fn_head = rewrite_fn_head_with_struct(fn_head, var, module)

            new_clause =
              case remaining_guard do
                nil -> {kind, meta, [new_fn_head, body_kw]}
                _ -> {kind, meta, [{:when, when_meta, [new_fn_head, remaining_guard]}, body_kw]}
              end

            {:ok, new_clause}

          :error ->
            :error
        end

      _ ->
        :error
    end
  catch
    :no_struct_match -> :error
  end

  defp try_struct_pattern_transform(_, _, _), do: :error

  # Extract a Map.get(var, :__struct__) == Module identity check from a guard,
  # returning {var_atom, module_atom, remaining_guard} where remaining_guard has
  # both the struct equality check and the companion is_map(var) removed.
  defp extract_struct_pattern_from_guard(guard) do
    case find_struct_check(guard) do
      {:ok, var, module} ->
        remaining = remove_struct_guard_parts(guard, var)
        {:ok, var, module, remaining}

      :error ->
        :error
    end
  end

  # Walk the guard AST looking for Map.get(var, :__struct__) == Module.
  defp find_struct_check(guard) do
    {_guard, result} =
      Macro.prewalk(guard, :error, fn
        node, :error ->
          case match_struct_identity_eq(node) do
            {:ok, _, _} = found -> {node, found}
            :error -> {node, :error}
          end

        node, acc ->
          {node, acc}
      end)

    result
  end

  # Match `Map.get(var, :__struct__) == Module` or `Module == Map.get(var, :__struct__)`.
  defp match_struct_identity_eq({:==, _, [left, right]}) do
    case extract_struct_identity(left, right) do
      {:ok, _, _} = result -> result
      :error -> extract_struct_identity(right, left)
    end
  end

  defp match_struct_identity_eq(_), do: :error

  defp extract_struct_identity(
         {{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [{var, _, nil}, struct_key]},
         {:__aliases__, _, [module]}
       )
       when is_atom(var) do
    case struct_key do
      {:__block__, _, [:__struct__]} -> {:ok, var, module}
      :__struct__ -> {:ok, var, module}
      _ -> :error
    end
  end

  defp extract_struct_identity(_, _), do: :error

  # Remove both the Map.get struct check and any companion is_map(var) from the guard.
  defp remove_struct_guard_parts(guard, var) do
    guard
    |> flatten_and()
    |> Enum.reject(fn part -> is_struct_related_part?(part, var) end)
    |> reconstruct_and()
  end

  defp flatten_and({:and, _, [left, right]}), do: flatten_and(left) ++ flatten_and(right)
  defp flatten_and(other), do: [other]

  defp reconstruct_and([]), do: nil
  defp reconstruct_and([single]), do: single

  defp reconstruct_and(parts),
    do: Enum.reduce(parts, fn part, acc -> {:and, [], [acc, part]} end)

  defp is_struct_related_part?({:is_map, _, [{var, _, nil}]}, var) when is_atom(var), do: true

  defp is_struct_related_part?(part, var) do
    case match_struct_identity_eq(part) do
      {:ok, ^var, _} -> true
      _ -> false
    end
  end

  # Replace the matching parameter in the function head with a struct pattern.
  # `var` is the variable atom (e.g. :regex), `module` is the struct module atom.
  defp rewrite_fn_head_with_struct({name, meta, args}, var, module) do
    new_args =
      Enum.map(args, fn
        {^var, vmeta, nil} ->
          struct_pattern = {:%, [], [{:__aliases__, [], [module]}, {:%{}, [], []}]}
          {:=, [], [struct_pattern, {var, vmeta, nil}]}

        other ->
          other
      end)

    {name, meta, new_args}
  end

  # Check if a guard expression contains the given remote function call.
  # fn_capture is {:., [], [{:__aliases__, [], [Module]}, :function]}.
  # We compare metadata-insensitively: strip metadata from the AST dot node.
  defp guard_contains?(guard, {_, _, [{:__aliases__, _, [mod]}, fun]}) do
    {_guard, found} =
      Macro.prewalk(guard, false, fn
        {{:., _, [{:__aliases__, _, [ast_mod]}, ast_fun]}, _meta, _args} = node, _acc ->
          {node, ast_mod == mod and ast_fun == fun}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Check if a node's metadata line matches the diagnostic line
  defp on_line?(meta, diag_line) when is_list(meta) do
    Keyword.get(meta, :line) == diag_line
  end

  defp on_line?(_, _), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
