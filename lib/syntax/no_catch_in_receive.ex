defmodule Credence.Syntax.NoCatchInReceive do
  @moduledoc """
  Detects and repairs `receive` blocks that misuse `catch`.

  LLMs hallucinate `catch` clauses inside `receive` blocks (from try/catch
  confusion), producing a compile error: "unexpected option :catch in receive".

  The deterministic fix removes the invalid `catch` block entirely. This cannot
  over-fire — `catch` is only valid inside `try`, never `receive`.

  ## Bad (compiles with error)

      receive do
        {:ok, result} -> {:ok, result}
      catch
        :exit, _ -> {:error, :timeout}
      after
        5_000 -> {:error, :timeout}
      end

  ## Good

      receive do
        {:ok, result} -> {:ok, result}
      after
        5_000 -> {:error, :timeout}
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case find_receive_with_catch(source) do
      {:ok, line} ->
        [
          %Issue{
            rule: :no_catch_in_receive,
            message: "`catch` inside `receive` — only valid inside `try`",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source) do
    case find_receive_with_catch(source) do
      {:ok, _line} ->
        case apply_fix(source) do
          {:ok, fixed} -> fixed
          :error -> source
        end

      :none ->
        source
    end
  end

  # Parse with Sourceror and walk the AST to find a `receive` node whose keyword
  # options include `:catch`. Returns `{:ok, catch_line}` or `:none`.
  defp find_receive_with_catch(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_ast, result} =
          Macro.prewalk(ast, nil, fn
            {:receive, _meta, [opts]} = node, nil when is_list(opts) ->
              case catch_option(opts) do
                {{:__block__, catch_meta, [:catch]}, _body} ->
                  {node, {:ok, catch_meta[:line]}}

                nil ->
                  {node, nil}
              end

            node, acc ->
              {node, acc}
          end)

        result || :none

      _ ->
        :none
    end
  end

  defp catch_option(opts) do
    Enum.find(opts, fn
      {{:__block__, _, [:catch]}, _} -> true
      _ -> false
    end)
  end

  # Apply the fix by transforming the AST: remove the :catch option from the
  # receive keyword list, then use Sourceror patching to apply the change.
  defp apply_fix(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {new_ast, changed} =
          Macro.prewalk(ast, false, fn
            {:receive, r_meta, [opts]} = node, false ->
              case Enum.find_index(opts, fn
                     {{:__block__, _, [:catch]}, _} -> true
                     _ -> false
                   end) do
                nil ->
                  {node, false}

                idx ->
                  new_opts = List.delete_at(opts, idx)
                  {{:receive, r_meta, [new_opts]}, true}
              end

            node, acc ->
              {node, acc}
          end)

        if changed do
          new_source = render_fix(source, ast, new_ast)
          {:ok, new_source}
        else
          :error
        end

      _ ->
        :error
    end
  end

  # Render the fixed receive block and patch it into the source.
  defp render_fix(source, original_ast, new_ast) do
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
