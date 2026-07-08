defmodule Credence.Syntax.NoIfElseInReceiveAfter do
  @moduledoc """
  Detects and repairs `receive` blocks where the `after` clause contains a bare
  expression (e.g. `if`, `case`, `cond`, or a multi-expression block) instead of
  the required `timeout -> body` arrow clause.

  LLMs frequently write bare expressions directly after `after` in a `receive`
  block, which parses but produces a compile error:
  `expected a single -> clause for :after in "receive"`.

  The deterministic fix wraps the bare expression in a `0 ->` arrow clause,
  which is the simplest valid `after` form.

  ## Bad (parses but won't compile)

      receive do
        :msg -> :ok
      after
        if true do
          :timeout
        else
          :done
        end
      end

  ## Good

      receive do
        :msg -> :ok
      after
        0 ->
          if true do
            :timeout
          else
            :done
          end
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case find_bare_after(source) do
      {:ok, line} ->
        [
          %Issue{
            rule: :no_if_else_in_receive_after,
            message:
              "`after` in `receive` expects a `timeout -> body` clause, not a bare expression",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source) do
    case find_bare_after(source) do
      {:ok, _line} ->
        case apply_fix(source) do
          {:ok, fixed} -> fixed
          :error -> source
        end

      :none ->
        source
    end
  end

  # Parse with Sourceror and find a `receive` block whose `after` value is a
  # bare expression (tuple) instead of a list of `->` clauses.
  defp find_bare_after(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_ast, result} =
          Macro.prewalk(ast, nil, fn
            {:receive, meta, [opts]} = node, nil when is_list(opts) ->
              case after_value(opts) do
                {:bare, _val} -> {node, {:ok, meta[:line]}}
                _ -> {node, nil}
              end

            node, acc ->
              {node, acc}
          end)

        result || :none

      _ ->
        :none
    end
  end

  # Check if the `after` clause in `opts` has a bare expression (tuple) or
  # a proper list of `->` clauses.
  defp after_value(opts) do
    case Enum.find(opts, fn
           {{:__block__, _, [:after]}, _} -> true
           _ -> false
         end) do
      {{:__block__, _, [:after]}, val} when is_list(val) -> :proper
      {{:__block__, _, [:after]}, val} when is_tuple(val) -> {:bare, val}
      _ -> :none
    end
  end

  # Apply the fix by transforming the AST: wrap the bare after value in
  # `0 -> <value>` and use Sourceror patching to apply the change.
  defp apply_fix(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {new_ast, changed} =
          Macro.prewalk(ast, false, fn
            {:receive, r_meta, [opts]} = node, false ->
              case find_and_fix_after(opts) do
                {:ok, new_opts} ->
                  {{:receive, r_meta, [new_opts]}, true}

                :none ->
                  {node, false}
              end

            node, acc ->
              {node, acc}
          end)

        if changed do
          new_source = render_receive_fix(source, ast, new_ast)
          {:ok, new_source}
        else
          :error
        end

      _ ->
        :error
    end
  end

  # Find the `after` clause with a bare expression and replace it with one
  # that wraps the expression in a `0 ->` arrow.
  defp find_and_fix_after(opts) do
    case Enum.find_index(opts, fn
           {{:__block__, _, [:after]}, val} when is_tuple(val) -> true
           _ -> false
         end) do
      nil ->
        :none

      idx ->
        {{:__block__, a_meta, [:after]}, after_val} = Enum.at(opts, idx)

        # Build a new `->` clause: `0 -> <after_val>`
        arrow_meta = [line: a_meta[:line] || 1, column: (a_meta[:column] || 0) + 3]
        zero_meta = [line: a_meta[:line] || 1, column: (a_meta[:column] || 0) + 3]

        arrow_clause =
          {:->, arrow_meta,
           [
             [{:__block__, zero_meta, [0]}],
             after_val
           ]}

        new_after = {{:__block__, a_meta, [:after]}, [arrow_clause]}
        {:ok, List.replace_at(opts, idx, new_after)}
    end
  end

  # Render the fixed receive block and patch it into the source.
  defp render_receive_fix(source, original_ast, new_ast) do
    # Find the receive node in both ASTs to get the range and render the replacement
    original_receive = find_receive(original_ast)
    new_receive = find_receive(new_ast)

    case {original_receive, new_receive} do
      {{:ok, orig}, {:ok, new}} ->
        case Sourceror.get_range(orig) do
          %Sourceror.Range{} = range ->
            new_text = Sourceror.to_string(new)

            patch = %{
              range: %{
                start: [line: range.start[:line], column: range.start[:column]],
                end: [line: range.end[:line], column: range.end[:column]]
              },
              change: new_text
            }

            source
            |> Sourceror.patch_string([patch])
            |> strip_trailing_ws(source)

          _ ->
            source
        end

      _ ->
        source
    end
  end

  defp find_receive(ast) do
    Macro.prewalk(ast, nil, fn
      {:receive, _meta, _opts} = node, nil -> {node, {:ok, node}}
      node, acc -> {node, acc}
    end)
    |> elem(1)
    |> case do
      {:ok, node} -> {:ok, node}
      _ -> :error
    end
  end

  # Strip trailing whitespace introduced by Sourceror patching, but only on
  # lines the patch changed.
  defp strip_trailing_ws(text, original) do
    original
    |> String.split("\n")
    |> List.myers_difference(String.split(text, "\n"))
    |> Enum.flat_map(fn
      {:eq, lines} -> lines
      {:del, _lines} -> []
      {:ins, lines} ->
        Enum.map(lines, fn line ->
          if String.trim(line) == "", do: "", else: line
        end)
    end)
    |> Enum.join("\n")
  end
end
