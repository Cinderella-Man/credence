defmodule Credence.Syntax.NoBareAtomInGenserverStartLink do
  @moduledoc """
  Detects and fixes bare atom expressions passed as the third argument to
  `GenServer.start_link/3`.

  LLMs pass a bare atom or `opts[:name] || __MODULE__` expression as the third
  argument to `GenServer.start_link/3`, which expects a keyword list of options.
  This causes a `FunctionClauseError` at runtime on every call.

  The fix wraps the expression in a conditional keyword list:

      # Before (causes FunctionClauseError)
      GenServer.start_link(__MODULE__, :ok, opts[:name] || __MODULE__)

      # After (valid — passes keyword list)
      GenServer.start_link(__MODULE__, :ok, if(opts[:name], do: [name: opts[:name]], else: []))
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @impl true
  def analyze(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_ast, issues} =
          Macro.prewalk(ast, [], fn
            node, acc ->
              case check_node(node) do
                {:flagged, line} ->
                  issue = %Issue{
                    rule: :no_bare_atom_in_genserver_start_link,
                    message:
                      "Third argument to GenServer.start_link/3 must be a keyword list of options. " <>
                        "Wrap bare atoms in [name: ...] instead.",
                    meta: %{line: line}
                  }

                  {node, [issue | acc]}

                :ok ->
                  {node, acc}
              end
          end)

        Enum.reverse(issues)

      {:error, _} ->
        []
    end
  end

  @impl true
  def fix(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_new_ast, patches} =
          Macro.postwalk(ast, [], fn
            node, acc ->
              case check_node(node) do
                {:flagged, _line} ->
                  {{:., _, _}, _, [_, _, third_arg]} = node

                  case Sourceror.get_range(third_arg) do
                    nil ->
                      {node, acc}

                    range ->
                      replacement = build_fix(third_arg)
                      patch = %{range: range, change: replacement}
                      {node, [patch | acc]}
                  end

                :ok ->
                  {node, acc}
              end
          end)

        case patches do
          [] ->
            source

          _ ->
            Sourceror.patch_string(source, patches)
        end

      {:error, _} ->
        source
    end
  end

  # Match GenServer.start_link(mod, init, third_arg) where third_arg is not a
  # keyword list literal.
  defp check_node(node) do
    case node do
      {{:., _, [{:__aliases__, _, [:GenServer]}, :start_link]}, meta, [_, _, third_arg]} ->
        if valid_options?(third_arg) do
          :ok
        else
          {:flagged, Keyword.get(meta, :line, 0)}
        end

      _ ->
        :ok
    end
  end

  # Returns true when `node` is a valid GenServer options expression:
  # keyword list literal (including empty list), or a conditional expression
  # (if/case/cond/with) that can return a keyword list at runtime.
  defp valid_options?(node) do
    keyword_list_literal?(node) or conditional_expr?(node)
  end

  defp keyword_list_literal?(node) do
    case unwrap_block(node) do
      list when is_list(list) ->
        Enum.all?(list, fn
          {key, _} -> atom_literal?(unwrap_block(key))
          _ -> false
        end)

      _ ->
        false
    end
  end

  defp conditional_expr?({:if, _, _}), do: true
  defp conditional_expr?({:case, _, _}), do: true
  defp conditional_expr?({:cond, _, _}), do: true
  defp conditional_expr?({:with, _, _}), do: true
  defp conditional_expr?(_), do: false

  defp unwrap_block({:__block__, _, [value]}), do: value
  defp unwrap_block(other), do: other

  defp atom_literal?(atom) when is_atom(atom), do: true
  defp atom_literal?(_), do: false

  # Build the replacement string for the flagged third argument.
  #
  # For `||` patterns (the common LLM error): extracts the LHS as the name
  # expression and wraps in `if(expr, do: [name: expr], else: [])`.
  #
  # For bare atoms / module attributes: wraps in `[name: expr]`.
  defp build_fix(third_arg) do
    case third_arg do
      {:||, _, [access_expr, _fallback]} ->
        access_str = Sourceror.to_string(access_expr)
        "if(#{access_str}, do: [name: #{access_str}], else: [])"

      _ ->
        expr_str = Sourceror.to_string(third_arg)
        "[name: #{expr_str}]"
    end
  end
end
