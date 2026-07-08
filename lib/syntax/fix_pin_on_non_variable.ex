defmodule Credence.Syntax.FixPinOnNonVariable do
  @moduledoc """
  Fixes `^` (pin operator) applied to non-variable expressions in pattern matching.

  The pin operator `^` can only be applied to variables in Elixir patterns.
  Using `^{expr}` on a tuple or other non-variable is a compile error:

      invalid argument for unary operator ^, expected an existing variable, got: ^{key}

  The fix removes the `^`, turning `^{key}` into `{key}`.

  ## Bad (won't compile)

      case value do
        [^{key}, rest] -> rest
      end

  ## Good

      case value do
        [{key}, rest] -> rest
      end
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @impl true
  def analyze(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_ast, issues} =
          Macro.prewalk(ast, [], fn
            {:^, meta, [arg]} = node, acc ->
              if non_variable?(arg) do
                issue = %Issue{
                  rule: :fix_pin_on_non_variable,
                  message:
                    "Pin operator `^` can only pin variables. " <>
                      "Remove `^` from the non-variable expression.",
                  meta: %{line: Keyword.get(meta, :line, 0)}
                }

                {node, [issue | acc]}
              else
                {node, acc}
              end

            node, acc ->
              {node, acc}
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
            {:^, _meta, [arg]} = node, acc ->
              if non_variable?(arg) do
                range = Sourceror.get_range(node)
                replacement = Sourceror.to_string(arg)
                {node, [%{range: range, change: replacement} | acc]}
              else
                {node, acc}
              end

            node, acc ->
              {node, acc}
          end)

        case patches do
          [] -> source
          _ -> Sourceror.patch_string(source, patches)
        end

      {:error, _} ->
        source
    end
  end

  # Returns true if the argument to `^` is NOT a simple variable.
  # Variables in Sourceror AST are {:name, meta, nil} where name is an atom.
  # Tuples, lists, literals, and other complex expressions are non-variables.
  defp non_variable?({:_, _, ctx}) when is_atom(ctx), do: true
  defp non_variable?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: false
  defp non_variable?(_), do: true
end
