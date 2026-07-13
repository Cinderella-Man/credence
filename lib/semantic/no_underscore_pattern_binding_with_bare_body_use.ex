defmodule Credence.Semantic.NoUnderscorePatternBindingWithBareBodyUse do
  @moduledoc """
  Fixes compiler warnings about unused underscore-prefixed pattern bindings
  when the bare name (without underscore) is referenced in the body.

  LLMs frequently write patterns like:

      case name do
        [{^name, {value, _old_name}}] ->
          IO.puts(old_name)
      end

  where `_old_name` is bound in the pattern but `old_name` (without underscore)
  is used in the body.  The compiler emits a warning that `_old_name` is unused
  (and separately an error that `old_name` is undefined — handled by
  `FixUnderscoredPatternBindingForBodyUse`).

  The fix removes the underscore prefix from the binding so the pattern binding
  matches the body usage.

  This is distinct from `FixUnderscoredPatternBindingForBodyUse` (which matches
  the `undefined variable` error) and `UnusedVariable` (which adds underscores
  to genuinely unused variables).  This rule targets the warning diagnostic and
  removes the underscore only when the bare name is actually referenced in the
  enclosing clause body.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.match?(msg, ~r/variable "_\w+" is unused/)
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :no_underscore_pattern_binding_with_bare_body_use,
      message: msg,
      meta: %{line: line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: position}) do
    var_name = extract_var_name(msg)
    line_no = extract_line(position)

    with true <- is_binary(var_name) and var_name != "",
         "_" <> bare_name = var_name,
         true <- bare_name != "",
         true <- has_standalone_occurrence?(source, bare_name),
         true <- is_integer(line_no) do
      replace_in_clause(source, line_no - 1, var_name, bare_name)
    else
      _ -> source
    end
  end

  defp extract_var_name(msg) do
    case Regex.run(~r/variable "(_\w+)" is unused/, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp has_standalone_occurrence?(source, name) do
    Regex.match?(~r/(?<![a-zA-Z0-9_])#{Regex.escape(name)}(?![a-zA-Z0-9_])/, source)
  end

  defp line({l, _col}) when is_integer(l), do: l
  defp line(l) when is_integer(l), do: l
  defp line(_), do: nil

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  # Replace the underscore-prefixed variable throughout the enclosing
  # function clause, covering both the pattern declaration and all body usages.
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
