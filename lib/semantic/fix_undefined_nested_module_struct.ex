defmodule Credence.Semantic.FixUndefinedNestedModuleStruct do
  @moduledoc """
  Fixes compiler errors when a nested module's struct (e.g. `%Parent.Child{}`)
  is used in the parent module defined before the child module in the same file.

  The compiler emits:

      Parent.Child.__struct__/1 is undefined (module Parent.Child is not available)

  The fix reorders module definitions so the child module comes first.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_fragment "is undefined (module"
  @match_suffix "is not available)"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_fragment) and
      String.contains?(msg, @match_suffix) and
      String.contains?(msg, ".__struct__/1")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_undefined_nested_module_struct,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    with true <- String.contains?(msg, @match_fragment),
         true <- String.contains?(msg, ".__struct__/1"),
         {:ok, child_name} <- extract_module_name(msg),
         true <- nested?(child_name),
         true <- struct_used?(source, child_name) do
      reorder_modules(source, child_name)
    else
      _ -> source
    end
  end

  def fix(source, _diagnostic), do: source

  # Extract the module name from "Module.Name.__struct__/1 is undefined (module Module.Name is not available)"
  defp extract_module_name(msg) do
    case Regex.run(~r/([\w.]+)\.__struct__\/1\s+is\s+undefined/, msg) do
      [_, mod_str] -> {:ok, mod_str}
      _ -> :error
    end
  end

  # True when child_name has at least one dot (is a nested module).
  defp nested?(child_name), do: String.contains?(child_name, ".")

  # True when source contains a struct usage like %ChildName{...}.
  defp struct_used?(source, child_name) do
    String.contains?(source, "%#{child_name}{")
  end

  # Reorder module definitions so the child module comes before its parent.
  defp reorder_modules(source, child_name) do
    lines = String.split(source, "\n")

    with {:ok, child_start, child_end} <- find_module_range(lines, child_name),
         parent_name <- parent_module_name(child_name),
         {:ok, parent_start, parent_end} <- find_module_range(lines, parent_name) do
      if child_start > parent_start do
        do_reorder(lines, child_start, child_end, parent_start, parent_end)
      else
        source
      end
    else
      _ -> source
    end
  end

  defp parent_module_name(child_name) do
    child_name
    |> String.split(".")
    |> Enum.drop(-1)
    |> Enum.join(".")
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

  # Reorder: move the child module before the parent module.
  defp do_reorder(lines, child_start, child_end, parent_start, parent_end) do
    total = length(lines)

    before = if parent_start > 1, do: Enum.slice(lines, 0..(parent_start - 2)), else: []
    parent_mod = Enum.slice(lines, (parent_start - 1)..(parent_end - 1))
    gap = if parent_end < child_start - 1, do: Enum.slice(lines, parent_end..(child_start - 2)), else: []
    child_mod = Enum.slice(lines, (child_start - 1)..(child_end - 1))
    after_child = if child_end < total, do: Enum.slice(lines, child_end..(total - 1)), else: []

    new_lines = before ++ child_mod ++ gap ++ parent_mod ++ after_child
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
