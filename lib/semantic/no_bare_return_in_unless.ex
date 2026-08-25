defmodule Credence.Semantic.NoBareReturnInUnless do
  @moduledoc """
  Removes bare `return` keyword from Elixir code in any context.

  LLMs (trained on Python) frequently write `return` as an early-exit
  statement in Elixir blocks. Since `return/1` does not exist in Elixir,
  this fails to compile. The fix unwraps the `return` call, leaving just
  the value as the block's last expression in any code context:

  - `unless` with `else`: unwraps `return` in the `do` branch
  - `if` keyword early-return: restructures to block `if/else`
  - `case` branches, bare expressions, any other context: strips `return`

  ## Ordering

  `Credence.Semantic.UndefinedFunction` (500) is the catch-all for
  `undefined function …` and claims `undefined function return/1` too.
  Semantic dispatch is `Enum.find` — first match wins, no fall-through — so at
  equal priority the winner would have been decided by `NoBareReturnInUnless`
  sorting before `UndefinedFunction` alphabetically. The catch-all therefore
  declares 501 so that every specific rule beats it by declaration rather than
  by spelling. This rule owns the `return` diagnostic because it restructures
  the surrounding block; treating `return` as a merely-misspelled call would
  strip an early exit and let execution fall through to the code it was
  written to skip.

  ## Bad

      defmodule DBCleanerNBRIU do
        def clean() do
          case get_spec() do
            nil -> :ok
            _spec ->
              case :error do
                {:error, {:cycle, remaining_tables}} ->
                  return {:error, {:cycle, remaining_tables}}
              end
          end
        end

        defp get_spec, do: Process.get(:spec)
      end

  ## Good

      defmodule DBCleanerNBRIU do
        def clean() do
          case get_spec() do
            nil ->
              :ok

            _spec ->
              case :error do
                {:error, {:cycle, remaining_tables}} ->
                  {:error, {:cycle, remaining_tables}}
              end
          end
        end

        defp get_spec, do: Process.get(:spec)
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "undefined function return/"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_bare_return_in_unless,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          # An early-exit guard: a conditional whose whole body is `return(V)`,
          # with more statements after it in the same block. Stripping the
          # `return` here would turn the guard into a discarded expression and
          # let execution fall through to the code it was written to skip — so
          # the block is restructured into if/else instead. This clause must
          # come first: it has to consume the `return` before the catch-all
          # below can strip it.
          {:__block__, _meta, stmts} = node when is_list(stmts) ->
            restructure_early_exit(node) || node

          # Handle unless blocks with else: unwrap return in do branch
          {:unless, unless_meta, [condition, kw]} = node when is_list(kw) ->
            if has_else_branch?(kw) do
              new_kw = unwrap_return_in_do(kw)

              if new_kw != kw do
                {:unless, unless_meta, [condition, new_kw]}
              else
                node
              end
            else
              node
            end

          # General case: strip bare return in any context (case branches, etc.)
          {:return, _, [value]} ->
            value

          node ->
            node
        end)

      if result == ast do
        source
      else
        Sourceror.to_string(result)
      end
    else
      _ -> source
    end
  end

  # When a non-final conditional or case arm ends in `return(V)`, move the
  # remaining statements into every non-returning path and unwrap the returning
  # paths. This preserves the early exit instead of discarding it.
  #
  # Verified failure this prevents: `unless n >= 0 do return({:error, :neg}) end`
  # followed by `{:ok, n}` was emitted with the `return` simply removed. That
  # compiles clean and returns `{:ok, -5}` where the author wrote
  # `{:error, :neg}` — the validation silently stops happening.
  defp restructure_early_exit({:__block__, meta, stmts}) do
    case Enum.find_index(stmts, &early_exit_expression?/1) do
      nil ->
        nil

      idx ->
        {pre, [guard | post]} = Enum.split(stmts, idx)

        if post == [] do
          nil
        else
          {:__block__, meta, pre ++ [restructure_expression(guard, post)]}
        end
    end
  end

  defp early_exit_expression?({kind, _meta, [_condition, kw]})
       when kind in [:if, :unless] and is_list(kw) do
    Enum.any?(kw, fn
      {{:__block__, _, [key]}, body} when key in [:do, :else] ->
        match?({:ok, _}, unwrap_terminal_return(body))

      _ ->
        false
    end)
  end

  defp early_exit_expression?({:case, _meta, [_value, kw]}) when is_list(kw) do
    kw
    |> case_clauses()
    |> Enum.any?(fn {:->, _, [_patterns, body]} ->
      match?({:ok, _}, unwrap_terminal_return(body))
    end)
  end

  defp early_exit_expression?(_), do: false

  defp restructure_expression({kind, meta, [condition, kw]}, post)
       when kind in [:if, :unless] do
    if has_else_branch?(kw) do
      new_kw =
        Enum.map(kw, fn
          {{:__block__, arm_meta, [key]}, body} when key in [:do, :else] ->
            new_body =
              case unwrap_terminal_return(body) do
                {:ok, unwrapped} -> unwrapped
                :error -> append_post(body, post)
              end

            {{:__block__, arm_meta, [key]}, new_body}

          other ->
            other
        end)

      {kind, block_form_meta(meta), [condition, new_kw]}
    else
      {:ok, value} =
        kw
        |> Enum.find_value(fn
          {{:__block__, _, [:do]}, body} -> {:found, body}
          _ -> nil
        end)
        |> then(fn {:found, body} -> unwrap_terminal_return(body) end)

      {do_body, else_body} =
        case kind do
          :if -> {value, block_of(post)}
          :unless -> {block_of(post), value}
        end

      {:if, block_form_meta(meta), [condition, [do_arm(do_body), else_arm(else_body)]]}
    end
  end

  defp restructure_expression({:case, meta, [value, kw]}, post) do
    new_kw =
      Enum.map(kw, fn
        {{:__block__, key_meta, [:do]}, clauses} ->
          new_clauses =
            Enum.map(clauses, fn {:->, arrow_meta, [patterns, body]} ->
              new_body =
                case unwrap_terminal_return(body) do
                  {:ok, unwrapped} -> unwrapped
                  :error -> append_post(body, post)
                end

              {:->, arrow_meta, [patterns, new_body]}
            end)

          {{:__block__, key_meta, [:do]}, new_clauses}

        other ->
          other
      end)

    {:case, meta, [value, new_kw]}
  end

  defp unwrap_terminal_return({:return, _, [value]}), do: {:ok, value}

  defp unwrap_terminal_return({:__block__, meta, stmts}) when is_list(stmts) do
    case List.pop_at(stmts, -1) do
      {nil, _} ->
        :error

      {{:return, _, [value]}, preceding} ->
        {:ok, {:__block__, meta, preceding ++ [value]}}

      _ ->
        :error
    end
  end

  defp unwrap_terminal_return(_), do: :error

  defp append_post({:__block__, meta, stmts}, post) when is_list(stmts),
    do: {:__block__, meta, stmts ++ post}

  defp append_post(body, post), do: block_of([body | post])

  defp case_clauses(kw) do
    Enum.find_value(kw, [], fn
      {{:__block__, _, [:do]}, clauses} -> clauses
      _ -> nil
    end)
  end

  defp do_arm(body), do: {{:__block__, [], [:do]}, body}
  defp else_arm(body), do: {{:__block__, [], [:else]}, body}

  # Sourceror renders `do…end` rather than `, do:` only when the call's meta
  # carries `:do` and `:end` positions.
  defp block_form_meta(meta) do
    line = Keyword.get(meta, :line, 1)

    meta
    |> Keyword.put_new(:do, line: line)
    |> Keyword.put_new(:end, line: line)
  end

  defp block_of([single]), do: single
  defp block_of(many), do: {:__block__, [], many}

  defp has_else_branch?(kw) do
    Enum.any?(kw, fn
      {{:__block__, _, [:else]}, _} -> true
      _ -> false
    end)
  end

  defp unwrap_return_in_do(kw) do
    Enum.map(kw, fn
      {{:__block__, meta, [:do]}, {:return, _, [value]}} ->
        {{:__block__, meta, [:do]}, value}

      other ->
        other
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
