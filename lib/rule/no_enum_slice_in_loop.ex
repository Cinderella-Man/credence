defmodule Credence.Rule.NoEnumSliceInLoop do
  @moduledoc """
  Performance rule: Flags usage of `Enum.slice/3` in iterative and recursive list-processing patterns.

  Elixir lists are linked structures, so `Enum.slice/3` is O(n). When used repeatedly
  inside loops, comprehensions, or recursion, this produces O(n²) behavior.

  This is a common pitfall in:
  - n-gram generation
  - sliding window extraction
  - manual recursive traversal of lists

  Prefer `Enum.chunk_every/4` for sliding windows.

  ## Bad

      for i <- 0..max_index do
        Enum.slice(list, i, n)
      end

      def loop(i, list) do
        Enum.slice(list, i, n)
        loop(i + 1, list)
      end

  ## Good

      list
      |> Enum.chunk_every(n, 1, :discard)

      def loop(list) do
        list
        |> Enum.chunk_every(n, 1, :discard)
      end
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # ------------------------------------------------------------
        # Detect Enum.slice/3 anywhere (core performance issue)
        # ------------------------------------------------------------
        {{:., _, [{:__aliases__, _, [:Enum]}, :slice]}, meta, _args} = node, issues ->
          issue = %Issue{
            rule: :no_enum_slice_in_loop,
            severity: :warning,
            message:
              "`Enum.slice/3` is O(n) on lists. Repeated use in loops or recursion leads to O(n²) behavior. " <>
                "Use `Enum.chunk_every(list, size, 1, :discard)` for sliding windows instead.",
            meta: %{line: Keyword.get(meta, :line)}
          }

          {node, [issue | issues]}

        # ------------------------------------------------------------
        # Detect recursive functions that likely re-slice lists
        # (heuristic: function calls itself AND contains Enum.slice/3)
        # ------------------------------------------------------------
        {:def, _, [{name, _, _args}, [do: body]]} = node, issues when is_atom(name) ->
          slice_used? =
            Macro.prewalk(body, false, fn
              {{:., _, [{:__aliases__, _, [:Enum]}, :slice]}, _, _} = slice_node, _ ->
                {slice_node, true}

              other, acc ->
                {other, acc}
            end)
            |> elem(1)

          recursive_call? =
            Macro.prewalk(body, false, fn
              {^name, _, _} = call, _ ->
                {call, true}

              other, acc ->
                {other, acc}
            end)
            |> elem(1)

          issues =
            if slice_used? and recursive_call? do
              issue = %Issue{
                rule: :no_enum_slice_in_loop,
                severity: :warning,
                message:
                  "Recursive function uses `Enum.slice/3` while calling itself. " <>
                    "This commonly creates O(n²) behavior in manual sliding-window implementations. " <>
                    "Refactor using `Enum.chunk_every/4` or accumulator-based traversal.",
                meta: %{function: name}
              }

              [issue | issues]
            else
              issues
            end

          {node, issues}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end
end
