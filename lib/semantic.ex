defmodule Credence.Semantic do
  @moduledoc """
  Semantic-level fixes for compiler warnings.

  Uses `Code.with_diagnostics/1` to compile the source and capture
  warnings without permanently loading modules. Then applies targeted
  fixes based on the diagnostic messages.

  Currently handles:
  - **Unused variables** — prefixes with `_` (e.g. `current_sum` → `_current_sum`)
  - **Undefined functions** — known replacements (e.g. `Enum.last/1` → `List.last/1`)
  """
  alias Credence.Issue

  @doc """
  Detects compiler warnings in the given source code.
  Returns `[]` if code compiles cleanly or can't compile at all.
  """
  @spec analyze(String.t(), keyword()) :: [Issue.t()]
  def analyze(source, _opts \\ []) do
    case compile_and_capture(source) do
      {:ok, diagnostics} ->
        diagnostics
        |> Enum.filter(&fixable_warning?/1)
        |> Enum.map(&diagnostic_to_issue/1)

      _error ->
        []
    end
  end

  @doc """
  Applies fixes for compiler warnings. Returns source unchanged if
  no warnings found or code can't compile.
  """
  @spec fix(String.t(), keyword()) :: String.t()
  def fix(source, _opts \\ []) do
    case compile_and_capture(source) do
      {:ok, diagnostics} ->
        warnings = Enum.filter(diagnostics, &fixable_warning?/1)
        apply_fixes(source, warnings)

      _error ->
        source
    end
  end

  # ── Compilation with diagnostics ────────────────────────────────

  defp compile_and_capture(source) do
    {result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          Code.compile_string(source, "credence_check.ex")
        rescue
          e -> {:error, e}
        end
      end)

    case result do
      {:error, _} ->
        {:error, diagnostics}

      modules when is_list(modules) ->
        cleanup_modules(modules)
        {:ok, diagnostics}
    end
  end

  defp cleanup_modules(modules) do
    for {mod, _binary} <- modules do
      :code.purge(mod)
      :code.delete(mod)
    end
  end

  # ── Warning classification ──────────────────────────────────────

  defp fixable_warning?(%{severity: :warning, message: msg}) do
    unused_variable?(msg) or undefined_function?(msg)
  end

  defp fixable_warning?(_), do: false

  defp unused_variable?(msg), do: String.match?(msg, ~r/variable ".*" is unused/)
  defp undefined_function?(msg), do: String.contains?(msg, "is undefined or private")

  # ── Fix application ─────────────────────────────────────────────

  defp apply_fixes(source, warnings) do
    Enum.reduce(warnings, source, fn warning, src ->
      cond do
        unused_variable?(warning.message) -> fix_unused_variable(src, warning)
        undefined_function?(warning.message) -> fix_undefined_function(src, warning)
        true -> src
      end
    end)
  end

  # ── Unused variable fix ─────────────────────────────────────────
  #
  # Compiler warning: variable "X" is unused
  # Fix: prefix with _ on the reported line

  defp fix_unused_variable(source, %{message: msg, position: position}) do
    line_no = extract_line(position)
    var_name = extract_variable_name(msg)

    if line_no && var_name && not String.starts_with?(var_name, "_") do
      replace_on_line(source, line_no, var_name, "_#{var_name}")
    else
      source
    end
  end

  # ── Undefined function fix ──────────────────────────────────────
  #
  # Known replacements for common LLM mistakes

  @undefined_replacements %{
    {"Enum", "last", 1} => {"List", "last"},
    {"Enum", "last", 0} => {"List", "last"}
  }

  defp fix_undefined_function(source, %{message: msg, position: position}) do
    line_no = extract_line(position)

    case parse_undefined_function(msg) do
      {mod, fun, arity} ->
        case Map.get(@undefined_replacements, {mod, fun, arity}) do
          {new_mod, new_fun} ->
            replace_on_line(source, line_no, "#{mod}.#{fun}", "#{new_mod}.#{new_fun}")

          nil ->
            source
        end

      nil ->
        source
    end
  end

  # ── Parsing helpers ─────────────────────────────────────────────

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  defp extract_variable_name(msg) do
    case Regex.run(~r/variable "([^"]+)" is unused/, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp parse_undefined_function(msg) do
    case Regex.run(~r/(\w+)\.(\w+)\/(\d+) is undefined or private/, msg) do
      [_, mod, fun, arity] -> {mod, fun, String.to_integer(arity)}
      _ -> nil
    end
  end

  # ── String replacement on a specific line ───────────────────────

  defp replace_on_line(source, line_no, old, new) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn
      {line, ^line_no} -> String.replace(line, old, new, global: false)
      {line, _} -> line
    end)
    |> Enum.join("\n")
  end

  # ── Issue building ──────────────────────────────────────────────

  defp diagnostic_to_issue(%{message: msg, position: position, severity: :warning}) do
    %Issue{
      rule: classify_warning(msg),
      message: msg,
      meta: %{line: extract_line(position) || 0}
    }
  end

  defp classify_warning(msg) do
    cond do
      unused_variable?(msg) -> :unused_variable
      undefined_function?(msg) -> :undefined_function
      true -> :compiler_warning
    end
  end
end
