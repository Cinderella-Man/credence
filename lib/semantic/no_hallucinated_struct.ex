defmodule Credence.Semantic.NoHallucinatedStruct do
  @moduledoc """
  Fixes compile errors caused by LLM-hallucinated struct literals.

  When an LLM generates a struct literal like `%Task.ExitError{reason: reason}`
  for a module that doesn't define a struct (or doesn't exist at all), the
  compiler emits:

      "Task.ExitError.__struct__/1 is undefined, cannot expand struct Task.ExitError"

  The fix rewrites the non-existent struct literal into a plain tuple so the
  code compiles:

      %Task.ExitError{reason: reason}  →  {Task.ExitError, reason}

  This rule handles cases where `FixCyclicStructReference` cannot fix the issue
  (i.e., the struct module is not defined anywhere in the source file).
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "__struct__/1 is undefined"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_struct,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      defined_structs = find_defined_structs(ast)

      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:%, _, [{:__aliases__, _, parts}, {:%{}, _, _entries}]} = node, acc ->
            module_name = Module.concat(parts)

            if MapSet.member?(defined_structs, module_name) do
              {node, acc}
            else
              {struct_to_tuple(node), true}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Collect every module name that defines a struct via defstruct.
  defp find_defined_structs(ast) do
    {_, structs} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:defmodule, _, [{:__aliases__, _, parts}, body]} = node, acc ->
          module_name = Module.concat(parts)

          if has_defstruct?(body) do
            {node, MapSet.put(acc, module_name)}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    structs
  end

  defp has_defstruct?(body) do
    {_, found} =
      Macro.prewalk(body, false, fn
        {:defstruct, _, _} = n, _ -> {n, true}
        n, acc -> {n, acc}
      end)

    found
  end

  # %Module{key: val} → {Module, val}  (or {Module, v1, v2, …} for multi-field)
  defp struct_to_tuple({:%, _meta, [alias_ast, {:%{}, _, entries}]}) do
    values =
      Enum.map(entries, fn
        {{:__block__, _, [_key]}, val} -> val
        {_key, val} -> val
      end)

    case [alias_ast | values] do
      [a, b] -> {:__block__, [], [{a, b}]}
      els -> {:__block__, [], [{:{}, [], els}]}
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
