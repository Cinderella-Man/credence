defmodule Credence.Semantic.UsedUnderscoreVariable do
  @moduledoc """
  Fixes compiler warnings about underscored variables that are referenced
  after being set, by removing the leading underscore.

  LLMs often generate function heads where a parameter is underscore-prefixed
  (signalling "unused") but then referenced in a guard or the function body:

      defp helper(_target_n, index, _acc) when index > _target_n do
        Enum.reverse(_acc)
      end

  The underscore prefix signals "unused," but the guard and body reference
  the variables. This produces compiler warnings that become hard errors
  under `--warnings-as-errors`.

  The fix finds the enclosing function clause and renames the variable
  throughout the entire clause (both the parameter declaration and all
  usages in the guard/body), leaving other clauses untouched.
  """
  use Credence.Semantic.Rule
  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) do
    String.contains?(msg, "is used after being set")
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :used_underscore_variable,
      message: msg,
      meta: %{line: extract_line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: position}) do
    line_no = extract_line(position)
    var_name = extract_variable_name(msg)

    if line_no && var_name && String.starts_with?(var_name, "_") do
      stripped = String.slice(var_name, 1..-1//1)
      replace_in_clause(source, line_no - 1, var_name, stripped)
    else
      source
    end
  end

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  defp extract_variable_name(msg) do
    case Regex.run(~r/variable "([^"]+)" is used after being set/, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  # Replace the variable throughout the enclosing function clause,
  # covering both the parameter declaration and all body/guard usages.
  defp replace_in_clause(source, target_idx, old, new) do
    lines = String.split(source, "\n")
    {clause_start, clause_end} = find_clause_bounds(lines, target_idx)

    pattern =
      Regex.compile!(
        "(?<![a-zA-Z0-9_?!])" <> Regex.escape(old) <> "(?![a-zA-Z0-9_?!])"
      )

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, idx} ->
      if idx >= clause_start and idx <= clause_end do
        Regex.replace(pattern, line, new)
      else
        line
      end
    end)
    |> Enum.join("\n")
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
