defmodule Credence.Semantic.FixUndefinedVariableInEquality do
  @moduledoc """
  Fixes `undefined variable` errors caused by LLMs attempting to bind a
  variable via equality in a `cond` clause.

  LLMs frequently write patterns like:

      cond do
        conn.path_info == ["api", "uploads", id] -> id
      end

  where `id` is used as if equality would bind it. The compiler emits
  `undefined variable "id"`. The fix pre-binds the variable from the
  matched structure before the `cond`:

      id = List.last(conn.path_info)
      cond do
        conn.path_info == ["api", "uploads", id] -> id
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :error, message: msg, file: file} = diagnostic)
      when is_binary(msg) and is_binary(file) do
    String.contains?(msg, "undefined variable") and
      source_has_list_equality_pattern?(diagnostic)
  end

  def match?(_), do: false

  defp source_has_list_equality_pattern?(%{message: msg, file: file}) do
    with {:ok, source} <- File.read(file),
         var_name when is_binary(var_name) <- extract_var_name(msg),
         {:ok, ast} <- Sourceror.parse_string(source) do
      var_atom = String.to_atom(var_name)
      find_list_with_var(ast, var_atom) != []
    else
      _ -> false
    end
  end

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :fix_undefined_variable_in_equality,
      message: msg,
      meta: %{line: line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    var_name = extract_var_name(msg)

    with true <- is_binary(var_name) and var_name != "",
         {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, list_expr, other_expr, var_position} <-
           find_equality_list_pattern(ast, var_name) do
      binding = build_binding(var_name, list_expr, other_expr, var_position)
      insert_binding_before_cond(source, binding)
    else
      _ -> source
    end
  end

  defp extract_var_name(msg) do
    case Regex.run(~r/undefined variable "(\w+)"/, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp find_equality_list_pattern(ast, var_name) do
    var_atom = String.to_atom(var_name)

    case find_list_with_var(ast, var_atom) do
      [{list_expr, other_expr, position} | _] ->
        {:ok, list_expr, other_expr, position}

      [] ->
        :error
    end
  end

  defp find_list_with_var(ast, var_atom) do
    {_ast, results} =
      Macro.prewalk(ast, [], fn
        {:==, _, [left, right]} = node, acc ->
          case {list_contains_var?(left, var_atom), list_contains_var?(right, var_atom)} do
            {true, _} ->
              pos = find_var_position(left, var_atom)
              {node, [{left, right, pos} | acc]}

            {_, true} ->
              pos = find_var_position(right, var_atom)
              {node, [{right, left, pos} | acc]}

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    results
  end

  defp list_contains_var?({:__block__, _, [list]} = _node, var_atom) when is_list(list) do
    Enum.any?(list, fn
      {^var_atom, _, nil} -> true
      _ -> false
    end)
  end

  defp list_contains_var?(_, _), do: false

  defp find_var_position({:__block__, _, [list]}, var_atom) when is_list(list) do
    Enum.find_index(list, fn
      {^var_atom, _, nil} -> true
      _ -> false
    end)
  end

  defp find_var_position(_, _), do: nil

  defp build_binding(var_name, list_expr, other_expr, var_position) do
    list_size = list_literal_size(list_expr)

    rhs =
      if var_position == list_size - 1 do
        "List.last(#{Sourceror.to_string(other_expr)})"
      else
        "Enum.at(#{Sourceror.to_string(other_expr)}, #{var_position})"
      end

    "#{var_name} = #{rhs}"
  end

  defp list_literal_size({:__block__, _, [list]}) when is_list(list), do: length(list)
  defp list_literal_size(_), do: 0

  defp insert_binding_before_cond(source, binding) do
    lines = String.split(source, "\n")

    case Enum.find_index(lines, &String.contains?(&1, "cond")) do
      nil ->
        source

      index ->
        indent = get_indent(Enum.at(lines, index))
        {before, after_} = Enum.split(lines, index)
        Enum.join(before ++ ["#{indent}#{binding}"] ++ after_, "\n")
    end
  end

  defp get_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end

  defp line({l, _col}) when is_integer(l), do: l
  defp line(l) when is_integer(l), do: l
  defp line(_), do: nil
end
