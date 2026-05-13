defmodule Credence.Pattern.NoIsNilGuard do
  @moduledoc """
  Detects `is_nil(param)` in function guards that can be replaced with
  pattern matching `nil` directly in the function head.

  LLMs reach for `is_nil/1` in guards because Python uses
  `if x is None:` — the explicit nil/null check is the only option.
  In Elixir, pattern matching `nil` in the function head is shorter,
  clearer, and more idiomatic.

  ## Bad

      def foo(x) when is_nil(x), do: :default
      def bar(x, y) when is_nil(x) and is_binary(y), do: y

  ## Good

      def foo(nil), do: :default
      def bar(nil, y) when is_binary(y), do: y

  ## What is flagged

  Any `def`/`defp` clause whose guard contains `is_nil(param)` where
  `param` is a top-level simple parameter. The `is_nil` may be the sole
  guard or a direct conjunct in an `and` chain.

  Not flagged:
  - `is_nil` inside `or` (`when is_nil(x) or is_atom(x)`)
  - negated `is_nil` (`when not is_nil(x)`)
  - `is_nil` on non-variable expressions (`when is_nil(hd(x))`)
  - `is_nil` on destructured bindings (`def foo(%{k: v}) when is_nil(v)`)
  - `is_nil` outside of function guards (e.g. inside `if`)

  ## Auto-fix

  Replaces the parameter with `nil` in the function head and removes
  `is_nil(param)` from the guard (or drops the guard entirely if it
  was the only condition). When the parameter is used in the function
  body, the fix uses `nil = param` to preserve the binding.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  # ── Check ──────────────────────────────────────────────────────

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect(node) do
          {:ok, meta} -> {node, [build_issue(meta) | acc]}
          :skip -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  # def/defp with a when clause
  defp detect({def_kind, meta, [{:when, _wm, [fn_head, guard]} | _]})
       when def_kind in [:def, :defp] do
    params = top_level_param_names(fn_head)

    if params != [] and has_fixable_is_nil?(guard, params) do
      {:ok, meta}
    else
      :skip
    end
  end

  defp detect(_), do: :skip

  # Extract simple top-level param names: {name, _, ctx} where both atoms
  defp top_level_param_names({_name, _meta, params}) when is_list(params) do
    for {n, _, ctx} <- params, is_atom(n), is_atom(ctx), do: n
  end

  defp top_level_param_names(_), do: []

  # Walk the guard looking for bare is_nil(param) — only recurse
  # into `and` nodes, stop at `or` / `not` / `!`
  defp has_fixable_is_nil?({:is_nil, _, [{name, _, ctx}]}, params)
       when is_atom(name) and is_atom(ctx),
       do: name in params

  defp has_fixable_is_nil?({:and, _, [left, right]}, params),
    do: has_fixable_is_nil?(left, params) or has_fixable_is_nil?(right, params)

  defp has_fixable_is_nil?({:or, _, _}, _), do: false
  defp has_fixable_is_nil?({:not, _, _}, _), do: false
  defp has_fixable_is_nil?({:!, _, _}, _), do: false
  defp has_fixable_is_nil?(_, _), do: false

  # ── Fix ────────────────────────────────────────────────────────

  # def name(params) when guard, do: body
  @one_liner_re ~r/^(\s*)(defp?)\s+(\w+[?!]?)\(([^)]*)\)\s*when\s+(.+?),\s*do:\s*(.+)$/
  # def name(params) when guard do
  @block_re ~r/^(\s*)(defp?)\s+(\w+[?!]?)\(([^)]*)\)\s*when\s+(.+)\s+do\s*$/

  @impl true
  def fix(source, _opts) do
    source
    |> String.split("\n")
    |> fix_lines([])
    |> Enum.join("\n")
  end

  defp fix_lines([], acc), do: Enum.reverse(acc)

  defp fix_lines([line | rest], acc) do
    cond do
      Regex.match?(@one_liner_re, line) ->
        fix_lines(rest, [fix_one_liner(line) | acc])

      Regex.match?(@block_re, line) ->
        {body_lines, remaining} = collect_body(rest)
        fixed_head = fix_block_head(line, body_lines)
        new_acc = Enum.reverse(body_lines) ++ [fixed_head | acc]

        case remaining do
          [end_line | after_end] -> fix_lines(after_end, [end_line | new_acc])
          [] -> Enum.reverse(new_acc)
        end

      true ->
        fix_lines(rest, [line | acc])
    end
  end

  # ── One-liner ──────────────────────────────────────────────────

  defp fix_one_liner(line) do
    case Regex.run(@one_liner_re, line) do
      [_, indent, kind, name, params, guard, body] ->
        if skip_guard?(guard), do: line, else: rewrite(indent, kind, name, params, guard, body)

      _ ->
        line
    end
  end

  # ── Block head ─────────────────────────────────────────────────

  defp fix_block_head(line, body_lines) do
    case Regex.run(@block_re, line) do
      [_, indent, kind, name, params, guard] ->
        if skip_guard?(guard) do
          line
        else
          body_text = Enum.join(body_lines, "\n")
          rewrite_block(indent, kind, name, params, guard, body_text)
        end

      _ ->
        line
    end
  end

  defp collect_body(lines), do: do_collect(lines, 1, [])

  defp do_collect([], _depth, acc), do: {Enum.reverse(acc), []}

  defp do_collect([line | rest], depth, acc) do
    trimmed = String.trim(line)
    opens = if Regex.match?(~r/\bdo\s*$/, trimmed), do: 1, else: 0
    closes = if trimmed == "end", do: 1, else: 0
    new_depth = depth + opens - closes

    if new_depth == 0 do
      {Enum.reverse(acc), [line | rest]}
    else
      do_collect(rest, new_depth, [line | acc])
    end
  end

  # ── Rewrite helpers ────────────────────────────────────────────

  defp rewrite(indent, kind, name, params, guard, body) do
    nil_params = extract_nil_params(guard)

    if nil_params == [] do
      "#{indent}#{kind} #{name}(#{params}) when #{guard}, do: #{body}"
    else
      new_params = replace_params(params, nil_params, body)
      new_guard = remove_nil_guards(guard, nil_params)

      case new_guard do
        "" -> "#{indent}#{kind} #{name}(#{new_params}), do: #{body}"
        g -> "#{indent}#{kind} #{name}(#{new_params}) when #{g}, do: #{body}"
      end
    end
  end

  defp rewrite_block(indent, kind, name, params, guard, body_text) do
    nil_params = extract_nil_params(guard)

    if nil_params == [] do
      "#{indent}#{kind} #{name}(#{params}) when #{guard} do"
    else
      new_params = replace_params(params, nil_params, body_text)
      new_guard = remove_nil_guards(guard, nil_params)

      case new_guard do
        "" -> "#{indent}#{kind} #{name}(#{new_params}) do"
        g -> "#{indent}#{kind} #{name}(#{new_params}) when #{g} do"
      end
    end
  end

  # ── Guard analysis ─────────────────────────────────────────────

  # Don't fix guards with `or`, or negated is_nil
  defp skip_guard?(guard) do
    Regex.match?(~r/\bor\b/, guard) or
      Regex.match?(~r/\bnot\s+is_nil\b/, guard) or
      Regex.match?(~r/!\s*is_nil\b/, guard)
  end

  # Pull simple param names out of is_nil(param) calls
  defp extract_nil_params(guard) do
    Regex.scan(~r/\bis_nil\((\w+)\)/, guard)
    |> Enum.map(fn [_, p] -> p end)
    |> Enum.uniq()
  end

  # ── Param replacement ──────────────────────────────────────────

  defp replace_params(params_str, nil_params, body_text) do
    Enum.reduce(nil_params, params_str, fn param, acc ->
      replacement = if param_used?(param, body_text), do: "nil = #{param}", else: "nil"
      Regex.replace(~r/\b#{Regex.escape(param)}\b/, acc, replacement, global: false)
    end)
  end

  defp param_used?(param, body) do
    Regex.match?(~r/\b#{Regex.escape(param)}\b/, body)
  end

  # ── Guard surgery ──────────────────────────────────────────────

  # Remove each is_nil(param) from the guard and-chain.
  # Handles first position, last position, and sole guard.
  defp remove_nil_guards(guard, nil_params) do
    Enum.reduce(nil_params, guard, fn param, acc ->
      e = Regex.escape(param)

      # is_nil(p) and ... → ...
      acc = Regex.replace(~r/\bis_nil\(#{e}\)\s+and\s+/, acc, "", global: false)
      # ... and is_nil(p) → ...
      acc = Regex.replace(~r/\s+and\s+is_nil\(#{e}\)/, acc, "", global: false)
      # sole is_nil(p) → ""
      Regex.replace(~r/\bis_nil\(#{e}\)/, acc, "", global: false)
    end)
    |> String.trim()
  end

  # ── Issue ──────────────────────────────────────────────────────

  defp build_issue(meta) do
    %Issue{
      rule: :no_is_nil_guard,
      message: """
      `is_nil(param)` in a guard can be replaced with pattern \
      matching `nil` directly in the function head.

          def foo(x) when is_nil(x)    →    def foo(nil)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
