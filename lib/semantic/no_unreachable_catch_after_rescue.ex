defmodule Credence.Semantic.NoUnreachableCatchAfterRescue do
  @moduledoc """
  Fixes unreachable `catch :error` clauses in `try` blocks that already have a
  catch-all `rescue` clause.

  LLM-generated try blocks frequently pair `rescue e ->` (catch-all) with
  `catch :error, reason ->`. Since `rescue` without an `in` qualifier catches
  *all* exceptions (which are `:error`-kind throws), the catch clause that
  also matches `:error` is unreachable dead code.

  Removing the dead catch clause preserves identical behaviour — the rescue
  catch-all already handles every exception the catch would handle.

  ## Bad

      try do
        :ok
      rescue
        e -> {:error, e}
      catch
        :error, reason -> {:error, reason}
      end

  ## Good

      try do
        :ok
      rescue
        e -> {:error, e}
      end

  ## What it deliberately does NOT touch

  - A `rescue e in SomeError ->` that is NOT a catch-all (it narrows to one
    exception type) — the catch clause may still be reachable for other kinds.
  - A `catch :exit` or `catch :throw` clause — these catch different kinds
    and are not made unreachable by a rescue catch-all.
  - A try block with no rescue clause at all.
  """

  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "this catch clause cannot match because a rescue catch-all"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_unreachable_catch_after_rescue,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      new_ast = remove_unreachable_catches(ast)

      if new_ast != ast do
        Sourceror.to_string(new_ast)
      else
        source
      end
    else
      _ -> source
    end
  end

  # Walk the AST and remove unreachable catch blocks from try expressions
  # that have a rescue catch-all. The Sourceror try shape is:
  #   {:try, meta, [kw_list]}
  # where kw_list is [{{:__block__, _, [:do]}, body}, {{:__block__, _, [:rescue]}, ...}, ...]
  defp remove_unreachable_catches(ast) do
    {new_ast, _changed} =
      Macro.prewalk(ast, false, fn
        {:try, meta, [kw_list]} = _node, acc when is_list(kw_list) ->
          if rescue_catchall?(kw_list) do
            case filter_catch_clauses(kw_list) do
              {:changed, new_kw} ->
                {{:try, meta, [new_kw]}, true}

              :unchanged ->
                {{:try, meta, [kw_list]}, acc}
            end
          else
            {{:try, meta, [kw_list]}, acc}
          end

        node, acc ->
          {node, acc}
      end)

    new_ast
  end

  # Check if the try block's rescue section has a catch-all pattern
  # (a bare variable or underscore, without an `in` qualifier).
  defp rescue_catchall?(clauses) do
    Enum.any?(clauses, fn
      {{:__block__, _, [:rescue]}, rescue_body} ->
        catchall_rescue_body?(rescue_body)

      _ ->
        false
    end)
  end

  defp catchall_rescue_body?([{:->, _, [patterns, _]} | _rest]) do
    case patterns do
      [{name, _, ctx} | _] when is_atom(name) and is_atom(ctx) -> true
      _ -> false
    end
  end

  defp catchall_rescue_body?(_), do: false

  # Remove `:error` catch clauses from the try block.
  # Returns `{:changed, new_clauses}` if any were removed, `:unchanged` otherwise.
  # If all catch clauses are removed, the entire catch block is dropped.
  defp filter_catch_clauses(clauses) do
    Enum.reduce_while(clauses, :unchanged, fn
      {{:__block__, catch_meta, [:catch]}, catch_body}, _acc ->
        filtered = remove_error_clauses(catch_body)

        if length(filtered) < length(catch_body) do
          case filtered do
            [] ->
              # All catch clauses removed — drop the entire catch block
              new_clauses = List.delete(clauses, {{:__block__, catch_meta, [:catch]}, catch_body})
              {:halt, {:changed, new_clauses}}

            _ ->
              # Some catch clauses remain — keep the catch block with remaining clauses
              new_clauses =
                List.replace_at(
                  clauses,
                  Enum.find_index(clauses, fn
                    {{:__block__, _, [:catch]}, _} -> true
                    _ -> false
                  end),
                  {{:__block__, catch_meta, [:catch]}, filtered}
                )

              {:halt, {:changed, new_clauses}}
          end
        else
          {:cont, :unchanged}
        end

      _other, acc ->
        {:cont, acc}
    end)
  end

  # Remove catch clauses that match `:error` kind from a list of arrow clauses.
  # Each clause has shape {:->, meta, [patterns_list, body]} where patterns_list
  # is a list like [{:__block__, _, [:error]}, {:reason, _, nil}].
  defp remove_error_clauses(clauses) do
    Enum.reject(clauses, fn
      {:->, _, [patterns, _body]} when is_list(patterns) ->
        error_clause?(patterns)

      _ ->
        false
    end)
  end

  defp error_clause?([{:__block__, _, [:error]} | _]), do: true
  defp error_clause?([:error | _]), do: true
  defp error_clause?(_), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
