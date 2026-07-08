defmodule Credence.Semantic.NoUndefinedOptionsInPlugRouterBlock do
  @moduledoc """
  Fixes `undefined variable "options"` errors inside Plug.Router route
  handler blocks.

  LLMs frequently generate Plug.Router route handlers that reference bare
  `options` which the macro scope does not bind. The compiler emits
  `undefined variable "options"`. The fix inserts
  `options = conn.private[:plug_router_opts]` at the start of the route
  handler's `do` block — Plug.Router stores init args in `conn.private`
  under `:plug_router_opts` when `copy_opts_to_assign` is used, which is
  the default idiom.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "undefined variable \"options\""

  @route_macros ~w(get post put delete patch options head match forward)a

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_undefined_options_in_plug_router_block,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: {target_line, _col}}) do
    with true <- String.contains?(msg, @match_msg),
         {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, do_line} <- find_route_do_line(ast, target_line) do
      insert_options_binding(source, do_line)
    else
      _ -> source
    end
  end

  def fix(source, _), do: source

  # Walk the AST looking for a Plug.Router route macro whose do..end range
  # contains the target line. Returns the line of the `do` keyword.
  defp find_route_do_line(ast, target_line) do
    {_ast, result} =
      Macro.prewalk(ast, nil, fn
        {name, meta, _args} = node, nil when name in @route_macros and is_list(meta) ->
          do_line = meta[:do][:line]
          end_line = meta[:end][:line]

          if do_line && end_line && target_line > do_line && target_line <= end_line do
            {node, {:ok, do_line}}
          else
            {node, nil}
          end

        node, acc ->
          {node, acc}
      end)

    result || :error
  end

  # Insert `options = conn.private[:plug_router_opts]` right after the `do`
  # line, with the same indentation as the block body.
  defp insert_options_binding(source, do_line) do
    lines = String.split(source, "\n")
    # do_line is 1-based; the body starts at the next line (index == do_line)
    body_indent = get_indent(Enum.at(lines, do_line, ""))
    new_line = "#{body_indent}options = conn.private[:plug_router_opts]"
    {before, after_} = Enum.split(lines, do_line)
    Enum.join(before ++ [new_line] ++ after_, "\n")
  end

  defp get_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
