defmodule Credence.Semantic.NoUnusedPrivateFunction do
  @moduledoc """
  Removes genuinely unused `defp` functions that trigger
  "function X/N is unused" compiler warnings.

  Under `--warnings-as-errors`, these warnings block compilation.

  The fix removes the private function definition entirely when it is
  not called from anywhere in the module (including from within itself).
  Functions called from `quote` blocks in macros are left alone — those
  are handled by `NoPrivateFnCalledFromMacroQuote`, which promotes them
  to `def` instead.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @unused_pattern ~r/^function (\w+)\/(\d+) is unused$/

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.match?(msg, @unused_pattern)
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg} = diagnostic) do
    %Issue{
      rule: :no_unused_private_function,
      message: msg,
      meta: %{line: extract_line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    case Regex.run(@unused_pattern, msg) do
      [_, fun_name, arity_str] ->
        arity = String.to_integer(arity_str)
        fun_atom = String.to_atom(fun_name)

        case Sourceror.parse_string(source) do
          {:ok, ast} ->
            if genuinely_unused?(ast, fun_atom, arity) do
              new_ast = remove_defp_from_ast(ast, fun_atom, arity)

              case Sourceror.to_string(new_ast) do
                result when is_binary(result) -> result
                _ -> source
              end
            else
              source
            end

          _ ->
            source
        end

      _ ->
        source
    end
  end

  defp extract_line(%{position: {line, _col}}), do: line
  defp extract_line(%{position: line}) when is_integer(line), do: line

  # Check whether `fun_atom/arity` is genuinely unused — i.e. no call to it
  # exists outside its own `defp` definitions.  We build a "definitions-removed"
  # AST and then look for remaining calls.  If none remain, the function is
  # unused (even if it is recursive — its self-calls vanish with the defp).
  defp genuinely_unused?(ast, fun_atom, arity) do
    ast_without_defs = remove_defp_from_ast(ast, fun_atom, arity)
    not call_exists?(ast_without_defs, fun_atom, arity)
  end

  # Walk the AST and return `true` as soon as we find a call to
  # `fun_atom/arity` (a node `{:fun_atom, _, args}` where `args` is a list of
  # the correct length).
  defp call_exists?(ast, fun_atom, arity) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {^fun_atom, _, args} = node, _acc when is_list(args) and length(args) == arity ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Remove every `defp fun_atom/arity` clause from `__block__` nodes in the AST.
  defp remove_defp_from_ast(ast, fun_atom, arity) do
    Macro.prewalk(ast, fn
      {:__block__, meta, children} = node when is_list(children) ->
        filtered = Enum.reject(children, &defp_clause?(&1, fun_atom, arity))

        if length(filtered) != length(children) do
          {:__block__, meta, filtered}
        else
          node
        end

      node ->
        node
    end)
  end

  # True when `node` is a `defp fun_atom` clause with the given arity.
  # Handles both `defp foo, do: ...` (nil args, arity 0) and
  # `defp foo(x, y), do: ...` (list args).
  defp defp_clause?({:defp, _, [{name, _, args} | _]}, fun_atom, arity)
       when name == fun_atom do
    (is_nil(args) and arity == 0) or (is_list(args) and length(args) == arity)
  end

  defp defp_clause?(_, _, _), do: false
end
