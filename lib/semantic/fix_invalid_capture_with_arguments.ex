defmodule Credence.Semantic.FixInvalidCaptureWithArguments do
  @moduledoc """
  Fixes `&Mod.fun(args)/N` capture syntax.

  Elixir's `&` capture does not accept call arguments — only `&Mod.fun/arity`
  or `&Mod.fun(&1, ...)`. When an LLM writes `&Mod.fun(args)/N`, the compiler
  emits an "undefined variable" error because the parser treats the function
  name as a variable reference in the capture context.

  The fix rewrites `&Mod.fun(args)/N` to `fn -> Mod.fun(args) end`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "undefined variable"

  @impl true
  def match?(%{severity: sev, message: msg, file: file})
      when sev in [:warning, :error] and is_binary(msg) and is_binary(file) do
    String.contains?(msg, @match_substring) and
      case File.read(file) do
        {:ok, source} -> has_invalid_capture?(source)
        _ -> false
      end
  end

  def match?(%{severity: sev, message: msg})
      when sev in [:warning, :error] and is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_invalid_capture_with_arguments,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed?} =
        Macro.prewalk(ast, false, fn
          # Remote call with args: &Mod.fun(args)/N
          {:&, meta, [{:/, _, [{{:., _, _}, _, args} = call, _arity]}]}, _acc
          when is_list(args) and args != [] ->
            fn_node = {:fn, meta, [{:->, [], [[], call]}]}
            {fn_node, true}

          # Local call with args: &func(args)/N
          {:&, meta, [{:/, _, [{func_name, _, args} = call, _arity]}]}, _acc
          when is_atom(func_name) and is_list(args) and args != [] ->
            fn_node = {:fn, meta, [{:->, [], [[], call]}]}
            {fn_node, true}

          node, acc ->
            {node, acc}
        end)

      if changed?, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp has_invalid_capture?(source) do
    Regex.match?(~r/&[\w.]+\(.*?\)\s*\/\s*\d+/, source)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
