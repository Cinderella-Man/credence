defmodule Credence.Syntax.NoPostfixIfExpression do
  @moduledoc """
  Rewrites a Ruby/Python-style postfix `if` modifier on a rebinding assignment.

  LLMs (especially Qwen) emit a trailing `if` modifier (`var = expr if condition`)
  which is a syntax error in Elixir (`syntax error before: 'if'`). Where the
  variable already exists, the modifier means "rebind it only when the condition
  holds", so the faithful Elixir spelling keeps the old value in the `else`
  branch.

  ## Bad (won't parse)

      new_max = current_max
      new_max = max(current_max, period) if type == :sma

  ## Good

      new_max = current_max
      new_max = if type == :sma, do: max(current_max, period), else: new_max

  ## Why this rule is narrow

  A line-anchored regex for `<var> = <expr> if <cond>` matches a great deal of
  *valid* code — `msg = "run if you can"`, `foo = bar() # only if needed`,
  `x =  if a, do: 1, else: 2` — and the syntax phase hands every rule the
  **whole file**, not just the broken line. So a match is only the first of five
  gates; a line is rewritten only when all of them hold:

  1. it is wholly code according to `Credence.SourceMask` (so strings, comments,
     charlists, sigils, and both kinds of heredoc are never rewritten);
  2. the line **does not parse on its own** — every valid line above parses, so
     none of them can reach the rewrite. This also passes over a modifier whose
     expression ends in a bare identifier (`total = total + x if x > 0` parses,
     as `total + x(if(x > 0))`): it is not a syntax error, so repairing it is not
     this phase's job;
  3. the captured expression and condition each parse as a *single* expression
     (this drops `x = a if b if c`, `x = "yes" if a else "no"`, and any other
     split that isn't really an expression plus a condition);
  4. the variable is **bound earlier in the same function**, so the `else:`
     branch refers to an existing binding — otherwise the rewrite would parse
     but not compile (`undefined variable`), and guessing `else: nil` instead
     would silently change the value the code ends up with;
  5. the rewritten line is **re-parsed and compared against the original
     fragments' ASTs**. Splicing text can reassociate: `x = foo a, b if c`
     would become `foo(a, b, else: x)` — the `else:` swallowed into the call.
     The AST check rejects any such rewrite instead of shipping it.

  Everything that fails a gate is left exactly as it was.
  """

  use Credence.Syntax.Rule
  alias Credence.Issue
  alias Credence.SourceMask

  # Line-anchored: <indent><var> = <expr> if <cond>. Group 3 is greedy, so the
  # split is taken at the *last* ` if ` on the line; gate 3 then throws the
  # match away unless both halves are real expressions.
  #
  #   group 1: leading indentation
  #   group 2: left-hand-side variable
  #   group 3: right-hand-side expression
  #   group 4: condition
  @postfix_if_pattern ~r/^(\s*)([a-z_][A-Za-z0-9_]*)\s*=\s*(\S.*)\s+if\s+(\S.*?)\s*$/

  # Plain ASCII variable names — the only ones @postfix_if_pattern can capture.
  @identifier_pattern ~r/[a-z_][A-Za-z0-9_]*/

  @impl true
  def analyze(source) do
    Enum.map(rewrites(source), fn {line_no, _fixed} ->
      %Issue{
        rule: :no_postfix_if_expression,
        message:
          "Postfix `if` is not valid Elixir. " <>
            "Use `var = if condition, do: expr, else: var` instead.",
        meta: %{line: line_no}
      }
    end)
  end

  @impl true
  def fix(source) do
    case rewrites(source) do
      [] ->
        source

      rewrites ->
        fixed = Map.new(rewrites)

        source
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.map_join("\n", fn {line, line_no} -> Map.get(fixed, line_no, line) end)
    end
  end

  # The single source of truth shared by analyze/1 and fix/1: the list of
  # `{line_number, rewritten_line}` for every line that clears all five gates.
  defp rewrites(source) do
    source
    |> SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.reduce({[], MapSet.new()}, fn {{line, shadow}, line_no}, {acc, seen} ->
      seen = if function_definition?(shadow), do: MapSet.new(), else: seen

      acc =
        case rewrite_line(line, shadow, seen) do
          {:ok, fixed} -> [{line_no, fixed} | acc]
          :error -> acc
        end

      {acc, add_bindings(seen, shadow)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp rewrite_line(line, shadow, seen) do
    with true <- SourceMask.self_contained?(line, shadow),
         [indent, lhs, expr, cond_expr] <- captures(line),
         true <- MapSet.member?(seen, lhs),
         :error <- parse(line),
         {:ok, expr_ast} <- parse_expression(expr),
         {:ok, cond_ast} <- parse_expression(cond_expr),
         fixed = "#{indent}#{lhs} = if #{cond_expr}, do: #{expr}, else: #{lhs}",
         true <- faithful?(fixed, lhs, expr_ast, cond_ast) do
      {:ok, fixed}
    else
      _ -> :error
    end
  end

  defp captures(line) do
    case Regex.run(@postfix_if_pattern, line, capture: :all_but_first) do
      [indent, lhs, expr, cond_expr] ->
        [indent, lhs, String.trim_trailing(expr), String.trim_trailing(cond_expr)]

      nil ->
        nil
    end
  end

  defp function_definition?(shadow), do: Regex.match?(~r/^\s*defp?\b/, shadow)

  defp add_bindings(seen, shadow) do
    assignment_bindings =
      Regex.scan(~r/\b([a-z_][A-Za-z0-9_]*)\s*=(?!=)/, shadow, capture: :all_but_first)

    parameter_bindings =
      Regex.scan(~r/(?:defp?\s+[a-z_][A-Za-z0-9_]*\s*\(|fn\s+)([^\n]*?)(?:\)|->)/, shadow,
        capture: :all_but_first
      )
      |> Kernel.++(
        Regex.scan(
          ~r/defp?\s+[a-z_][A-Za-z0-9_]*\s+([^\n]*?)(?:\s+when\b|\s+do\b|,\s*do:)/,
          shadow,
          capture: :all_but_first
        )
      )
      |> Enum.flat_map(fn [parameters] ->
        Regex.scan(@identifier_pattern, parameters, capture: :first)
      end)

    Enum.reduce(assignment_bindings ++ parameter_bindings, seen, fn [id], acc ->
      MapSet.put(acc, id)
    end)
  end

  # `{:ok, ast}` when `code` parses as exactly one expression, `:error` otherwise.
  defp parse_expression(code) do
    case parse(code) do
      {:ok, {:__block__, _, [_, _ | _]}} -> :error
      {:ok, ast} -> {:ok, ast}
      :error -> :error
    end
  end

  defp parse(code) do
    {result, _diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          Code.string_to_quoted(String.trim(code))
        rescue
          _ -> :error
        end
      end)

    case result do
      {:ok, ast} -> {:ok, ast}
      _ -> :error
    end
  end

  # The rewrite is accepted only if re-parsing it yields exactly
  # `lhs = if <cond>, do: <expr>, else: lhs` with the *same* condition and
  # expression ASTs we captured — no reassociation, no swallowed keywords.
  defp faithful?(fixed, lhs, expr_ast, cond_ast) do
    case parse(fixed) do
      {:ok, {:=, _, [{name, _, nil}, {:if, _, [cond?, [do: expr?, else: {name, _, nil}]]}]}} ->
        Atom.to_string(name) == lhs and
          strip_meta(cond?) == strip_meta(cond_ast) and
          strip_meta(expr?) == strip_meta(expr_ast)

      _ ->
        false
    end
  end

  defp strip_meta(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} when is_list(meta) -> {form, [], args}
      other -> other
    end)
  end
end
