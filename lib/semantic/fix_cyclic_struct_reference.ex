defmodule Credence.Semantic.FixCyclicStructReference do
  @moduledoc """
  Fixes compile errors caused by referencing a struct defined later in the same file.

  When a module uses `%ModuleName{}` struct syntax before the module that defines
  the struct with `defstruct`, the compiler emits:

      "ModuleName.__struct__/1 is undefined, cannot expand struct ModuleName"

  The fix reorders top-level `defmodule` blocks so that modules defining structs
  appear before modules that reference them. It only rewrites when the file is
  exactly a sequence of alias-named top-level `defmodule`s (no stray comments or
  other code between them, which a reorder would drop) and the reordered result
  actually compiles — otherwise the source is returned unchanged.

  ## Bad

      defmodule CsrE2eFactory do
        def build, do: %CsrE2eUser{name: "test"}
      end

      defmodule CsrE2eUser do
        defstruct [:name]
      end

  ## Good

      defmodule CsrE2eUser do
        defstruct [:name]
      end

      defmodule CsrE2eFactory do
        def build, do: %CsrE2eUser{name: "test"}
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue
  alias Credence.RuleHelpers

  @match_msg "__struct__/1 is undefined"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_cyclic_struct_reference,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         [_ | _] = modules <- extract_top_level_modules(ast, source) do
      reorder_if_needed(modules, source)
    else
      _ -> source
    end
  end

  defp extract_top_level_modules({:__block__, _, nodes}, source) do
    if Enum.all?(nodes, &named_defmodule?/1) do
      lines = String.split(source, "\n")

      modules =
        Enum.map(nodes, fn {:defmodule, _meta, [{:__aliases__, _, name_parts}, body]} = node ->
          name = name_parts |> Enum.map_join(".", &Atom.to_string/1)
          range = Sourceror.get_range(node)

          start_line = range.start[:line]
          end_line = range.end[:line]
          source_text = lines |> Enum.slice((start_line - 1)..(end_line - 1)) |> Enum.join("\n")

          %{
            name: name,
            source: source_text,
            start_line: start_line,
            end_line: end_line,
            defines_struct: has_defstruct?(body),
            refs: struct_refs(node)
          }
        end)

      if covers_all_content?(modules, lines), do: modules, else: []
    else
      []
    end
  end

  defp extract_top_level_modules(_, _), do: []

  defp named_defmodule?({:defmodule, _, [{:__aliases__, _, parts}, _body]}) when is_list(parts) do
    Enum.all?(parts, &is_atom/1)
  end

  defp named_defmodule?(_), do: false

  # Reordering emits only the module ranges; any non-blank line outside them
  # (e.g. a comment between modules) would be silently dropped, so bail.
  defp covers_all_content?(modules, lines) do
    covered =
      Enum.reduce(modules, MapSet.new(), fn m, acc ->
        Enum.reduce(m.start_line..m.end_line, acc, &MapSet.put(&2, &1))
      end)

    lines
    |> Enum.with_index(1)
    |> Enum.all?(fn {text, idx} ->
      String.trim(text) == "" or MapSet.member?(covered, idx)
    end)
  end

  defp has_defstruct?(body) do
    {_, found} =
      Macro.prewalk(body, false, fn
        {:defstruct, _, _} = n, _ -> {n, true}
        n, acc -> {n, acc}
      end)

    found
  end

  defp struct_refs(node) do
    {_, refs} =
      Macro.prewalk(node, [], fn
        {:%, _, [{:__aliases__, _, parts}, {:%{}, _, _}]} = n, acc ->
          name = parts |> Enum.map_join(".", &Atom.to_string/1)
          {n, [name | acc]}

        n, acc ->
          {n, acc}
      end)

    Enum.uniq(refs)
  end

  defp reorder_if_needed(modules, source) do
    struct_definers = modules |> Enum.filter(& &1.defines_struct) |> MapSet.new(& &1.name)

    deps =
      Map.new(modules, fn m ->
        relevant =
          m.refs
          |> Enum.filter(&(&1 != m.name and MapSet.member?(struct_definers, &1)))
          |> Enum.uniq()

        {m.name, relevant}
      end)

    sorted = topo_sort(modules, deps)

    if Enum.map(sorted, & &1.name) == Enum.map(modules, & &1.name) do
      source
    else
      confirm_reorder(Enum.map_join(sorted, "\n\n", & &1.source) <> "\n", source)
    end
  end

  # Struct refs are not the only compile-order dependency (import/require/use,
  # compile-time calls); only keep the reorder if the result really compiles.
  defp confirm_reorder(reordered, source) do
    case RuleHelpers.compile_and_capture(reordered) do
      {:ok, _} -> reordered
      {:error, _} -> source
    end
  end

  defp topo_sort(modules, deps) do
    do_topo_sort(modules, deps, MapSet.new(), [])
  end

  defp do_topo_sort([], _deps, _done, acc), do: Enum.reverse(acc)

  defp do_topo_sort(remaining, deps, done, acc) do
    {ready, waiting} =
      Enum.split_with(remaining, fn m ->
        Enum.all?(deps[m.name], &MapSet.member?(done, &1))
      end)

    case ready do
      [] ->
        Enum.reverse(acc) ++ waiting

      _ ->
        new_done = Enum.reduce(ready, done, &MapSet.put(&2, &1.name))
        do_topo_sort(waiting, deps, new_done, Enum.reverse(ready) ++ acc)
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
