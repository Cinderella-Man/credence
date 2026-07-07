defmodule Credence.Semantic.NoImportLocalFunctionConflict do
  @moduledoc """
  Fixes the compile error caused by a local `defp` that shadows an imported function.

  When a module imports another module (e.g., `import StreamData`) and defines a
  private function with the same name as one of the imported functions, the compiler
  emits:

      "imported StreamData.date/1 conflicts with local function"

  The fix renames the local `defp` to `generate_<name>` and updates all internal
  call sites. This rule excludes `to_string` conflicts, which are handled separately
  by `NoDefineToString`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @import_conflict_re ~r/imported [\w.]+\.(?<func>\w+)\/\d+ conflicts with local function/

  # Higher priority (lower number) than NoDefineToString (500) so this rule
  # runs first. Its match? excludes "to_string" so that NoDefineToString still
  # handles those conflicts.
  @impl true
  def priority, do: 400

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    case Regex.named_captures(@import_conflict_re, msg) do
      %{"func" => func} -> func != "to_string"
      _ -> false
    end
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_import_local_function_conflict,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) when is_binary(msg) do
    case Regex.named_captures(@import_conflict_re, msg) do
      %{"func" => func_name} ->
        rename_local_conflict(source, String.to_atom(func_name))

      _ ->
        source
    end
  end

  def fix(source, _diagnostic), do: source

  defp rename_local_conflict(source, func_name) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      new_name = :"generate_#{func_name}"

      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          # Match defp <name>(...) ... — rename the function definition
          {:defp, meta, [{^func_name, fmeta, args}, body]}, _acc ->
            {{:defp, meta, [{new_name, fmeta, args}, body]}, true}

          # Match <name>(args) call sites — rename
          {^func_name, meta, args}, _acc when is_list(args) ->
            {{new_name, meta, args}, true}

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
