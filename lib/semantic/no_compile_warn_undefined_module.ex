defmodule Credence.Semantic.NoCompileWarnUndefinedModule do
  @moduledoc """
  Adds `@compile {:no_warn_undefined, Module}` when the compiler warns that
  a remote call targets an undefined module (the module is not available or
  is yet to be defined).

  The compiler emits:

      SomeModule.fun/arity is undefined (module SomeModule is not available or is yet to be defined)

  The idiomatic fix is to suppress the warning for that specific module:

      @compile {:no_warn_undefined, SomeModule}
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_suffix " is not available or is yet to be defined)"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "is undefined (module ") and String.ends_with?(msg, @match_suffix)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_compile_warn_undefined_module,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    module_name = extract_module(diagnostic.message)

    if module_name == "" do
      source
    else
      if already_has_attribute?(source, module_name) do
        source
      else
        insert_attribute(source, module_name)
      end
    end
  end

  # Extract the module name from the diagnostic message.
  # "MyApp.Repo.insert!/1 is undefined (module MyApp.Repo is not available or is yet to be defined)"
  # -> "MyApp.Repo"
  defp extract_module(msg) do
    case Regex.run(~r/is undefined \(module (.+) is not available/, msg) do
      [_, mod] -> mod
      _ -> ""
    end
  end

  # Check if the source already has `@compile {:no_warn_undefined, ModuleName}`.
  defp already_has_attribute?(source, module_name) do
    String.contains?(source, "@compile {:no_warn_undefined, #{module_name}}")
  end

  # Insert `@compile {:no_warn_undefined, ModuleName}` as the first expression
  # inside the defmodule do block.
  defp insert_attribute(source, module_name) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         do_line when not is_nil(do_line) <- find_defmodule_do_line(ast) do
      lines = String.split(source, "\n")
      indent = detect_indent(lines, do_line)
      attr_line = "#{indent}@compile {:no_warn_undefined, #{module_name}}"
      {before, after_lines} = Enum.split(lines, do_line)
      Enum.join(before ++ [attr_line] ++ after_lines, "\n")
    else
      _ -> source
    end
  end

  # Walk the AST to find the line of the `do` keyword in the top-level defmodule.
  defp find_defmodule_do_line(ast) do
    {_ast, result} =
      Macro.prewalk(ast, nil, fn
        {:defmodule, meta, [_alias, body]} = node, nil when is_list(body) ->
          case Keyword.get(meta, :do) do
            [{:line, line} | _] -> {node, line}
            _ -> {node, nil}
          end

        node, acc ->
          {node, acc}
      end)

    result
  end

  # Detect the indentation of the line following the do-line.
  # do_line is 1-based; Enum.at uses 0-based indexing, so the next line is at index == do_line.
  defp detect_indent(lines, do_line) do
    case Enum.at(lines, do_line) do
      nil ->
        "  "

      line ->
        case Regex.run(~r/^(\s*)/, line) do
          [_, indent] when indent != "" -> indent
          _ -> "  "
        end
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
