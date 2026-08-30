defmodule Credence.Semantic.FixRemoteCallInPattern do
  @moduledoc """
  Fixes `cannot invoke remote function ... inside a match` compile errors.

  LLMs repeatedly write `{state.ref, ...}` inside `receive`/`case`/function-head
  patterns, causing the compile error:

      "cannot invoke remote function state.ref/0 inside a match"

  No existing rule covers map-field-access in pattern position (only
  `no_remote_function_in_guard` covers guards). The fix is deterministic:
  extract the remote-call expression to a local variable before the pattern
  context and pin it in the pattern.

  ## Before

      def wait(state) do
        receive do
          {state.ref, :done, result} -> result
        end
      end

  ## After

      def wait(state) do
        ref = state.ref
        receive do
          {^ref, :done, result} -> result
        end
      end

  ## Bad

      defmodule ExFRCIP do
        def wait(state, ref) do
          receive do
            {state.ref, :done} -> ref
          end
        end
      end

  ## Good

      defmodule ExFRCIP do
        def wait(state, ref) do
          ref_1 = state.ref

          receive do
            {^ref_1, :done} -> ref
          end
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "cannot invoke remote function "
  @match_suffix " inside a match"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @match_prefix) and String.ends_with?(msg, @match_suffix)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_remote_call_in_pattern,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, receiver, field} <- extract_remote_fn(diagnostic.message) do
      diag_line = line(diagnostic)

      # Build the stripped remote call for comparison
      remote_call_stripped = strip_meta(build_remote_call_ast(receiver, field))

      # Names for introduced bindings must not collide with any variable already
      # in the source, or the hoisted binding would shadow it and change what
      # otherwise-valid code means.
      pin_var = fresh_var_name(ast, field)
      new_var = fresh_var_name(ast, :"new_#{field}")

      # Walk executable AST only: quoted AST is data and cannot be the source
      # of a compiler diagnostic from this compilation.
      {new_ast, changed} =
        prewalk_unquoted(ast, false, fn
          # Handle var.field = expr assignment inside a block
          {:__block__, block_meta, exprs} = node, acc when is_list(exprs) ->
            with true <- var_receiver?(receiver),
                 {:ok, new_exprs} <-
                   try_fix_block_assignment(
                     exprs,
                     remote_call_stripped,
                     receiver,
                     new_var,
                     diag_line
                   ) do
              {{:__block__, block_meta, new_exprs}, true}
            else
              _ -> {node, acc}
            end

          {:receive, meta, [clauses_kw]} = node, acc when is_list(clauses_kw) ->
            case try_fix_clauses(clauses_kw, remote_call_stripped, pin_var, diag_line) do
              {:ok, new_clauses, binding} ->
                # Wrap: binding + receive
                {{:__block__, [], [binding, {:receive, meta, [new_clauses]}]}, true}

              :error ->
                {node, acc}
            end

          {:case, meta, [subject, clauses_kw]} = node, acc when is_list(clauses_kw) ->
            case try_fix_clauses(clauses_kw, remote_call_stripped, pin_var, diag_line) do
              {:ok, new_clauses, binding} ->
                {{:__block__, [], [binding, {:case, meta, [subject, new_clauses]}]}, true}

              :error ->
                {node, acc}
            end

          {:fn, meta, clauses} = node, acc when is_list(clauses) ->
            case try_fix_arrow_clauses(
                   clauses,
                   remote_call_stripped,
                   pin_var,
                   diag_line
                 ) do
              {:ok, new_clauses, binding} ->
                {{:__block__, [], [binding, {:fn, meta, new_clauses}]}, true}

              :error ->
                {node, acc}
            end

          {:with, meta, args} = node, acc when is_list(args) ->
            case try_fix_with(args, remote_call_stripped, pin_var, diag_line) do
              {:ok, new_args, binding} ->
                {{:__block__, [], [binding, {:with, meta, new_args}]}, true}

              :error ->
                {node, acc}
            end

          {kind, meta, [head, body]} = node, acc when kind in [:def, :defp] ->
            case try_fix_function_head(head, remote_call_stripped, pin_var, diag_line) do
              {:ok, new_head} -> {{kind, meta, [new_head, body]}, true}
              :error -> {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed do
        result = Sourceror.to_string(new_ast)
        if result == source, do: source, else: result
      else
        source
      end
    else
      _ -> source
    end
  end

  defp try_fix_clauses(clauses_kw, remote_call_stripped, var_name, diag_line) do
    pin_ast = {:^, [line: diag_line], [{var_name, [line: diag_line], nil}]}

    # Reconstruct the binding from the stripped remote call
    {{:., [], [receiver_ast, field]}, _, _} = remote_call_stripped
    binding_rhs = {{:., [], [receiver_ast, field]}, [no_parens: true], []}
    binding = {:=, [line: diag_line], [{var_name, [line: diag_line], nil}, binding_rhs]}

    {new_kw, changed} =
      Enum.map_reduce(clauses_kw, false, fn
        {{:__block__, do_meta, [:do]}, clause_entries}, acc when is_list(clause_entries) ->
          {new_entries, entry_changed} =
            Enum.map_reduce(clause_entries, false, fn
              {:->, arrow_meta, [patterns, body]}, eacc ->
                {new_patterns, pat_changed} =
                  Enum.map_reduce(patterns, false, fn pattern, pacc ->
                    {new_p, c} =
                      replace_remote_in_pattern(
                        pattern,
                        remote_call_stripped,
                        pin_ast,
                        diag_line
                      )

                    {new_p, pacc or c}
                  end)

                if pat_changed do
                  {{:->, arrow_meta, [new_patterns, body]}, true}
                else
                  {{:->, arrow_meta, [patterns, body]}, eacc}
                end

              other, eacc ->
                {other, eacc}
            end)

          {{{:__block__, do_meta, [:do]}, new_entries}, acc or entry_changed}

        entry, acc ->
          {entry, acc}
      end)

    if changed, do: {:ok, new_kw, binding}, else: :error
  end

  defp try_fix_arrow_clauses(clauses, remote_call_stripped, var_name, diag_line) do
    pin_ast = {:^, [line: diag_line], [{var_name, [line: diag_line], nil}]}
    binding = build_binding(remote_call_stripped, var_name, diag_line)

    {new_clauses, changed} =
      Enum.map_reduce(clauses, false, fn
        {:->, meta, [patterns, body]} = clause, acc ->
          {new_patterns, pattern_changed} =
            Enum.map_reduce(patterns, false, fn pattern, pattern_acc ->
              {new_pattern, changed} =
                replace_remote_in_pattern(
                  pattern,
                  remote_call_stripped,
                  pin_ast,
                  diag_line
                )

              {new_pattern, pattern_acc or changed}
            end)

          if pattern_changed do
            {{:->, meta, [new_patterns, body]}, true}
          else
            {clause, acc}
          end

        clause, acc ->
          {clause, acc}
      end)

    if changed, do: {:ok, new_clauses, binding}, else: :error
  end

  defp try_fix_with(args, remote_call_stripped, var_name, diag_line) do
    pin_ast = {:^, [line: diag_line], [{var_name, [line: diag_line], nil}]}
    binding = build_binding(remote_call_stripped, var_name, diag_line)

    {new_args, changed} =
      Enum.map_reduce(args, false, fn
        {:<-, meta, [pattern, value]} = clause, acc ->
          {new_pattern, pattern_changed} =
            replace_remote_in_pattern(pattern, remote_call_stripped, pin_ast, diag_line)

          if pattern_changed do
            {{:<-, meta, [new_pattern, value]}, true}
          else
            {clause, acc}
          end

        arg, acc ->
          {arg, acc}
      end)

    if changed, do: {:ok, new_args, binding}, else: :error
  end

  defp try_fix_function_head(head, remote_call_stripped, var_name, diag_line) do
    var = {var_name, [line: diag_line], nil}

    {new_head, changed} =
      replace_remote_in_pattern(head, remote_call_stripped, var, diag_line)

    if changed do
      {{:., [], [receiver_ast, field]}, _, _} = remote_call_stripped
      rhs = {{:., [], [receiver_ast, field]}, [no_parens: true], []}
      equality = {:==, [line: diag_line], [var, rhs]}

      guarded_head =
        case new_head do
          {:when, meta, args} ->
            {patterns, [guard]} = Enum.split(args, -1)
            {:when, meta, patterns ++ [{:and, [line: diag_line], [guard, equality]}]}

          _ ->
            {:when, [line: diag_line], [new_head, equality]}
        end

      {:ok, guarded_head}
    else
      :error
    end
  end

  defp build_binding(remote_call_stripped, var_name, diag_line) do
    {{:., [], [receiver_ast, field]}, _, _} = remote_call_stripped
    binding_rhs = {{:., [], [receiver_ast, field]}, [no_parens: true], []}

    {:=, [line: diag_line], [{var_name, [line: diag_line], nil}, binding_rhs]}
  end

  # Fix var.field = expr assignment: rewrite to new_<field> = expr and
  # replace bare var references in subsequent expressions with %{var | field: new_<field}.
  defp try_fix_block_assignment(exprs, remote_call_stripped, receiver, new_var_name, diag_line) do
    {{:., [], [_, field]}, _, _} = remote_call_stripped

    with {:ok, index, rhs} <-
           find_remote_assignment(exprs, remote_call_stripped, diag_line),
         false <- receiver_rebound_after?(exprs, index, receiver) do
      new_var = {new_var_name, [line: diag_line], nil}
      new_binding = {:=, [line: diag_line], [new_var, rhs]}

      receiver_ast = build_receiver_ast(receiver)
      map_update = build_map_update(receiver_ast, field, new_var, diag_line)

      new_exprs =
        exprs
        |> Enum.with_index()
        |> Enum.map(fn
          {_, ^index} ->
            new_binding

          {expr, i} when i > index ->
            replace_receiver_reads(
              expr,
              receiver,
              field,
              new_var,
              map_update
            )

          {expr, _} ->
            expr
        end)

      {:ok, new_exprs}
    else
      _ -> :error
    end
  end

  # True when any expression after `index` uses the bare receiver in a binding
  # position: the LHS of `=`, a clause head (patterns and guard) of `->`, or
  # the LHS of `<-`. Replacing the receiver there would either change a binding
  # or put map-update syntax in a pattern/guard, so the fix must not run.
  defp receiver_rebound_after?(exprs, index, receiver) do
    receiver_stripped = strip_meta(build_receiver_ast(receiver))

    exprs
    |> Enum.drop(index + 1)
    |> Enum.any?(fn expr ->
      {_, found} =
        Macro.prewalk(expr, false, fn
          {:=, _, [lhs, _]} = n, acc -> {n, acc or mentions_var?(lhs, receiver_stripped)}
          {:->, _, [head, _]} = n, acc -> {n, acc or mentions_var?(head, receiver_stripped)}
          {:<-, _, [lhs, _]} = n, acc -> {n, acc or mentions_var?(lhs, receiver_stripped)}
          n, acc -> {n, acc}
        end)

      found
    end)
  end

  defp mentions_var?(ast, var_stripped) do
    {_, found} =
      Macro.prewalk(ast, false, fn n, acc ->
        {n, acc or strip_meta(n) == var_stripped}
      end)

    found
  end

  # The block-assignment rewrite only makes sense when the receiver is a plain
  # local variable: `%{Some.Alias | field: v}` is never what alias-receiver
  # code meant, and special forms are not rebindable maps.
  @special_forms [:__MODULE__, :__ENV__, :__DIR__, :__CALLER__, :__STACKTRACE__]

  defp var_receiver?([single]) when single not in @special_forms do
    single |> Atom.to_string() |> String.match?(~r/^[a-z_]/)
  end

  defp var_receiver?(_), do: false

  # A variable name not used anywhere in the source, derived from `base`.
  defp fresh_var_name(ast, base) do
    used = collect_var_names(ast)

    if base in used do
      Enum.find_value(1..1000, fn i ->
        candidate = :"#{base}_#{i}"
        if candidate not in used, do: candidate
      end)
    else
      base
    end
  end

  defp collect_var_names(ast) do
    {_, names} =
      Macro.prewalk(ast, MapSet.new(), fn
        {name, _meta, ctx} = n, acc when is_atom(name) and is_atom(ctx) ->
          {n, MapSet.put(acc, name)}

        n, acc ->
          {n, acc}
      end)

    names
  end

  # Find the first assignment with a remote-call LHS matching remote_call_stripped.
  defp find_remote_assignment(exprs, remote_call_stripped, diag_line) do
    exprs
    |> Enum.with_index()
    |> Enum.find_value(:error, fn
      {{:=, _meta, [lhs, rhs]}, index} ->
        if strip_meta(lhs) == remote_call_stripped and at_line?(lhs, diag_line) do
          {:ok, index, rhs}
        end

      _ ->
        nil
    end)
  end

  # Replace bare receiver references with the updated map and reads of the
  # assigned field with its new value.
  defp replace_receiver_reads(ast, receiver, field, new_var, replacement) do
    receiver_stripped = strip_meta(build_receiver_ast(receiver))
    do_replace_receiver_reads(ast, receiver_stripped, field, new_var, replacement)
  end

  defp do_replace_receiver_reads(node, recv, field, new_var, repl) do
    case node do
      {:quote, _, _} ->
        node

      # 3-tuple with list args (most common AST form)
      {form, meta, args} when is_list(args) ->
        case dot_call_field(form, recv) do
          ^field ->
            new_var

          other_field when is_atom(other_field) and not is_nil(other_field) ->
            node

          nil ->
            {form, meta,
             Enum.map(args, &do_replace_receiver_reads(&1, recv, field, new_var, repl))}
        end

      # 3-tuple with non-list arg (leaf like {:state, [], nil})
      {form, meta, arg} ->
        if strip_meta(node) == recv do
          repl
        else
          {form, meta, do_replace_receiver_reads(arg, recv, field, new_var, repl)}
        end

      # 2-tuple
      {left, right} ->
        {do_replace_receiver_reads(left, recv, field, new_var, repl),
         do_replace_receiver_reads(right, recv, field, new_var, repl)}

      # List
      list when is_list(list) ->
        Enum.map(list, &do_replace_receiver_reads(&1, recv, field, new_var, repl))

      # Leaf
      _ ->
        node
    end
  end

  # Check if form is {:., _, [recv_ast, _field]} and strip_meta(recv_ast) == recv
  defp dot_call_field({:., _, [recv_ast, field]}, recv) do
    if strip_meta(recv_ast) == recv, do: field
  end

  defp dot_call_field(_, _), do: nil

  # Build the bare receiver AST (e.g. {:state, [], nil} for [:state])
  defp build_receiver_ast(receiver) do
    case receiver do
      [single] -> {single, [], nil}
      parts -> {:__aliases__, [], parts}
    end
  end

  # Build %{receiver | field: new_var} AST
  defp build_map_update(receiver_ast, field, new_var, line) do
    {:%{}, [line: line],
     [
       {:|, [line: line],
        [
          receiver_ast,
          [{{:__block__, [format: :keyword, line: line], [field]}, new_var}]
        ]}
     ]}
  end

  # Replace remote call nodes in a pattern with a pinned variable.
  defp replace_remote_in_pattern(node, remote_call_stripped, pin_ast, diag_line) do
    if strip_meta(node) == remote_call_stripped and at_line?(node, diag_line) do
      {pin_ast, true}
    else
      case node do
        # Clause guard: dot access like `state.ref` is VALID in a guard, and a
        # pin would not be — rewrite only the pattern part, never the guard.
        {:when, meta, args} when is_list(args) ->
          {patterns, [guard]} = Enum.split(args, -1)

          {new_patterns, changed} =
            Enum.map_reduce(patterns, false, fn pat, acc ->
              {new_pat, c} =
                replace_remote_in_pattern(pat, remote_call_stripped, pin_ast, diag_line)

              {new_pat, acc or c}
            end)

          {{:when, meta, new_patterns ++ [guard]}, changed}

        {form, meta, args} when is_list(args) ->
          {new_args, changed} =
            Enum.map_reduce(args, false, fn arg, acc ->
              {new_arg, c} =
                replace_remote_in_pattern(arg, remote_call_stripped, pin_ast, diag_line)

              {new_arg, acc or c}
            end)

          {{form, meta, new_args}, changed}

        {form, meta, arg} ->
          # 3-tuple with non-list arg (leaf like {:state, [], nil})
          {new_arg, changed} =
            replace_remote_in_pattern(arg, remote_call_stripped, pin_ast, diag_line)

          {{form, meta, new_arg}, changed}

        {left, right} ->
          {new_left, lc} =
            replace_remote_in_pattern(left, remote_call_stripped, pin_ast, diag_line)

          {new_right, rc} =
            replace_remote_in_pattern(right, remote_call_stripped, pin_ast, diag_line)

          {{new_left, new_right}, lc or rc}

        list when is_list(list) ->
          {new_list, changed} =
            Enum.map_reduce(list, false, fn elem, acc ->
              {new_elem, c} =
                replace_remote_in_pattern(elem, remote_call_stripped, pin_ast, diag_line)

              {new_elem, acc or c}
            end)

          {new_list, changed}

        _ ->
          {node, false}
      end
    end
  end

  defp at_line?({_, meta, _}, line) when is_list(meta), do: meta[:line] == line
  defp at_line?(_, _), do: false

  defp prewalk_unquoted(ast, acc, fun) do
    {ast, acc} = fun.(ast, acc)

    case ast do
      {:quote, _, _} ->
        {ast, acc}

      tuple when is_tuple(tuple) ->
        {items, acc} =
          tuple
          |> Tuple.to_list()
          |> Enum.map_reduce(acc, &prewalk_unquoted(&1, &2, fun))

        {List.to_tuple(items), acc}

      list when is_list(list) ->
        Enum.map_reduce(list, acc, &prewalk_unquoted(&1, &2, fun))

      _ ->
        {ast, acc}
    end
  end

  # Strip all metadata from an AST for structural comparison.
  # Uses postwalk so children are stripped before parents.
  defp strip_meta(ast) do
    Macro.postwalk(ast, fn
      {form, _meta, args} when is_list(args) -> {form, [], args}
      {form, _meta, arg} -> {form, [], arg}
      other -> other
    end)
  end

  # Build the AST for the remote call, e.g. `state.ref` becomes
  # {{:., [], [{:state, [], nil}, :ref]}, [no_parens: true], []}
  defp build_remote_call_ast(receiver, field) do
    case receiver do
      [single] ->
        {{:., [], [{single, [], nil}, field]}, [no_parens: true], []}

      [first | rest] ->
        alias_ast = {:__aliases__, [], [first | rest]}
        {{:., [], [alias_ast, field]}, [no_parens: true], []}
    end
  end

  # Extract receiver and field from message like
  # "cannot invoke remote function state.ref/0 inside a match"
  defp extract_remote_fn(msg) do
    case Regex.run(
           ~r/cannot invoke remote function ([A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)*)\.(\w+)\/\d+ inside a match/,
           msg
         ) do
      [_, receiver_str, field_str] ->
        receiver =
          receiver_str
          |> String.split(".")
          |> Enum.map(&String.to_atom/1)

        {:ok, receiver, String.to_atom(field_str)}

      _ ->
        :error
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
