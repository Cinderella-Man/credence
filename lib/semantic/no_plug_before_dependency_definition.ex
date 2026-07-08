defmodule Credence.Semantic.NoPlugBeforeDependencyDefinition do
  @moduledoc """
  Fixes compiler errors when a `plug SomeModule` call appears in a module that
  is defined BEFORE the dependency module in the same file.

  `Plug.Builder` calls `init/1` at compile time, so the plugged module must be
  compiled first. When LLMs define the using module before the dependency
  module, the compiler emits:

      function SomeModule.init/1 is undefined (module SomeModule is not available)

  The fix reorders module definitions so compile-time dependencies come first.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "function "
  @match_suffix " is undefined (module "
  @match_trail " is not available)"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_suffix) and
      String.contains?(msg, @match_trail) and
      String.contains?(msg, @match_prefix) and
      String.contains?(msg, ".init/1 is undefined")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_plug_before_dependency_definition,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    case extract_module_name(msg) do
      {:ok, module_name} ->
        reorder_modules(source, module_name)

      :error ->
        source
    end
  end

  # Extract the module name from the diagnostic message.
  # "function LifecycleApi.Plugs.ApiVersion.init/1 is undefined (module LifecycleApi.Plugs.ApiVersion is not available)"
  # -> "LifecycleApi.Plugs.ApiVersion"
  defp extract_module_name(msg) do
    case Regex.run(~r/function (.+)\.init\/1 is undefined/, msg) do
      [_, mod_str] -> {:ok, mod_str}
      _ -> :error
    end
  end

  # Reorder module definitions so the dependency module comes first.
  defp reorder_modules(source, module_name) do
    lines = String.split(source, "\n")

    case find_module_range(lines, module_name) do
      {:ok, dep_start, dep_end} ->
        # Find the first defmodule that uses this dependency via `plug`
        case find_using_module_range(lines, module_name) do
          {:ok, user_start, user_end} ->
            # Only reorder if the dependency is AFTER the user
            if dep_start > user_start do
              do_reorder(lines, dep_start, dep_end, user_start, user_end)
            else
              source
            end

          :error ->
            source
        end

      :error ->
        source
    end
  end

  # Find the line range (1-indexed) of a defmodule block by its module name.
  defp find_module_range(lines, module_name) do
    # Build the regex to match the defmodule declaration
    parts = String.split(module_name, ".")
    alias_pattern = Enum.join(parts, ".")

    Enum.find_value(Enum.with_index(lines, 1), :error, fn {line, idx} ->
      if Regex.match?(~r/^\s*defmodule\s+#{Regex.escape(alias_pattern)}\s+do\s*$/, line) do
        # Find the matching `end`
        case find_matching_end(lines, idx) do
          {:ok, end_idx} -> {:ok, idx, end_idx}
          :error -> nil
        end
      end
    end)
  end

  # Find the first defmodule that uses the dependency via `plug DependencyModule`
  defp find_using_module_range(lines, module_name) do
    # Convert module name to alias form for matching in `plug` calls
    # e.g. "LifecycleApi.Plugs.ApiVersion" -> "LifecycleApi.Plugs.ApiVersion"
    plug_pattern = ~r/^\s*plug\s+#{Regex.escape(module_name)}\s*$/

    Enum.find_value(Enum.with_index(lines, 1), :error, fn {line, idx} ->
      if Regex.match?(plug_pattern, line) do
        # Find the enclosing defmodule
        case find_enclosing_defmodule(lines, idx) do
          {:ok, user_start} ->
            case find_matching_end(lines, user_start) do
              {:ok, user_end} -> {:ok, user_start, user_end}
              :error -> nil
            end

          :error ->
            nil
        end
      end
    end)
  end

  # Find the enclosing defmodule for a given line number (search backwards).
  defp find_enclosing_defmodule(lines, line_no) do
    Enum.reduce_while((line_no - 1)..1//-1, :error, fn idx, acc ->
      line = Enum.at(lines, idx - 1)
      if line && Regex.match?(~r/^\s*defmodule\s+.*\bdo\s*$/, line) do
        {:halt, {:ok, idx}}
      else
        {:cont, acc}
      end
    end)
  end

  # Find the matching `end` for a `defmodule ... do` starting at start_line.
  # Starts searching from start_line + 1 (skips the defmodule line itself).
  defp find_matching_end(lines, start_line) do
    start_indent = get_indent(Enum.at(lines, start_line - 1, ""))
    do_find_end(lines, start_line + 1, start_indent, 0)
  end

  defp do_find_end(lines, idx, _start_indent, _depth) when idx > length(lines), do: :error

  defp do_find_end(lines, idx, start_indent, depth) do
    line = Enum.at(lines, idx - 1, "")
    trimmed = String.trim(line)

    cond do
      # Nested do block
      Regex.match?(~r/\bdo\s*$/, trimmed) ->
        do_find_end(lines, idx + 1, start_indent, depth + 1)

      # End at the same indent level as the defmodule
      trimmed == "end" and get_indent(line) == start_indent and depth == 0 ->
        {:ok, idx}

      # End at a deeper nesting level
      trimmed == "end" ->
        do_find_end(lines, idx + 1, start_indent, depth - 1)

      true ->
        do_find_end(lines, idx + 1, start_indent, depth)
    end
  end

  # Reorder: move the dependency module before the user module.
  # All positions are 1-indexed. dep_start > user_start (dep is after user).
  defp do_reorder(lines, dep_start, dep_end, user_start, user_end) do
    total = length(lines)

    # Segments (0-indexed slices):
    #   before: lines before user module
    #   user_mod: the user module (user_start..user_end, inclusive)
    #   gap: blank lines between user and dep (user_end+1..dep_start-1)
    #   dep_mod: the dep module (dep_start..dep_end, inclusive)
    #   after: lines after dep module
    before = if user_start > 1, do: Enum.slice(lines, 0..(user_start - 2)), else: []
    user_mod = Enum.slice(lines, (user_start - 1)..(user_end - 1))
    gap = if user_end < dep_start - 1, do: Enum.slice(lines, user_end..(dep_start - 2)), else: []
    dep_mod = Enum.slice(lines, (dep_start - 1)..(dep_end - 1))
    after_dep = if dep_end < total, do: Enum.slice(lines, dep_end..(total - 1)), else: []

    # Assemble: before + dep_mod + gap + user_mod + after_dep
    # The gap already contains blank lines that separated the modules originally.
    new_lines = before ++ dep_mod ++ gap ++ user_mod ++ after_dep
    Enum.join(new_lines, "\n")
  end

  defp get_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
