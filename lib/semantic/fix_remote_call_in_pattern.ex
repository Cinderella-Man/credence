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

      # Walk the AST, find pattern contexts and fix them
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:receive, meta, [clauses_kw]} = node, acc when is_list(clauses_kw) ->
            case try_fix_clauses(clauses_kw, remote_call_stripped, field, diag_line) do
              {:ok, new_clauses, binding} ->
                # Wrap: binding + receive
                {{:__block__, [], [binding, {:receive, meta, [new_clauses]}]}, true}

              :error ->
                {node, acc}
            end

          {:case, meta, [subject, clauses_kw]} = node, acc when is_list(clauses_kw) ->
            case try_fix_clauses(clauses_kw, remote_call_stripped, field, diag_line) do
              {:ok, new_clauses, binding} ->
                {{:__block__, [], [binding, {:case, meta, [subject, new_clauses]}]}, true}

              :error ->
                {node, acc}
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

  defp try_fix_clauses(clauses_kw, remote_call_stripped, field, diag_line) do
    var_name = field
    pin_ast = {:^, [line: diag_line], [{var_name, [line: diag_line], nil}]}

    # Reconstruct the binding from the stripped remote call
    {{:., [], [receiver_ast, ^field]}, _, _} = remote_call_stripped
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
                    {new_p, c} = replace_remote_in_pattern(pattern, remote_call_stripped, pin_ast)
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

  # Replace remote call nodes in a pattern with a pinned variable.
  defp replace_remote_in_pattern(node, remote_call_stripped, pin_ast) do
    if strip_meta(node) == remote_call_stripped do
      {pin_ast, true}
    else
      case node do
        {form, meta, args} when is_list(args) ->
          {new_args, changed} =
            Enum.map_reduce(args, false, fn arg, acc ->
              {new_arg, c} = replace_remote_in_pattern(arg, remote_call_stripped, pin_ast)
              {new_arg, acc or c}
            end)

          {{form, meta, new_args}, changed}

        {form, meta, arg} ->
          # 3-tuple with non-list arg (leaf like {:state, [], nil})
          {new_arg, changed} = replace_remote_in_pattern(arg, remote_call_stripped, pin_ast)
          {{form, meta, new_arg}, changed}

        {left, right} ->
          {new_left, lc} = replace_remote_in_pattern(left, remote_call_stripped, pin_ast)
          {new_right, rc} = replace_remote_in_pattern(right, remote_call_stripped, pin_ast)
          {{new_left, new_right}, lc or rc}

        list when is_list(list) ->
          {new_list, changed} =
            Enum.map_reduce(list, false, fn elem, acc ->
              {new_elem, c} = replace_remote_in_pattern(elem, remote_call_stripped, pin_ast)
              {new_elem, acc or c}
            end)

          {new_list, changed}

        _ ->
          {node, false}
      end
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
