defmodule Credence.Semantic.NoSplitFunctionDefinition do
  @moduledoc """
  Fixes the compiler warning about split function definitions.

  LLMs frequently generate split function definitions — the same name+arity
  in separate non-adjacent blocks with different bodies. The Elixir compiler
  warns:

      function <name>/<arity> has multiple clauses and they are not adjacent

  Under `--warnings-as-errors` this blocks compilation. The fix reorders the
  module body so all clauses for the same function are contiguous, placing
  intervening definitions after the merged group.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "has multiple clauses and they are not adjacent"
  @extract_pattern ~r/function (\w+)\/(\d+) has multiple clauses and they are not adjacent/

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :no_split_function_definition,
      message: msg,
      meta: %{line: line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    with [_, name_str, arity_str] <- Regex.run(@extract_pattern, msg),
         name = String.to_atom(name_str),
         arity = String.to_integer(arity_str),
         {:ok, ast} <- Sourceror.parse_string(source) do
      result = merge_split_clauses(ast, name, arity)
      if result == ast, do: source, else: Sourceror.to_string(result)
    else
      _ -> source
    end
  end

  # Walk the AST and reorder defmodule bodies so split function clauses
  # with the target name+arity are grouped together.
  defp merge_split_clauses(ast, name, arity) do
    Macro.prewalk(ast, fn
      {:defmodule, mod_meta, [alias_node, body_kw]} = node when is_list(body_kw) ->
        case extract_do_body(body_kw) do
          {:ok, {:__block__, body_meta, stmts}} ->
            new_stmts = group_matching_clauses(stmts, name, arity)

            if new_stmts != stmts do
              new_body = {:__block__, body_meta, new_stmts}
              {:defmodule, mod_meta, [alias_node, replace_do_body(body_kw, new_body)]}
            else
              node
            end

          _ ->
            node
        end

      node ->
        node
    end)
  end

  defp extract_do_body(kw) when is_list(kw) do
    Enum.find_value(kw, :error, fn
      {{:__block__, _, [:do]}, body} -> {:ok, body}
      {:do, body} -> {:ok, body}
      _ -> nil
    end)
  end

  defp replace_do_body(kw, new_body) when is_list(kw) do
    Enum.map(kw, fn
      {{:__block__, meta, [:do]}, _} -> {{:__block__, meta, [:do]}, new_body}
      {:do, _} -> {:do, new_body}
      other -> other
    end)
  end

  # In `stmts`, find all def/defp with `{target_name, target_arity}`.
  # If they are non-adjacent (split), reorder so all matching clauses are
  # contiguous — the intervening non-matching statements are placed after.
  defp group_matching_clauses(stmts, target_name, target_arity) do
    target_key = {target_name, target_arity}

    matching_indices =
      stmts
      |> Enum.with_index()
      |> Enum.filter(fn {stmt, _} -> function_key(stmt) == target_key end)
      |> Enum.map(fn {_, idx} -> idx end)

    case matching_indices do
      [] ->
        stmts

      [_] ->
        stmts

      [first | _] ->
        last = List.last(matching_indices)

        all_adjacent? =
          matching_indices
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.all?(fn [a, b] -> b == a + 1 end)

        if all_adjacent? do
          stmts
        else
          {before_span, rest} = Enum.split(stmts, first)
          span_len = last - first + 1
          {span, after_span} = Enum.split(rest, span_len)

          {matching, others} =
            Enum.split_with(span, fn stmt -> function_key(stmt) == target_key end)

          before_span ++ matching ++ others ++ after_span
        end
    end
  end

  # Extract {name, arity} from a def/defp AST node.  Requires a body
  # (bodiless forward declarations are skipped).
  defp function_key({kind, _, [{:when, _, [{name, _, args} | _]}, _body]})
       when kind in [:def, :defp] and is_atom(name) do
    {name, if(is_list(args), do: length(args), else: 0)}
  end

  defp function_key({kind, _, [{name, _, args}, _body]})
       when kind in [:def, :defp] and is_atom(name) do
    {name, if(is_list(args), do: length(args), else: 0)}
  end

  defp function_key(_), do: nil

  defp line({line, _col}) when is_integer(line), do: line
  defp line(line) when is_integer(line), do: line
end
