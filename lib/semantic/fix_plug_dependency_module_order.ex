defmodule Credence.Semantic.FixPlugDependencyModuleOrder do
  @moduledoc """
  Fixes compiler errors when a `plug SomeModule` call appears in a `Plug.Router`
  module defined before the dependency module in the same file.

  `Plug.Builder` calls `init/1` at compile time, so the plugged module must be
  compiled first. When the dependency module is defined after the router, the
  compiler emits:

      function SomeModule.init/1 is undefined (module SomeModule is not available)

  The fix reorders module definitions so the dependency module comes first.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_fragment "is undefined (module"
  @match_suffix "is not available)"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_fragment) and String.contains?(msg, @match_suffix)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_plug_dependency_module_order,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    with true <- String.contains?(msg, @match_fragment),
         {:ok, module_name} <- extract_module_name(msg) do
      reorder_modules(source, module_name)
    else
      _ -> source
    end
  end

  def fix(source, _diagnostic), do: source

  # Extract the module name from "function Module.init/1 is undefined (module Module is not available)"
  defp extract_module_name(msg) do
    case Regex.run(~r/function\s+([\w.]+)\.init\/1\s+is\s+undefined/, msg) do
      [_, mod_str] -> {:ok, mod_str}
      _ -> :error
    end
  end

  # Reorder module definitions so the dependency module comes first.
  defp reorder_modules(source, module_name) do
    lines = String.split(source, "\n")

    case find_module_range(lines, module_name) do
      {:ok, dep_start, dep_end} ->
        case find_using_module_range(lines, module_name) do
          {:ok, user_start, user_end} ->
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
    alias_pattern = Regex.escape(module_name)

    Enum.find_value(Enum.with_index(lines, 1), :error, fn {line, idx} ->
      if Regex.match?(~r/^\s*defmodule\s+#{alias_pattern}\s+do\s*$/, line) do
        case find_matching_end(lines, idx) do
          {:ok, end_idx} -> {:ok, idx, end_idx}
          :error -> nil
        end
      end
    end)
  end

  # Find the first defmodule that uses the dependency via `plug DependencyModule`
  defp find_using_module_range(lines, module_name) do
    # Try full module name first, then short alias (last segment).
    # After `alias Foo.Bar.Baz`, a `plug Baz` call resolves to `Foo.Bar.Baz`.
    short_name = module_name |> String.split(".") |> List.last()

    patterns =
      if short_name == module_name do
        [~r/^\s*plug[\s(]+:?\s*#{Regex.escape(module_name)}\b/]
      else
        [
          ~r/^\s*plug[\s(]+:?\s*#{Regex.escape(module_name)}\b/,
          ~r/^\s*plug[\s(]+:?\s*#{Regex.escape(short_name)}\b/
        ]
      end

    Enum.find_value(patterns, :error, fn plug_pattern ->
      case find_plug_caller(lines, plug_pattern) do
        {:ok, _, _} = result -> result
        :error -> nil
      end
    end)
  end

  defp find_plug_caller(lines, plug_pattern) do
    Enum.find_value(Enum.with_index(lines, 1), :error, fn {line, idx} ->
      if Regex.match?(plug_pattern, line) do
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
  defp find_matching_end(lines, start_line) do
    start_indent = get_indent(Enum.at(lines, start_line - 1, ""))
    do_find_end(lines, start_line + 1, start_indent, 0)
  end

  defp do_find_end(lines, idx, _start_indent, _depth) when idx > length(lines), do: :error

  defp do_find_end(lines, idx, start_indent, depth) do
    line = Enum.at(lines, idx - 1, "")
    trimmed = String.trim(line)

    cond do
      Regex.match?(~r/\bdo\s*$/, trimmed) ->
        do_find_end(lines, idx + 1, start_indent, depth + 1)

      trimmed == "end" and get_indent(line) == start_indent and depth == 0 ->
        {:ok, idx}

      trimmed == "end" ->
        do_find_end(lines, idx + 1, start_indent, depth - 1)

      true ->
        do_find_end(lines, idx + 1, start_indent, depth)
    end
  end

  # Reorder: move the dependency module before the user module.
  defp do_reorder(lines, dep_start, dep_end, user_start, user_end) do
    total = length(lines)

    before = if user_start > 1, do: Enum.slice(lines, 0..(user_start - 2)), else: []
    user_mod = Enum.slice(lines, (user_start - 1)..(user_end - 1))
    gap = if user_end < dep_start - 1, do: Enum.slice(lines, user_end..(dep_start - 2)), else: []
    dep_mod = Enum.slice(lines, (dep_start - 1)..(dep_end - 1))
    after_dep = if dep_end < total, do: Enum.slice(lines, dep_end..(total - 1)), else: []

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
