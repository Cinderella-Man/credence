defmodule Credence.Semantic.FixPythonStyleStructDefinition do
  @moduledoc """
  Fixes compile errors caused by Python-style struct definitions.

  When an LLM generates `defp struct Name do %{...} end` instead of
  `defstruct [:field1, :field2, ...]`, the code parses fine but produces:

      "Name.__struct__/1 is undefined, cannot expand struct Name"

  The fix extracts fields from the map literal, replaces the `defp struct`
  block with `defstruct`, and rewrites `%Name{}` to `%__MODULE__{}`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "__struct__/1 is undefined"

  @impl true
  def priority, do: 400

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_python_style_struct_definition,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      struct_info = find_python_structs(ast)

      case struct_info do
        [] ->
          source

        [_ | _] ->
          lines = String.split(source, "\n")

          # Apply replacements from bottom to top (by line) to preserve line numbers
          sorted =
            Enum.sort_by(struct_info, fn {_name, _parts, _fields, range} ->
              range.start[:line]
            end, :desc)

          result =
            Enum.reduce(sorted, lines, fn {_name, _parts, fields, range}, acc ->
              # Replace the defp struct block with defstruct
              start_idx = range.start[:line] - 1
              end_idx = range.end[:line] - 1
              indent = find_indent(Enum.at(acc, start_idx))
              field_str = Enum.map_join(fields, ", ", &":#{&1}")
              defstruct_line = "#{indent}defstruct [#{field_str}]"

              acc
              |> List.replace_at(start_idx, defstruct_line)
              |> remove_lines(start_idx + 1, end_idx)
            end)

          # Replace %Name{ with %__MODULE__{
          result_str =
            result
            |> Enum.join("\n")
            |> replace_struct_refs(struct_info)

          # Ensure trailing newline is preserved
          if String.ends_with?(source, "\n") and not String.ends_with?(result_str, "\n") do
            result_str <> "\n"
          else
            result_str
          end
      end
    else
      _ -> source
    end
  end

  defp find_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end

  defp remove_lines(lines, from, to) when from > to, do: lines

  defp remove_lines(lines, from, to) do
    Enum.reject(Enum.with_index(lines), fn {_line, idx} -> idx >= from and idx <= to end)
    |> Enum.map(&elem(&1, 0))
  end

  defp replace_struct_refs(source, struct_info) do
    Enum.reduce(struct_info, source, fn {name, _parts, _fields, _range}, acc ->
      # Replace %Name{ with %__MODULE__{ — use a regex that matches the struct name
      pattern = "%#{name}{"
      String.replace(acc, pattern, "%__MODULE__{")
    end)
  end

  # Find all `defp struct Name do %{...} end` patterns and extract field names.
  defp find_python_structs(ast) do
    {_, structs} =
      Macro.prewalk(ast, [], fn
        {:defp, _meta, [{:struct, _, [{:__aliases__, _, name_parts}]}, body]} = node, acc ->
          case extract_fields(body) do
            [_ | _] = fields ->
              name = name_string(name_parts)
              range = Sourceror.get_range(node)
              {node, [{name, name_parts, fields, range} | acc]}

            [] ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    structs
  end

  defp name_string(parts) do
    parts |> Enum.map_join(".", &Atom.to_string/1)
  end

  # Extract field atoms from the map literal inside a do block.
  defp extract_fields([{{:__block__, _, [:do]}, {:%{}, _, entries}}]) do
    Enum.flat_map(entries, fn
      {{:__block__, meta, [field]}, _type} when is_atom(field) and is_list(meta) ->
        if Keyword.get(meta, :format) == :keyword, do: [field], else: []

      _ ->
        []
    end)
  end

  defp extract_fields(_), do: []

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
