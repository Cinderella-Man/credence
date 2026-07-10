defmodule Credence.Syntax.NoDefpQualifiedName do
  @moduledoc """
  Detects and fixes `defp Module.function(...)` — valid Python, invalid Elixir.

  LLMs (especially those translating from Python) produce
  `defp Module.function(...)` which is valid Python but invalid Elixir syntax.
  Elixir's `defp` only accepts local names; a qualified name like
  `Macro.expand(...)` in a `defp` head causes a compile error:
  "invalid syntax in defp Macro.expand(...)".

  The fix renames the qualified `defp` to a local name derived from the module
  and function (e.g. `defp Macro.expand(...)` → `defp macro_expand(...)`) and
  updates all call sites within the same source.

  ## Bad (won't compile)

      defp Macro.expand({mod, fun, args}, _env) do
        fn -> apply(mod, fun, args) end
      end

  ## Good

      defp macro_expand({mod, fun, args}, _env) do
        fn -> apply(mod, fun, args) end
      end
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  # Match `defp` keyword followed by a qualified name: Module.function(
  # Module: PascalCase, may contain dots (e.g. Foo.Bar)
  # Function: starts with lowercase/underscore, may end with ! or ?
  @defp_qualified ~r/\bdefp\s+([A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*)\.([a-z_][a-zA-Z0-9_]*[?!]?)\(/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      case Regex.run(@defp_qualified, line) do
        [_match | _] ->
          [
            %Issue{
              rule: :no_defp_qualified_name,
              message:
                "`defp` with qualified name is not valid Elixir — use a local name instead.",
              meta: %{line: line_no}
            }
          ]

        nil ->
          []
      end
    end)
  end

  @impl true
  def fix(source) do
    case Regex.scan(@defp_qualified, source) do
      [] ->
        source

      matches ->
        # Deduplicate (module, function) pairs
        replacements =
          matches
          |> Enum.map(fn [_full, module, function] -> {module, function} end)
          |> Enum.uniq()

        # Apply each replacement: rename the qualified name to a local name
        Enum.reduce(replacements, source, fn {module, function}, acc ->
          local_name = Macro.underscore(module) <> "_" <> function

          call_pattern =
            Regex.compile!(
              "\\b" <> Regex.escape(module) <> "\\." <> Regex.escape(function) <> "\\("
            )

          Regex.replace(call_pattern, acc, local_name <> "(")
        end)
    end
  end
end
