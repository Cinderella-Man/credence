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

  # `pre… ; COND_STMT ; post…`  where COND_STMT is `if/unless C do return(V) end`
  # and `post` is non-empty, becomes `pre… ; if C do post else V end` (with the
  # arms swapped for `unless`, which runs its body when the condition is falsy).
  #
  # Verified failure this prevents: `unless n >= 0 do return({:error, :neg}) end`
  # followed by `{:ok, n}` was emitted with the `return` simply removed. That
  # compiles clean and returns `{:ok, -5}` where the author wrote
  # `{:error, :neg}` — the validation silently stops happening.
  defp restructure_early_exit({:__block__, meta, stmts}) do
    case Enum.find_index(stmts, &early_exit_guard?/1) do
      nil ->
        nil

      idx ->
        {pre, [guard | post]} = Enum.split(stmts, idx)

        if post == [] do
          nil
        else
          {:__block__, meta, pre ++ [swap_arms(guard, block_of(post))]}
        end
    end
  end

  defp early_exit_guard?({kind, _meta, [_condition, kw]})
       when kind in [:if, :unless] and is_list(kw) do
    not has_else_branch?(kw) and do_branch_return_value(kw) != nil
  end

  defp early_exit_guard?(_), do: false

  defp do_branch_return_value(kw) do
    Enum.find_value(kw, fn
      {{:__block__, _, [:do]}, {:return, _, [value]}} -> value
      _ -> nil
    end)
  end

  defp swap_arms({kind, meta, [condition, kw]}, rest) do
    value = do_branch_return_value(kw)

    {do_body, else_body} =
      case kind do
        :if -> {value, rest}
        :unless -> {rest, value}
      end

    {:if, block_form_meta(meta), [condition, [do_arm(do_body), else_arm(else_body)]]}
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
