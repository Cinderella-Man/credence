defmodule Credence.Semantic.NoUnusedTypeDeclaration do
  @moduledoc """
  Removes unused `@typep` declarations that trigger
  "type X/N is unused" compiler warnings.

  Under `--warnings-as-errors`, these warnings block compilation.

  The fix removes the entire `@typep` declaration since the compiler
  has already confirmed it is never referenced anywhere in the module.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @unused_type_pattern ~r/^type (\w+)\/(\d+) is unused$/

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.match?(msg, @unused_type_pattern)
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg} = diagnostic) do
    %Issue{
      rule: :no_unused_type_declaration,
      message: msg,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    case Regex.run(@unused_type_pattern, msg) do
      [_, type_name, _arity_str] ->
        type_atom = String.to_atom(type_name)

        case Sourceror.parse_string(source) do
          {:ok, ast} ->
            new_ast = remove_typep_from_ast(ast, type_atom)

            case Sourceror.to_string(new_ast) do
              result when is_binary(result) -> result
              _ -> source
            end

          _ ->
            source
        end

      _ ->
        source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line

  # Walk the AST and remove @typep declarations matching the given type name
  # from `:__block__` nodes.
  defp remove_typep_from_ast(ast, type_atom) do
    Macro.prewalk(ast, fn
      {:__block__, meta, children} = node when is_list(children) ->
        filtered = Enum.reject(children, &typep_clause?(&1, type_atom))

        if length(filtered) != length(children) do
          case filtered do
            [single] -> single
            _ -> {:__block__, meta, filtered}
          end
        else
          node
        end

      node ->
        node
    end)
  end

  # True when `node` is a `@typep type_atom :: ...` declaration.
  defp typep_clause?({:@, _, [{:typep, _, [{:"::", _, [{name, _, nil} | _]}]}]}, type_atom)
       when is_atom(name) do
    name == type_atom
  end

  defp typep_clause?(_, _), do: false
end
