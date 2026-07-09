defmodule Credence.Semantic.FixUndefinedUnderscoredBinding do
  @moduledoc """
  Fixes `undefined variable` errors caused by LLMs writing `_var` in a
  function-head destructuring (intending "unused" style) but then
  referencing `var` (no underscore) in the same clause body.

  LLMs frequently write patterns like:

      defp collect_overlapping(node, {q_start, _q_finish} = query, acc) do
        ... q_finish ...
      end

  where `_q_finish` is bound in the parameter pattern but `q_finish`
  (without underscore) is used in the body. The compiler emits
  `undefined variable "q_finish"` because `_q_finish` and `q_finish`
  are different bindings.

  The fix finds the underscore-prefixed binding in the enclosing function
  clause and removes the underscore, making the binding match the body usage.

  This is distinct from `FixUnderscoredPatternBindingForBodyUse` (which
  handles case/pattern-match contexts) — this rule targets the specific
  diagnostic captured from a `defp` clause with a destructured parameter.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :error, message: msg, file: file} = _diagnostic)
      when is_binary(msg) and is_binary(file) do
    case extract_var_name(msg) do
      nil ->
        false

      var_name ->
        underscore_name = "_" <> var_name

        case File.read(file) do
          {:ok, source} -> String.contains?(source, underscore_name)
          _ -> false
        end
    end
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :fix_undefined_underscored_binding,
      message: msg,
      meta: %{line: line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: position}) do
    var_name = extract_var_name(msg)
    line_no = extract_line(position)

    with true <- is_binary(var_name) and var_name != "",
         underscore_name = "_" <> var_name,
         true <- String.contains?(source, underscore_name),
         true <- is_integer(line_no) do
      replace_in_clause(source, line_no - 1, underscore_name, var_name)
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

  defp line({l, _col}) when is_integer(l), do: l
  defp line(l) when is_integer(l), do: l
  defp line(_), do: nil

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  # Replace the underscore-prefixed variable throughout the enclosing
  # function clause, covering both the parameter/pattern declaration and
  # all body usages.
  defp replace_in_clause(source, target_idx, old, new) do
    lines = String.split(source, "\n")
    {clause_start, clause_end} = find_clause_bounds(lines, target_idx)

    pattern =
      Regex.compile!(
        "(?<![a-zA-Z0-9_?!])" <> Regex.escape(old) <> "(?![a-zA-Z0-9_?!])"
      )

    lines
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {line, idx} ->
      if idx >= clause_start and idx <= clause_end do
        Regex.replace(pattern, line, new)
      else
        line
      end
    end)
  end

  # Find the def/defp line before and the matching end after the target line.
  defp find_clause_bounds(lines, target_idx) do
    start_idx =
      target_idx..0//-1
      |> Enum.find(target_idx, fn idx ->
        Regex.match?(~r/^\s*(def|defp)\s/, Enum.at(lines, idx))
      end)

    def_line = Enum.at(lines, start_idx)

    if one_liner?(def_line) do
      {start_idx, start_idx}
    else
      def_indent = leading_spaces(def_line)

      end_idx =
        (start_idx + 1)..(length(lines) - 1)//1
        |> Enum.find(start_idx, fn idx ->
          line = Enum.at(lines, idx)
          String.trim(line) == "end" and leading_spaces(line) == def_indent
        end)

      {start_idx, end_idx}
    end
  end

  defp one_liner?(line) do
    String.contains?(line, ", do:")
  end

  defp leading_spaces(line) do
    byte_size(line) - byte_size(String.trim_leading(line))
  end
end
