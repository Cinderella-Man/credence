defmodule Credence.Semantic.FixInvalidCaptureWithLiteral do
  @moduledoc """
  Fixes `&<literal>` capture syntax where a bare literal is used with `&`.

  Elixir's `&` capture operator does not accept bare literals — only
  `&Mod.fun/arity`, `&fun/arity`, or `&expr(&1, ...)`. When an LLM writes
  `&true`, `&false`, `&:atom`, `&nil`, etc., the compiler emits:

      invalid args for &, expected one of …
      Got: <literal>

  LLMs typically intend a constant-function callback. The fix wraps the literal
  in `fn _ -> <literal> end`, which is the valid Elixir expression that
  captures a constant.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "invalid args for &"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_invalid_capture_with_literal,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed?} =
        Macro.prewalk(ast, false, fn
          {:&, meta, [{:__block__, _, [literal]}]}, _acc
          when is_boolean(literal) or is_atom(literal) or is_binary(literal) ->
            fn_node = {:fn, meta, [{:->, [], [[{:_, [], nil}], {:__block__, [], [literal]}]}]}
            {fn_node, true}

          {:&, meta, [{{:., dot_meta, [aliases, fun]}, call_meta, args}]} = node, acc
          when is_list(args) ->
            if Enum.any?(args, &match?({:/, _, [_, _]}, &1)) do
              new_args =
                Enum.map(args, fn
                  {:/, _, [left, _right]} -> left
                  other -> other
                end)

              fn_node = {:fn, meta, [{:->, [], [[], {{:., dot_meta, [aliases, fun]}, call_meta, new_args}]}]}
              {fn_node, true}
            else
              {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed?, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
