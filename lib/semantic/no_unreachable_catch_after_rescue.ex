defmodule Credence.Semantic.NoUnreachableCatchAfterRescue do
  @moduledoc """
  Deletes a `catch :error, pattern ->` clause the compiler has proven dead
  because an earlier catch-all `rescue` clause already matches it.

  LLM-generated `try` blocks (and `def`-level `rescue`/`catch` bodies) often
  pair a catch-all `rescue e ->` with `catch :error, reason ->`. A `rescue`
  without an `in` qualifier catches *every* error-class exception, and the
  compiler places the rescue clauses ahead of the user's `catch` clauses — so
  the `:error` catch clause can never run. Elixir says so:

      warning: this clause cannot match because a previous clause at line 6
      matches the same pattern as this clause

  which fails a `--warnings-as-errors` build. Deleting the dead clause is
  behaviour-preserving: it never executed, and the rescue catch-all that
  shadows it is left exactly as it was.

  ## Bad

      defmodule CredenceUnreachableCatchLiveReproNUCAR do
        def run(f) do
          try do
            f.()
          rescue
            e -> {:error, e}
          catch
            :error, reason -> {:error, reason}
          end
        end
      end

  ## Good

      defmodule CredenceUnreachableCatchLiveReproNUCAR do
        def run(f) do
          try do
            f.()
          rescue
            e -> {:error, e}
          end
        end
      end
  """

  use Credence.Semantic.Rule

  alias Credence.Issue

  # Captures the line of the *previous* clause the compiler says already
  # matches. `fix/2` requires that line to hold the shadowing `rescue`
  # catch-all, which is what ties this generic warning to the try/rescue shape.
  @match_re ~r/this clause cannot match because a previous clause at line (\d+) matches the same pattern as this clause/

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    Regex.match?(@match_re, msg)
  end

  def match?(_), do: false

  @doc """
  Only report diagnostics this rule can actually fix. The matched message is
  emitted for any pair of identical clauses (duplicate `case` clauses, for
  instance), so attribution is decided by re-running the rewrite.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_unreachable_catch_after_rescue,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{severity: :warning, message: msg} = diagnostic) when is_binary(msg) do
    with [_, previous] <- Regex.run(@match_re, msg),
         target_line when is_integer(target_line) <- line(diagnostic),
         {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, new_ast} <- delete_dead_catch(ast, target_line, String.to_integer(previous)) do
      Sourceror.to_string(new_ast)
    else
      _ -> source
    end
  end

  def fix(source, _diagnostic), do: source

  # Delete the flagged `:error, pattern ->` catch clause from the `try` (or
  # `def`-level rescue body) that owns both the flagged line and the shadowing
  # rescue catch-all. Returns `:error` unless exactly one clause was deleted, so
  # an ambiguous line leaves the source untouched.
  defp delete_dead_catch(ast, target_line, previous_line) do
    {new_ast, deleted} =
      Macro.prewalk(ast, 0, fn
        {form, meta, args} = node, acc when is_list(args) and args != [] ->
          blocks = List.last(args)

          with true <- rescue_catchall_on_line?(blocks, previous_line),
               {:ok, new_blocks, count} <- drop_catch_clause(blocks, target_line) do
            {{form, meta, List.replace_at(args, length(args) - 1, new_blocks)}, acc + count}
          else
            _ -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    if deleted == 1, do: {:ok, new_ast}, else: :error
  end

  # True when the `rescue` section of this block list has a bare-variable
  # (or `_`) catch-all clause whose `->` sits on the line the warning named.
  defp rescue_catchall_on_line?(blocks, line) when is_list(blocks) do
    case section(blocks, :rescue) do
      {_key, clauses} when is_list(clauses) ->
        Enum.any?(clauses, fn
          {:->, meta, [[{name, _, ctx}], _body]} when is_atom(name) and is_atom(ctx) ->
            Keyword.get(meta, :line) == line

          _ ->
            false
        end)

      _ ->
        false
    end
  end

  defp rescue_catchall_on_line?(_blocks, _line), do: false

  # Drop the flagged clause from the `catch` section, dropping the whole section
  # when it would be left empty (`catch` with no clauses does not compile).
  defp drop_catch_clause(blocks, target_line) do
    with {key, clauses} when is_list(clauses) <- section(blocks, :catch),
         {[_ | _] = dead, kept} <-
           Enum.split_with(clauses, &dead_error_clause?(&1, target_line)) do
      index = Enum.find_index(blocks, &match?({^key, _}, &1))

      new_blocks =
        case kept do
          [] -> List.delete_at(blocks, index)
          _ -> List.replace_at(blocks, index, {key, kept})
        end

      {:ok, new_blocks, length(dead)}
    else
      _ -> :none
    end
  end

  # Exactly `:error, <pattern> ->` (two patterns, no guard) on the flagged line.
  defp dead_error_clause?({:->, meta, [[{:__block__, _, [:error]}, _pattern], _body]}, line) do
    Keyword.get(meta, :line) == line
  end

  defp dead_error_clause?(_clause, _line), do: false

  defp section(blocks, name) when is_list(blocks) do
    Enum.find(blocks, fn
      {{:__block__, _, [^name]}, _value} -> true
      _ -> false
    end)
  end

  defp section(_blocks, _name), do: nil

  defp line(%{position: {line, _col}}) when is_integer(line), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_diagnostic), do: nil
end
