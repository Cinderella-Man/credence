defmodule Credence.Semantic.NoHallucinatedDefpstruct do
  @moduledoc """
  Fixes compile errors caused by LLM-hallucinated `defpstruct` macro.

  When an LLM generates `defpstruct Name do ... end` (a nonexistent
  private-struct macro), the compiler emits:

      "undefined function defpstruct/2 (there is no such import)"

  The fix:
    1. Removes the `defpstruct` wrapper and its closing `end`.
    2. Promotes `defstruct` and `@type t` from inside the wrapper to
       module level (dedented, reordered: defstruct first, then @type).
    3. Rewrites `%StructName{}` references to `%__MODULE__{}`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "undefined function defpstruct/"

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
      rule: :no_hallucinated_defpstruct,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         {_name_parts, range, inner_body} <- find_defpstruct(ast),
         true <- safe_to_fix?(inner_body) do
      lines = String.split(source, "\n")
      start_idx = range.start[:line] - 1
      end_idx = range.end[:line] - 1

      # Extract inner lines (between defpstruct do and end)
      inner_start = start_idx + 1
      inner_end = end_idx - 1

      if inner_start > inner_end do
        source
      else
        inner_lines = Enum.slice(lines, inner_start..inner_end)

        # Determine indentation
        defpstruct_line = Enum.at(lines, start_idx)
        outer_indent = find_indent(defpstruct_line)
        inner_indent = find_indent(Enum.at(inner_lines, 0) || "")

        # Dedent inner lines: strip inner_indent prefix, add outer_indent
        dedented =
          Enum.map(inner_lines, fn line ->
            if String.starts_with?(line, inner_indent) do
              outer_indent <> String.replace_prefix(line, inner_indent, "")
            else
              line
            end
          end)

        # Split into defstruct and @type groups
        {defstruct_lines, type_lines} = split_body(dedented)

        # Build replacement block: defstruct, blank, @type
        replacement =
          case {defstruct_lines, type_lines} do
            {_, []} -> defstruct_lines
            {[], _} -> type_lines
            {_, _} -> defstruct_lines ++ [""] ++ type_lines
          end

        # Replace the defpstruct block in the source
        before = Enum.slice(lines, 0..(start_idx - 1))
        after_ = Enum.slice(lines, (end_idx + 1)..-1//1)
        result_lines = before ++ replacement ++ after_
        result = Enum.join(result_lines, "\n")

        # Replace %StructName{ with %__MODULE__{
        replace_struct_refs(result, ast)
      end
    else
      _ -> source
    end
  end

  # Find the defpstruct call in the AST and return {name_parts, range, inner_body}.
  defp find_defpstruct(ast) do
    Macro.prewalk(ast, nil, fn
      {:defpstruct, _meta, [{:__aliases__, _, name_parts}, body]} = node, nil ->
        case extract_do_body(body) do
          {:ok, inner} ->
            range = Sourceror.get_range(node)
            {node, {name_parts, range, inner}}

          _ ->
            {node, nil}
        end

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp extract_do_body([{{:__block__, _, [:do]}, body}]), do: {:ok, body}
  defp extract_do_body(_), do: :error

  # The line-based transform below only reproduces one shape faithfully: a
  # single-line `defstruct` optionally preceded by a single `@type`, with
  # nothing else in the block. Any other shape (multi-line defstruct, other
  # attributes such as `@enforce_keys`/`@derive`, a `@type` *after* the
  # defstruct, extra statements) would be silently dropped, reordered, or
  # truncated into invalid source — so bail and leave the diagnostic unfixed.
  defp safe_to_fix?(inner_body) do
    exprs = block_exprs(inner_body)
    defstructs = Enum.filter(exprs, &defstruct_node?/1)
    types = Enum.filter(exprs, &type_attr?/1)
    others = Enum.reject(exprs, &(defstruct_node?(&1) or type_attr?(&1)))

    with [defstruct_node] <- defstructs,
         true <- others == [],
         true <- length(types) <= 1,
         true <- single_line?(defstruct_node),
         true <- type_before_defstruct?(exprs) do
      true
    else
      _ -> false
    end
  end

  defp block_exprs({:__block__, _, exprs}) when is_list(exprs), do: exprs
  defp block_exprs(nil), do: []
  defp block_exprs(expr), do: [expr]

  defp defstruct_node?({:defstruct, _, _}), do: true
  defp defstruct_node?(_), do: false

  defp type_attr?({:@, _, [{:type, _, _}]}), do: true
  defp type_attr?(_), do: false

  defp single_line?(node) do
    case Sourceror.get_range(node) do
      %{start: start, end: end_} -> start[:line] == end_[:line]
      _ -> false
    end
  end

  # `split_body` always emits defstruct first then @type; a @type appearing
  # after the defstruct would be dropped, so only fire when it precedes it.
  defp type_before_defstruct?(exprs) do
    ti = Enum.find_index(exprs, &type_attr?/1)
    di = Enum.find_index(exprs, &defstruct_node?/1)
    is_nil(ti) or ti < di
  end

  # Split dedented inner lines into defstruct and @type groups.
  # Returns {defstruct_lines, type_lines} with defstruct first.
  defp split_body(lines) do
    # Find the defstruct line index
    defstruct_idx =
      Enum.find_index(lines, fn line ->
        String.starts_with?(String.trim(line), "defstruct")
      end)

    case defstruct_idx do
      nil ->
        # No defstruct found — treat all as @type
        {[], lines}

      0 ->
        # defstruct is the first line — no @type before it
        {[Enum.at(lines, 0)], []}

      idx ->
        # Everything before defstruct_idx is the @type block
        type_lines =
          Enum.slice(lines, 0..(idx - 1))
          |> Enum.reverse()
          |> Enum.drop_while(fn line -> String.trim(line) == "" end)
          |> Enum.reverse()

        # The defstruct line itself
        defstruct_line = Enum.at(lines, idx)

        {[defstruct_line], type_lines}
    end
  end

  # Replace %StructName{ with %__MODULE__{ in source text.
  defp replace_struct_refs(source, ast) do
    case find_defpstruct(ast) do
      {name_parts, _range, _inner} ->
        name = Enum.map_join(name_parts, ".", &Atom.to_string/1)
        pattern = "%#{name}{"
        String.replace(source, pattern, "%__MODULE__{")

      _ ->
        source
    end
  end

  defp find_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
