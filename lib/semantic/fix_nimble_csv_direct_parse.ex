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

  The rewrite is deliberately narrow — the fix is a no-op whenever the target
  parser is not unambiguous:

    * the diagnostic must reference `NimbleCSV.parse_string/1` or `/2` itself
      (defined parsers export exactly those arities; a message about
      `Foo.NimbleCSV.parse_string` or another arity is not fixable this way);
    * the file must contain exactly one `NimbleCSV.define/2` target — several
      distinct parsers make the intended one a guess;
    * the define target must be a literal alias (`__MODULE__.Parser`, a
      variable, etc. cannot be resolved textually);
    * only a standalone `NimbleCSV.parse_string` reference on the reported
      line is rewritten, never one embedded in a longer module path such as
      `Foo.NimbleCSV.parse_string`.

  `UndefinedFunction` matches this same message and declares priority 501
  against this rule's default 500, so the ordering is stated rather than
  inherited from where the module names sort (docs/20 §1). It repairs by
  table lookup, and the parser name cannot go in a table — it is whatever
  alias the file passed to `NimbleCSV.define/2`, which only an AST walk can
  recover. It has no row for either arity, and its `FunctionMatcher`
  fallback finds no `defmodule NimbleCSV` in the file, so its `fix/2`
  returns the source byte-identical.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # Standalone `NimbleCSV.parse_string` (not `Foo.NimbleCSV....`), arity 1 or 2
  # only — those are the arities a defined parser actually exports.
  @diag_re ~r{(?<![\w.])NimbleCSV\.parse_string/[12] is undefined or private}
  @call_re ~r{(?<![\w.])NimbleCSV\.parse_string(?![\w!?])}

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    Regex.match?(@diag_re, msg)
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source, so files without a resolvable
  `NimbleCSV.define/2` (none, several, or a non-literal target) are not
  attributed to this rule.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

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

  # Walk the AST collecting every `NimbleCSV.define(Target, ...)` call.
  # Returns `{:ok, "ParserModule"}` only when the file names exactly one
  # resolvable parser; `:not_found` when there is none, more than one distinct
  # target, or any target that is not a literal alias (`__MODULE__.Parser`, a
  # variable, ...) — those make the intended parser ambiguous.
  defp find_nimble_csv_define(ast) do
    {_, defines} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:NimbleCSV]}, :define]}, _meta, [target | _]} = node, acc ->
          {node, [classify_target(target) | acc]}

        node, acc ->
          {node, acc}
      end)

    case Enum.uniq(defines) do
      [parser] when is_binary(parser) -> {:ok, parser}
      _ -> :not_found
    end
  end

  defp classify_target({:__aliases__, _, parts}) do
    if Enum.all?(parts, &is_atom/1), do: parts_to_module_string(parts), else: :unresolvable
  end

  defp classify_target(_), do: :unresolvable

  # Convert alias parts to a dotted module string: [:CsvLoader, :Parser] → "CsvLoader.Parser"
  defp parts_to_module_string(parts) do
    Enum.map_join(parts, ".", &Atom.to_string/1)
  end

  # Replace the first standalone `NimbleCSV.parse_string` with
  # `<Parser>.parse_string` on the target line.
  defp replace_on_line(source, line_no, parser_name) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {line, ^line_no} ->
        Regex.replace(@call_re, line, "#{parser_name}.parse_string", global: false)

      {line, _} ->
        line
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
