defmodule Credence.Semantic.FixNimbleCsvDirectParse do
  @moduledoc """
  Fixes direct `NimbleCSV.parse_string/2` calls when a parser module was
  defined via `NimbleCSV.define/2` in the same file.

  LLMs commonly write:

      NimbleCSV.define(MyApp.Parser, separator: ",", escape: "\\"")
      # ... later ...
      NimbleCSV.parse_string(csv, skip_headers: false)

  instead of the correct:

      MyApp.Parser.parse_string(csv, skip_headers: false)

  The compiler emits:

      NimbleCSV.parse_string/2 is undefined or private

  The fix finds the `NimbleCSV.define(ParserModule, ...)` call in the same
  source file and rewrites `NimbleCSV.parse_string` to `ParserModule.parse_string`
  on the reported line.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "NimbleCSV.parse_string") and
      String.contains?(msg, "is undefined or private")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_nimble_csv_direct_parse,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    target_line = line(diagnostic)

    with {:ok, ast} <- Sourceror.parse_string(source) do
      case find_nimble_csv_define(ast) do
        {:ok, parser_name} ->
          replace_on_line(source, target_line, parser_name)

        :not_found ->
          source
      end
    else
      _ -> source
    end
  end

  # Walk the AST looking for `NimbleCSV.define(ParserModule, ...)`.
  # Returns `{:ok, "ParserModule"}` or `:not_found`.
  defp find_nimble_csv_define(ast) do
    {_, result} =
      Macro.prewalk(ast, :not_found, fn
        # Match: NimbleCSV.define(ParserModule, opts)
        {{:., _, [{:__aliases__, _, [:NimbleCSV]}, :define]}, _meta,
         [{:__aliases__, _, parts} | _]} = node,
        :not_found ->
          {node, {:ok, parts_to_module_string(parts)}}

        node, acc ->
          {node, acc}
      end)

    result
  end

  # Convert alias parts to a dotted module string: [:CsvLoader, :Parser] → "CsvLoader.Parser"
  defp parts_to_module_string(parts) do
    Enum.map_join(parts, ".", &Atom.to_string/1)
  end

  # Replace `NimbleCSV.parse_string` with `<Parser>.parse_string` on the target line.
  defp replace_on_line(source, line_no, parser_name) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {line, ^line_no} ->
        String.replace(line, "NimbleCSV.parse_string", "#{parser_name}.parse_string", global: false)

      {line, _} ->
        line
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
