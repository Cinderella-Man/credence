defmodule Credence.Semantic.NoMapsetMemberInGuard do
  @moduledoc """
  Fixes `MapSet.member?/2` used inside a guard expression.

  The Elixir compiler rejects remote function calls in guards:

      "cannot invoke remote function MapSet.member?/2 inside a guard"

  The deterministic fix extracts the `MapSet.member?` call from the `when`
  guard into an `if` inside the function body, merging any same-name/arity
  fallback clause into the `else` branch:

  ## Before

      defp cycle_check(graph, node, visited, rec_stack)
           when MapSet.member?(rec_stack, node), do: true

      defp cycle_check(graph, node, visited, rec_stack) do
        ...
      end

  ## After

      defp cycle_check(graph, node, visited, rec_stack) do
        if MapSet.member?(rec_stack, node) do
          true
        else
          ...
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "cannot invoke remote function MapSet.member?/2 inside a guard"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    msg == @match_msg
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_mapset_member_in_guard,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:__block__, meta, stmts} = node, acc ->
            case merge_mapset_guard(stmts) do
              {:ok, new_stmts} -> {{:__block__, meta, new_stmts}, true}
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

  # Find a def/defp clause with `when MapSet.member?` guard and merge it
  # with a matching fallback clause (same name/arity, no guard).
  defp merge_mapset_guard(stmts) do
    stmts
    |> Enum.with_index()
    |> Enum.find_value(:error, fn
      {{kind, _meta, [{:when, when_meta, [head, guard]}, body_kw]}, idx}
      when kind in [:def, :defp] ->
        case guard do
          {{:., _, [{:__aliases__, _, [:MapSet]}, :member?]}, _, _} ->
            {fn_name, fn_arity} = fn_name_arity(head)

            case find_fallback(stmts, idx + 1, kind, fn_name, fn_arity) do
              {:ok, fallback_idx, fallback_body, fallback_meta} ->
                guarded_body = extract_do_body(body_kw)
                base_line = when_meta[:line] || 1

                if_node =
                  {:if,
                   [
                     line: base_line,
                     column: 3,
                     do: [line: base_line, column: 50],
                     end: [line: base_line + 20, column: 5]
                   ],
                   [
                     guard,
                     [
                       {{:__block__, [], [:do]}, guarded_body},
                       {{:__block__, [], [:else]}, fallback_body}
                     ]
                   ]}

                clean_head = strip_when(head)
                new_body = [{{:__block__, [], [:do]}, if_node}]

                new_meta =
                  (fallback_meta || [])
                  |> Keyword.put(:do, [line: base_line, column: 53])
                  |> Keyword.put(:end, [line: base_line + 20, column: 3])

                new_clause = {kind, new_meta, [clean_head, new_body]}

                new_stmts =
                  stmts
                  |> List.replace_at(idx, new_clause)
                  |> List.delete_at(fallback_idx)

                {:ok, new_stmts}

              :error ->
                nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end)
  end

  # Find a clause of `kind` with matching `name`/`arity` and no guard,
  # starting from `start_idx`.
  defp find_fallback(stmts, start_idx, kind, name, arity) do
    stmts
    |> Enum.with_index()
    |> Enum.find_value(:error, fn
      {{^kind, meta, [{^name, _, args}, body_kw]}, idx}
      when idx >= start_idx and is_list(args) and length(args) == arity ->
        {:ok, idx, extract_do_body(body_kw), meta}

      _ ->
        nil
    end)
  end

  defp extract_do_body([{{:__block__, _, [:do]}, body} | _]), do: body
  defp extract_do_body(body), do: body

  defp strip_when({:when, _, [head, _]}), do: head
  defp strip_when(head), do: head

  defp fn_name_arity({name, _, args}) when is_list(args), do: {name, length(args)}

  defp fn_name_arity({:when, _, [{name, _, args}, _]}) when is_list(args),
    do: {name, length(args)}

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
