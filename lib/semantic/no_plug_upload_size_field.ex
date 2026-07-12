defmodule Credence.Semantic.NoPlugUploadSizeField do
  @moduledoc """
  Fixes compile errors caused by LLMs hallucinating a `:size` field on `%Plug.Upload{}`.

  `Plug.Upload` only has `:path`, `:filename`, and `:content_type` — there is no
  `:size` field.  LLMs routinely hallucinate one, producing:

      "unknown key :size for struct Plug.Upload"

  The fix removes the nonexistent key from the pattern match.  When the bound
  variable is used downstream as a direct function-call argument (e.g.
  `validate_csv(path, size)`), the argument is removed from the call site and
  from the callee's parameter list.  When the variable is used in a non-call
  context (e.g. in an expression), a `File.stat!(path).size` computation is
  inserted to preserve runtime behaviour.

  Distinct from `NoHallucinatedStructFieldInPattern` which targets generic
  "key :X not found" errors on LLM-created structs; this rule targets the
  specific diagnostic emitted for the real stdlib struct `Plug.Upload`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "unknown key :size for struct Plug.Upload"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    msg == @match_msg
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_plug_upload_size_field,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      entries = find_struct_entries(ast)

      source
      |> fix_entries(entries)
      |> fix_callee_defs(entries, ast)
    else
      _ -> source
    end
  end

  # Phase 1: remove `:size` from the pattern and call sites.
  defp fix_entries(source, entries) do
    Enum.reduce(entries, source, fn entry, src ->
      src
      |> remove_entry(entry)
      |> remove_from_call_sites(entry)
    end)
  end

  # Phase 2: for each call site where the variable was removed, find the callee
  # function definition and remove the variable from its parameter list too.
  # If the callee uses the variable internally, insert File.stat! in its body.
  defp fix_callee_defs(source, entries, ast) do
    callee_names =
      entries
      |> Enum.flat_map(fn %{var_name: var_name, call_info: info} ->
        for {fun_name, arity, _line} <- info, do: {{fun_name, arity}, var_name}
      end)
      |> Enum.uniq()

    Enum.reduce(callee_names, source, fn {fun_arity, var_name}, src ->
      fix_callee_def(src, fun_arity, var_name, ast)
    end)
  end

  # --- AST traversal ---

  defp find_struct_entries(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {:def, _, _} = node, acc ->
          entries = find_entries_in_def(node)
          {node, acc ++ entries}

        {:defp, _, _} = node, acc ->
          entries = find_entries_in_def(node)
          {node, acc ++ entries}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp find_entries_in_def({_def_type, _meta, [head, body_kw]}) do
    body = extract_body(body_kw)
    entries = collect_struct_entries(head)

    Enum.map(entries, fn {var_name, entry_meta} ->
      var_used = body != nil and var_used?(body, var_name)

      call_info =
        if var_used, do: find_call_info(body, var_name), else: []

      %{
        var_name: var_name,
        var_used: var_used,
        call_info: call_info,
        entry_range: Sourceror.get_range(entry_meta)
      }
    end)
  end

  defp collect_struct_entries(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {:%, _meta, [{:__aliases__, _, [:Plug, :Upload]}, {:%{}, _, entries}]} = node, acc ->
          found =
            for {key_ast, val_ast} <- entries,
                entry_key(key_ast) == :size,
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

  # --- Phase 1 helpers ---

  defp remove_entry(source, %{entry_range: range}) do
    lines = String.split(source, "\n")

    if range do
      idx = (range.start[:line] || 1) - 1

      if idx >= 0 and idx < length(lines) do
        updated = remove_size_from_line(Enum.at(lines, idx))

        if updated == "" do
          List.delete_at(lines, idx)
        else
          List.replace_at(lines, idx, updated)
        end
      else
        lines
      end
    else
      lines
    end
    |> Enum.join("\n")
  end

  defp remove_size_from_line(line) do
    cond do
      Regex.match?(~r/,\s*size:\s+\w+/, line) ->
        Regex.replace(~r/,\s*size:\s+\w+/, line, "")

      Regex.match?(~r/\bsize:\s+\w+,?\s*/, line) ->
        Regex.replace(~r/\bsize:\s+\w+,?\s*/, line, "")

      true ->
        line
    end
  end

  defp remove_from_call_sites(source, %{var_name: var_name, call_info: call_info})
       when call_info != [] do
    call_lines = MapSet.new(call_info, &elem(&1, 2))
    lines = String.split(source, "\n")

    updated =
      Enum.with_index(lines, fn line, idx ->
        if MapSet.member?(call_lines, idx + 1) do
          remove_var_from_call(line, var_name)
        else
          line
        end
      end)

    Enum.join(updated, "\n")
  end

  defp remove_from_call_sites(source, _entry), do: source

  defp remove_var_from_call(line, var_name) do
    var_str = Regex.escape(Atom.to_string(var_name))

    line
    |> String.replace(~r/,\s*\b#{var_str}\b/, "")
    |> String.replace(~r/\b#{var_str}\b,\s*/, "")
  end

  # --- Phase 2 helpers: fix callee definitions ---

  defp fix_callee_def(source, fun_arity, var_name, ast) do
    case find_callee_def_node(ast, fun_arity, var_name) do
      nil ->
        source

      {_def_type, meta, [_head, body_kw]} ->
        callee_body = extract_body(body_kw)
        var_used_in_callee = callee_body != nil and var_used?(callee_body, var_name)

        if var_used_in_callee do
          # Callee uses the variable — insert File.stat! computation
          source
          |> remove_var_from_defp_params(meta, var_name)
          |> insert_file_stat_in_callee(meta, var_name)
        else
          # Callee does not use the variable — just remove from params
          remove_var_from_defp_params(source, meta, var_name)
        end
    end
  end

  defp find_callee_def_node(ast, {fun_name, arity}, var_name) do
    {_ast, result} =
      Macro.prewalk(ast, nil, fn
        {:def, _, _} = node, nil ->
          if callee_match?(node, fun_name, arity, var_name), do: {node, node}, else: {node, nil}

        {:defp, _, _} = node, nil ->
          if callee_match?(node, fun_name, arity, var_name), do: {node, node}, else: {node, nil}

        node, acc ->
          {node, acc}
      end)

    result
  end

  defp callee_match?({def_type, _meta, [{fun, _, args} | _]}, fun_name, arity, var_name)
       when def_type in [:def, :defp] and is_atom(fun) and is_list(args) do
    fun == fun_name and length(args) == arity and
      Enum.any?(args, fn
        {^var_name, _, nil} -> true
        {^var_name, _, _} -> true
        _ -> false
      end)
  end

  defp callee_match?(_, _, _, _), do: false

  defp remove_var_from_defp_params(source, def_meta, var_name) do
    def_line = Keyword.get(def_meta, :line)
    lines = String.split(source, "\n")

    if def_line do
      idx = def_line - 1

      if idx >= 0 and idx < length(lines) do
        line = Enum.at(lines, idx)
        updated = remove_var_from_call(line, var_name)
        List.replace_at(lines, idx, updated) |> Enum.join("\n")
      else
        source
      end
    else
      source
    end
  end

  defp insert_file_stat_in_callee(source, def_meta, var_name) do
    def_line = Keyword.get(def_meta, :line) || 1
    lines = String.split(source, "\n")
    do_idx = find_do_line(lines, def_line - 1)

    if do_idx do
      indent = get_indent(Enum.at(lines, do_idx))
      new_line = "#{indent}  #{var_name} = File.stat!(path).size"
      {before, rest} = Enum.split(lines, do_idx + 1)
      Enum.join(before ++ [new_line] ++ rest, "\n")
    else
      source
    end
  end

  defp find_do_line(lines, start_idx) do
    lines
    |> Enum.drop(start_idx)
    |> Enum.find_index(fn line ->
      String.contains?(line, " do") or String.ends_with?(line, " do")
    end)
    |> case do
      nil -> nil
      idx -> start_idx + idx
    end
  end

  # --- Call info collection ---

  defp find_call_info(body, var_name) do
    {_ast, acc} =
      Macro.prewalk(body, [], fn
        {fun_name, _, args} = node, acc when is_atom(fun_name) and is_list(args) ->
          if fun_name not in [:__block__, :def, :defp, :defmodule] and var_in_args?(args, var_name) do
            meta = elem(node, 1)
            line = Keyword.get(meta, :line)
            if line, do: {node, [{fun_name, length(args), line} | acc]}, else: {node, acc}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp var_in_args?(args, var_name) do
    Enum.any?(args, fn
      {^var_name, _meta, nil} -> true
      _ -> false
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
