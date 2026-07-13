defmodule Credence.Syntax.NoRescueOrCatchOutsideTry do
  @moduledoc """
  Detects and repairs `def`/`defp` clauses with `rescue`/`catch`/`else`
  attached directly to the function body instead of inside a `try` block.

  LLMs with Python `try`/`except` muscle memory attach `rescue`/`catch`/`else`
  directly to `def` bodies. While Elixir accepts this syntactically (the compiler
  wraps the body in an implicit `try`), it is non-idiomatic and confusing. The
  deterministic fix wraps the body in an explicit `try do … end` block and moves
  the clauses inside.

  ## Bad (non-idiomatic)

      def verify(payload) do
        process(payload)
      rescue
        _ -> :error
      end

  ## Good

      def verify(payload) do
        try do
          process(payload)
        rescue
          _ -> :error
        end
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @bad_clauses [:rescue, :catch, :else]

  @impl true
  def analyze(source) do
    case find_def_with_bad_clause(source) do
      {:ok, clause, line} ->
        [
          %Issue{
            rule: :no_rescue_or_catch_outside_try,
            message:
              "`#{clause}` attached to `def` — wrap body in `try` instead",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source) do
    case find_def_with_bad_clause(source) do
      {:ok, _kind, _line} ->
        fixed = apply_fix(source)
        if fixed == source, do: source, else: fix(fixed)

      :none ->
        source
    end
  end

  # Parse with Sourceror and walk the AST to find a `def`/`defp` node whose
  # keyword options include `:rescue`, `:catch`, or `:else`.
  # Returns `{:ok, clause_name, line}` or `:none`.
  defp find_def_with_bad_clause(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_ast, result} =
          Macro.prewalk(ast, nil, fn
            {kind, meta, [_head, opts]} = node, nil
            when kind in [:def, :defp] and is_list(opts) ->
              case bad_clause_info(opts) do
                {:ok, clause_name, _clause_line} ->
                  {node, {:ok, clause_name, meta[:line]}}

                :none ->
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

  # Returns {clause_name, line} of the first rescue/catch/else keyword in opts, or :none.
  defp bad_clause_info(opts) do
    opts
    |> Enum.find_value(:none, fn
      {{:__block__, meta, [key]}, _} when key in @bad_clauses ->
        {:ok, key, meta[:line]}

      _ ->
        nil
    end)
  end

  # Source surgery: wrap the def body in `try do … end` and move
  # rescue/catch/else clauses inside the try block.
  #
  # 1. After the `def … do` line, insert `try do` (at body indent).
  # 2. Indent everything between do-line and def's closing `end` by 2
  #    (body + rescue/catch/else and their bodies all move inside try).
  # 3. Before the def's closing `end`, insert `end` for the try block.
  defp apply_fix(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_, positions} =
          Macro.prewalk(ast, [], fn
            {kind, meta, [_head, opts]} = node, acc
            when kind in [:def, :defp] and is_list(opts) ->
              case bad_clause_info(opts) do
                {:ok, _clause_name, clause_line} ->
                  {node,
                   acc ++
                     [
                       %{
                         do_line: meta[:do][:line],
                         end_line: meta[:end][:line],
                         clause_line: clause_line
                       }
                     ]}

                :none ->
                  {node, acc}
              end

            node, acc ->
              {node, acc}
          end)

        case positions do
          [pos | _] -> do_apply_fix(source, pos)
          [] -> source
        end

      _ ->
        source
    end
  end

  defp do_apply_fix(source, %{do_line: do_line, end_line: end_line, clause_line: _clause_line}) do
    lines = String.split(source, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, idx} ->
      cond do
        idx == do_line ->
          # Insert `try do` after the `def … do` line, at body indent.
          [line, "#{body_indent(line)}try do"]

        idx > do_line and idx < end_line ->
          # Indent everything between do and end by 2 (body + rescue/catch/else
          # and their bodies all move inside the try block).
          [indent_line(line, 2)]

        idx == end_line ->
          # Insert `end` for the try block (same indent as `try do`) just
          # before the def's closing `end`.
          ["#{body_indent(line)}end", line]

        true ->
          [line]
      end
    end)
    |> Enum.join("\n")
  end

  # The indent of the body content (one level deeper than the def line).
  defp body_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent <> "  "
      _ -> "  "
    end
  end

  defp indent_line(line, n) do
    if String.trim(line) == "", do: line, else: String.duplicate(" ", n) <> line
  end

end
