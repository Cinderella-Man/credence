defmodule Credence.Semantic.FixNestedModuleShortReference do
  @moduledoc """
  Fixes short references to nested modules that the compiler rejects.

  When a module defines a nested `defmodule`, calling the nested module by its
  short name (e.g. `Coordinator.start_link()`) instead of the fully-qualified
  name (e.g. `WorkStealQueue.Coordinator.start_link()`) triggers a compiler
  warning:

      "redefining module ParentModule (current version loaded from ...)"

  The fix replaces all short references to nested modules with their
  fully-qualified form, guided by the compiler's own diagnostic.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, "redefining module") and
      not standard_library_path?(msg) and
      not recompilation_artifact?(msg)
  end

  def match?(_), do: false

  # Standard library modules (Config, Mix, etc.) trigger "redefining module"
  # warnings when compiled in a test environment. These are false positives —
  # the fix is for user-defined modules with nested defmodule blocks.
  defp standard_library_path?(msg) do
    String.contains?(msg, "/lib/elixir/ebin/") or
      String.contains?(msg, "/lib/mix/ebin/") or
      String.contains?(msg, "/lib/iex/ebin/") or
      String.contains?(msg, "/lib/ex_unit/ebin/") or
      String.contains?(msg, "/lib/eex/ebin/") or
      String.contains?(msg, "/lib/logger/ebin/")
  end

  # When a module was already compiled in a prior pass, the compiler emits a
  # "redefining module X (current version loaded from .../ebin/Elixir.X.beam)"
  # diagnostic. These are normal recompilation artifacts, not actual nested-
  # module reference problems.
  defp recompilation_artifact?(msg) do
    String.contains?(msg, "current version loaded from")
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_nested_module_short_reference,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    case extract_parent_module(diagnostic.message) do
      nil ->
        source

      parent ->
        nested = find_nested_modules(source, parent)

        Enum.reduce(nested, source, fn name, acc ->
          pattern =
            Regex.compile!(
              "(?<!\\.)(?<![A-Za-z0-9_])" <> Regex.escape(name) <> "\\."
            )

          Regex.replace(pattern, acc, "#{parent}.#{name}.")
        end)
    end
  end

  defp extract_parent_module(message) do
    case Regex.run(~r/redefining module (\w+)/, message) do
      [_, name] -> name
      _ -> nil
    end
  end

  # Find all defmodule declarations with simple names (no dots) that are
  # indented (nested inside another module), excluding the parent itself.
  defp find_nested_modules(source, parent) do
    Regex.scan(
      ~r/^\s+defmodule\s+([A-Z][A-Za-z0-9_]*)\s+do/m,
      source,
      capture: :all_but_first
    )
    |> Enum.map(&List.first/1)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == parent))
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
