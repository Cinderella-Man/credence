defmodule Credence.Semantic.FixHallucinatedCalendarIsoAccessor do
  @moduledoc """
  Fixes compiler warnings about hallucinated `Calendar.ISO.date/1` and
  `Calendar.ISO.time/1` accessor calls.

  LLMs frequently hallucinate `Calendar.ISO.date(dt)` and
  `Calendar.ISO.time(dt)` as ways to decompose a DateTime into date/time
  parts. These functions do not exist (`Calendar.ISO.date/4` and
  `Calendar.ISO.time/5` have different arities), producing an undefined-
  function compile error:

      "Calendar.ISO.date/1 is undefined or private"

  The fix removes the hallucinated assignment and replaces all uses of the
  bound variable's struct fields (e.g. `date.year`, `time.hour`) with
  direct field access on the original DateTime argument (`dt.year`,
  `dt.hour`).
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg_prefix "Calendar.ISO."

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg_prefix) and
      String.contains?(msg, "is undefined or private") and
      (String.contains?(msg, "Calendar.ISO.date/") or
         String.contains?(msg, "Calendar.ISO.time/"))
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_calendar_iso_accessor,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      mappings = collect_iso_mappings(ast)

      if mappings == %{} do
        source
      else
        new_ast =
          ast
          |> remove_iso_assignments(mappings)
          |> replace_field_accesses(mappings)

        Sourceror.to_string(new_ast)
      end
    else
      _ -> source
    end
  end

  # First pass: collect {var_name => arg_name} from Calendar.ISO.date/time assignments
  defp collect_iso_mappings(ast) do
    {_, acc} =
      Macro.prewalk(ast, %{}, fn
        {:=, _meta,
         [
           {var_name, _, nil},
           {{:., _, [{:__aliases__, _, [:Calendar, :ISO]}, _func]}, _, [{arg_name, _, nil}]}
         ]} = node,
        acc
        when is_atom(var_name) and is_atom(arg_name) ->
          {node, Map.put(acc, var_name, arg_name)}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  # Second pass: remove the hallucinated assignment lines from __block__ bodies
  defp remove_iso_assignments(ast, mappings) do
    Macro.postwalk(ast, fn
      {:__block__, meta, exprs} ->
        filtered =
          Enum.reject(exprs, fn
            {:=, _,
             [
               {var_name, _, nil},
               {{:., _, [{:__aliases__, _, [:Calendar, :ISO]}, _]}, _, _}
             ]} ->
              Map.has_key?(mappings, var_name)

            _ ->
              false
          end)

        {:__block__, meta, filtered}

      node ->
        node
    end)
  end

  # Third pass: replace `var.field` with `arg.field` throughout the AST
  defp replace_field_accesses(ast, mappings) do
    Macro.postwalk(ast, fn
      {{:., dot_meta, [{var_name, var_meta, nil}, field]}, call_meta, []} = node
      when is_atom(var_name) and is_atom(field) ->
        if Map.has_key?(mappings, var_name) do
          arg_name = mappings[var_name]
          {{:., dot_meta, [{arg_name, var_meta, nil}, field]}, call_meta, []}
        else
          node
        end

      node ->
        node
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
