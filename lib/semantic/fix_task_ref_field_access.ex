defmodule Credence.Semantic.FixTaskRefFieldAccess do
  @moduledoc """
  Fixes the compile warning for calls to the hallucinated `Task.ref/1`.

  `Task.ref/1` does not exist in the Elixir standard library — LLMs
  hallucinate it to obtain a task's monitor reference, which actually lives
  in the `:ref` field of the `%Task{}` struct. Because the `Task` module
  itself exists, the compiler emits a warning whose position points at the
  function name:

      "Task.ref/1 is undefined or private"

  The fix replaces the flagged `Task.ref(arg)` call with the idiomatic field
  access `arg.ref`, spliced in via a Sourceror patch anchored at the
  diagnostic's line/column — only the flagged call changes, every other line
  survives byte-for-byte. Compound arguments keep their precedence: the
  rendered access parenthesizes them (`if(x, do: a, else: b).ref`).

  Only messages that start with `Task.ref/1 is undefined or private` are
  claimed: a user module whose path merely ends in `Task`
  (`MyApp.Task.ref/1 …`) and other arities (`Task.ref/2`) stay with the
  generic `UndefinedFunction` rule. Shapes that emit the same message but
  admit no in-place field-access rewrite — `&Task.ref/1` captures, the piped
  `t |> Task.ref()`, `Elixir.Task.ref(t)`, and a `Task.ref(t)` spelling that
  resolves to another module through `alias …, as: Task` — are deliberately
  left unfixed: the anchor only accepts a direct one-argument `Task.ref(…)`
  call whose function name sits exactly at the flagged column, and the fix
  no-ops rather than risk a wrong edit (same policy as
  `FixHallucinatedEnumRange`).

  ## Bad

      defmodule CredenceTaskRefMultilineE2EFTRFA do
        def a(t) do
          Task.ref(
            t
          )
        end
      end

  ## Good

      defmodule CredenceTaskRefMultilineE2EFTRFA do
        def a(t) do
          t.ref
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @message_prefix "Task.ref/1 is undefined or private"

  # `Task.` — the diagnostic column points at `ref`, five characters after
  # the start of the qualified call.
  @prefix_width 5

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @message_prefix)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_task_ref_field_access,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, node, range} <- flagged_call(ast, position(diagnostic)) do
      {_, _, [arg]} = node
      change = Sourceror.to_string({{:., [], [arg, :ref]}, [no_parens: true], []})
      Sourceror.patch_string(source, [%{range: range, change: change}])
    else
      _ -> source
    end
  end

  # The flagged call is the candidate whose function name sits exactly at the
  # diagnostic column. Without a column, a lone candidate on the flagged line
  # is unambiguous; anything else no-ops rather than guess.
  defp flagged_call(ast, {line_no, col}) do
    candidates = candidates_on_line(ast, line_no)

    if is_integer(col) do
      case Enum.filter(candidates, fn {_, range} ->
             range.start[:column] + @prefix_width == col
           end) do
        [{node, range}] -> {:ok, node, range}
        _ -> :error
      end
    else
      case candidates do
        [{node, range}] -> {:ok, node, range}
        _ -> :error
      end
    end
  end

  # A candidate is a direct `Task.ref(arg)` call — exact `[:Task]` alias,
  # exactly one argument — starting on the flagged line. The capture
  # (`&Task.ref/1`) and piped (`t |> Task.ref()`) forms carry zero args in
  # the dot call and never qualify.
  defp candidates_on_line(ast, line_no) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Task]}, :ref]}, _, [_]} = node, acc ->
          case Sourceror.get_range(node) do
            %{start: start} = range ->
              if start[:line] == line_no, do: {node, [{node, range} | acc]}, else: {node, acc}

            nil ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp position(%{position: {line, col}}) when is_integer(line), do: {line, col}
  defp position(%{position: line}) when is_integer(line), do: {line, nil}
  defp position(_), do: {nil, nil}

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
