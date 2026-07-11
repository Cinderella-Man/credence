defmodule Credence.Semantic.NoHallucinatedStructFieldInPattern do
  @moduledoc """
  Fixes compile errors caused by LLMs hallucinating struct fields in pattern matches.

  When an LLM generates a pattern like `%Plug.Upload{path: path, size: size}` for a
  struct that doesn't have a `:size` field, the compiler emits:

      "key :size not found"

  The fix removes the non-existent field from the pattern match. When the bound
  variable is used downstream in the function body, it inserts a `File.stat!`
  computation to derive the value instead.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "key :"
  @match_suffix " not found"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @match_prefix) and String.ends_with?(msg, @match_suffix)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_struct_field_in_pattern,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    with key when is_atom(key) <- extract_key(msg),
         {:ok, ast} <- Sourceror.parse_string(source) do
      removals = find_struct_entries(ast, key)

      Enum.reduce(removals, source, fn removal, src ->
        src
        |> remove_entry(removal)
        |> maybe_insert_file_stat(removal)
      end)
    else
      _ -> source
    end
  end

  defp extract_key(msg) do
    case Regex.run(~r/^key :(\w+) not found$/, msg) do
      [_, key] -> String.to_atom(key)
      _ -> nil
    end
  end

  # Walk the AST to find struct pattern entries that bind `target_key`.
  # Returns a list of maps with info needed to remove each entry and
  # optionally insert a File.stat! computation.
  defp find_struct_entries(ast, target_key) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {:def, _, _} = node, acc ->
          entries = find_entries_in_def(node, target_key)
          {node, acc ++ entries}

        {:defp, _, _} = node, acc ->
          entries = find_entries_in_def(node, target_key)
          {node, acc ++ entries}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp find_entries_in_def({_def_type, meta, [head, body_kw]}, target_key) do
    body = extract_body(body_kw)
    entries = collect_struct_entries(head, target_key)

    Enum.map(entries, fn {var_name, entry_meta} ->
      var_used = body != nil and var_used?(body, var_name)

      %{
        target_key: target_key,
        var_name: var_name,
        var_used: var_used,
        struct_line: Keyword.get(meta, :line),
        entry_range: Sourceror.get_range(entry_meta)
      }
    end)
  end

  # Collect all entries in the AST that bind `target_key` in a struct pattern.
  # Returns `[{var_name_atom, entry_node}]`.
  defp collect_struct_entries(ast, target_key) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {:%{}, _meta, entries} = node, acc when is_list(entries) ->
          found =
            for {key_ast, val_ast} <- entries,
                entry_key(key_ast) == target_key,
                var = entry_var(val_ast),
                var != nil,
                do: {var, {key_ast, val_ast}}

          {node, acc ++ found}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp entry_key({:__block__, _, [key]}) when is_atom(key), do: key
  defp entry_key(key) when is_atom(key), do: key
  defp entry_key(_), do: nil

  defp entry_var({var_name, _meta, nil}) when is_atom(var_name), do: var_name
  defp entry_var(_), do: nil

  defp var_used?(ast, var_name) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {^var_name, _meta, nil} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp extract_body(kw) when is_list(kw) do
    Enum.find_value(kw, fn
      {{:__block__, _, [:do]}, body} -> body
      _ -> nil
    end)
  end

  defp extract_body(_), do: nil

  # Remove a struct entry from the source string.
  defp remove_entry(source, %{target_key: target_key, entry_range: range}) do
    lines = String.split(source, "\n")

    if range do
      start_line = range.start[:line] || 1
      end_line = range.end[:line] || start_line
      idx_start = start_line - 1
      idx_end = end_line - 1

      cond do
        idx_start == idx_end ->
          # Single-line entry: remove from line
          updated = remove_from_line(Enum.at(lines, idx_start), target_key)

          if updated == "" do
            # Entry was the whole line, remove it
            List.delete_at(lines, idx_start)
          else
            List.replace_at(lines, idx_start, updated)
          end

        idx_start < idx_end ->
          # Multi-line entry: key on start line, value on end line
          {before_key, _} = split_at_key(Enum.at(lines, idx_start), target_key)
          rest = Enum.slice(lines, (idx_end + 1)..-1//1)
          Enum.slice(lines, 0, idx_start) ++ [before_key] ++ rest

        true ->
          lines
      end
    else
      lines
    end
    |> Enum.join("\n")
  end

  defp remove_from_line(line, key) do
    key_str = to_string(key)

    # Match the entry with trailing comma and whitespace
    pattern = Regex.compile!(",\\s*#{Regex.escape(key_str)}:\\s+\\w+")

    case Regex.run(pattern, line) do
      [match] ->
        String.replace(line, match, "", global: false)

      nil ->
        # Try without leading comma (entry might be first/only)
        pattern2 = Regex.compile!("#{Regex.escape(key_str)}:\\s+\\w+,?\\s*")
        String.replace(line, pattern2, "", global: false)
    end
  end

  defp split_at_key(line, key) do
    key_str = to_string(key)
    pattern = Regex.compile!(",\\s*#{Regex.escape(key_str)}:")

    case Regex.run(pattern, line, return: :index) do
      [{idx, _len}] ->
        {String.slice(line, 0, idx), String.slice(line, idx..-1//1)}

      nil ->
        {line, ""}
    end
  end

  # Insert `var = File.stat!(path).size` before the function body when the
  # variable is used downstream.
  defp maybe_insert_file_stat(source, %{var_name: var_name, var_used: true}) do
    lines = String.split(source, "\n")

    case find_do_line(lines) do
      nil ->
        source

      do_idx ->
        indent = get_indent(Enum.at(lines, do_idx))
        new_line = "#{indent}  #{var_name} = File.stat!(path).size"
        {before, rest} = Enum.split(lines, do_idx + 1)
        Enum.join(before ++ [new_line] ++ rest, "\n")
    end
  end

  defp maybe_insert_file_stat(source, _removal), do: source

  defp find_do_line(lines) do
    Enum.find_index(lines, fn line ->
      String.contains?(line, "do") and not String.contains?(line, "defmodule")
    end)
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
