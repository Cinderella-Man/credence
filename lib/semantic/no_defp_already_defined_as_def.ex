defmodule Credence.Semantic.NoDefpAlreadyDefinedAsDef do
  @moduledoc """
  Fixes compiler errors caused by LLMs defining a function as both `def` and
  `defp` with the same name and arity.

  LLMs commonly produce code like:

      def sequence(name, formatter_fn) do
        formatter_fn.(name)
      end

      defp sequence(name, formatter_fn) when is_function(formatter_fn, 1) do
        formatter_fn.(name + 1)
      end

  The compiler emits "defp X/N already defined as def" because Elixir does not
  allow a private clause with the same name/arity as a public one. The fix
  deterministically removes the `defp` clause, preserving any leading comments
  on the preceding sibling node.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "already defined as def"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_defp_already_defined_as_def,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    with {name, arity} <- extract_fn_name_arity(msg),
         {:ok, ast} <- Sourceror.parse_string(source),
         %Sourceror.Range{} = range <- find_defp_range(ast, name, arity) do
      delete_range(source, range)
    else
      _ -> source
    end
  end

  defp extract_fn_name_arity(msg) do
    case Regex.run(~r/defp (\w+)\/(\d+)/, msg) do
      [_, name, arity_str] -> {String.to_atom(name), String.to_integer(arity_str)}
      _ -> nil
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line

  defp find_defp_range(ast, name, arity) do
    {_ast, result} =
      Macro.prewalk(ast, nil, fn
        {:defp, _, _} = node, nil ->
          if defp_fn_name_arity(node) == {name, arity} do
            {node, Sourceror.get_range(node)}
          else
            {node, nil}
          end

        node, acc ->
          {node, acc}
      end)

    result
  end

  defp defp_fn_name_arity({:defp, _meta, [_head | _]} = node) do
    head =
      case node do
        {:defp, _, [{:when, _, [h | _]} | _]} -> h
        {:defp, _, [h | _]} -> h
      end

    case head do
      {name, _, args} when is_atom(name) and is_list(args) -> {name, length(args)}
      _ -> nil
    end
  end

  defp defp_fn_name_arity(_), do: nil

  defp delete_range(source, %Sourceror.Range{start: s, end: e}) do
    lines = String.split(source, "\n")
    start_idx = s[:line] - 1
    end_idx = e[:line] - 1

    # Also delete a preceding blank line (usually spacing before the defp clause)
    delete_from =
      if start_idx > 0 and String.trim(Enum.at(lines, start_idx - 1, "")) == "",
        do: start_idx - 1,
        else: start_idx

    new_lines = Enum.take(lines, delete_from) ++ Enum.drop(lines, end_idx + 1)
    Enum.join(new_lines, "\n")
  end
end
