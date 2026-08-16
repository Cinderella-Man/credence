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
  alias Credence.SourceMask

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

    with true <- is_integer(line_no),
         true <- is_binary(var_name),
         {:ok, stripped} <- rename(var_name) do
      replace_in_clause(source, line_no - 1, var_name, stripped)
    else
      _ -> source
    end
  end

  # The new name is the old one with **every** leading underscore removed, and
  # it must still be a variable. Both halves were missing, and each was a live
  # defect found by the T2.5 idempotency sweep:
  #
  #   `_MODULE` -> `MODULE`   an ALIAS, not a variable. `MODULE = :mod` compiles
  #                           clean and raises MatchError at *runtime* — the
  #                           "output compiles but means something else" class
  #                           (docs/22 §3), the worst shape a fix can have.
  #   `__foo`   -> `_foo`     still underscore-prefixed, so the rule fires again
  #                           on the next pass, and again: `__MODULE` walked to
  #                           `_MODULE` and then to `MODULE` one underscore per
  #                           pass. That is how the alias case was reached.
  #   `_`       -> `""`       an empty name spliced over every `_` in the clause.
  #
  # Declining is always safe here: the diagnostic is a warning about a naming
  # convention, so leaving the source alone costs a lint message, while renaming
  # to a non-variable costs the program.
  @variable ~r/^[a-z][A-Za-z0-9_]*$/

  defp rename(var_name) do
    stripped =
      String.replace_prefix(var_name, String.duplicate("_", leading_underscores(var_name)), "")

    if Regex.match?(@variable, stripped), do: {:ok, stripped}, else: :error
  end

  defp leading_underscores(name) do
    name |> String.graphemes() |> Enum.take_while(&(&1 == "_")) |> length()
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
  # Renames only in CODE position. The rename used to run a plain
  # `Regex.replace` over each raw line in the clause, so a mention of the same
  # variable in a trailing comment or a string was renamed too — measured:
  # `def check(_limit, v) do  # def check(_limit, v) do` came back with the
  # comment rewritten. That is the byte-scope class (docs/22 T3.7, T3.10), and
  # `Credence.SourceMask` is the repair: match on the shadow, splice into the
  # line. Mask the whole FILE, never a line alone — heredoc state crosses lines.
  defp replace_in_clause(source, target_idx, old, new) do
    pairs = SourceMask.lines(source)
    lines = Enum.map(pairs, &elem(&1, 0))
    {clause_start, clause_end} = find_clause_bounds(lines, target_idx)

    pattern =
      Regex.compile!("(?<![a-zA-Z0-9_?!])" <> Regex.escape(old) <> "(?![a-zA-Z0-9_?!])")

    pairs
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {{line, shadow}, idx} ->
      if idx >= clause_start and idx <= clause_end do
        SourceMask.replace_code(line, shadow, pattern, new)
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
