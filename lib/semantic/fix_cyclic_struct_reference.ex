defmodule Credence.Semantic.FixCyclicStructReference do
  @moduledoc """
  Fixes compile errors caused by referencing a struct defined later in the same file.

  When a module uses `%ModuleName{}` struct syntax before the module that defines
  the struct with `defstruct`, the compiler emits:

      "ModuleName.__struct__/1 is undefined, cannot expand struct ModuleName"

  The fix reorders `defmodule` blocks so that modules defining structs appear before
  modules that reference them. It only rewrites when the statements it is reordering
  cover every non-blank line of their scope (a stray comment between them would be
  dropped by a reorder) and the reordered result actually compiles — otherwise the
  source is returned unchanged.

  ## Two scopes: top-level siblings, and nested modules

  The original rule handled only the first. A struct defined in a NESTED module and
  used earlier in the same body raises the same diagnostic, and this rule reported it
  and then declined — `analyze/1` returned `:fix_cyclic_struct_reference` while
  `fix/2` returned `:no_op`, which is the report-without-fix shape this project does
  not ship. docs/18 had already asked for the extension, as
  `fix_undefined_struct_in_pattern`'s redirect.

  Both spellings of the nested reference raise it, and hoisting repairs both
  (executed):

      defmodule O do             #  O.NUser.__struct__/1 is undefined
        def build, do: %U{}      #  U.__struct__/1 is undefined
        defmodule U, do: defstruct([:name])
      end

  The bare-alias case is worth a note, because the hoist changes which module the
  reference NAMES: before it, `%U{}` means `Elixir.U`; after, the nested definition is
  in scope and it means `O.U`. That is sound here only because the rule fires on a
  diagnostic saying nothing defines the name — a file where a top-level `U` really
  exists compiles, emits no diagnostic, and never reaches this rule.

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
    case Sourceror.parse_string(source) do
      {:ok, ast} -> reorder_top_level(ast, source) || reorder_nested(ast, source) || source
      _error -> source
    end
  end

  # `nil` rather than `source` when nothing changed, so `fix/2` can fall through to the
  # nested scope instead of stopping at the first attempt that declines.
  defp reorder_top_level(ast, source) do
    case extract_top_level_modules(ast, source) do
      [_ | _] = modules ->
        case reorder_if_needed(modules, source) do
          ^source -> nil
          reordered -> reordered
        end

      [] ->
        nil
    end
  end

  # The nested scope. One outer module's body is reordered at a time — the first whose
  # body both needs it and can be rebuilt safely — and the compile gate then judges the
  # whole file, exactly as for the top-level scope.
  defp reorder_nested(ast, source) do
    lines = String.split(source, "\n")

    ast
    |> outer_modules_with_struct_nested()
    |> Enum.find_value(fn {outer_name, body_nodes} ->
      with [_, _ | _] = statements <- body_statements(body_nodes, lines),
           true <- covers_all_content_between?(statements, lines),
           reordered when is_binary(reordered) <-
             reorder_body(statements, outer_name, lines, source) do
        reordered
      else
        _ -> nil
      end
    end)
  end

  # Every `defmodule` — at any depth — whose body block holds a nested `defmodule` that
  # defines a struct. Returns `{outer_dotted_name, body_statement_nodes}`.
  defp outer_modules_with_struct_nested(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn node, acc ->
        case node do
          {:defmodule, _, [{:__aliases__, _, parts}, [{_do, {:__block__, _, nodes}}]]}
          when is_list(parts) and is_list(nodes) ->
            if Enum.any?(nodes, &struct_defining_module?/1) do
              {node, acc ++ [{Enum.map_join(parts, ".", &Atom.to_string/1), nodes}]}
            else
              {node, acc}
            end

          _ ->
            {node, acc}
        end
      end)

    found
  end

  defp struct_defining_module?({:defmodule, _, [{:__aliases__, _, parts}, body]})
       when is_list(parts),
       do: has_defstruct?(body)

  defp struct_defining_module?(_node), do: false

  # One record per body statement, in the same shape `reorder_if_needed/2` already
  # consumes. A statement that is not a struct-defining module still needs a unique
  # `name` and its own `refs`, or the topological sort cannot keep it in place relative
  # to the module being hoisted.
  defp body_statements(nodes, lines) do
    nodes
    |> Enum.with_index()
    |> Enum.map(fn {node, index} ->
      case Sourceror.get_range(node) do
        %{start: [line: start_line, column: _], end: [line: end_line, column: _]} ->
          %{
            name: statement_name(node, index),
            source: lines |> Enum.slice((start_line - 1)..(end_line - 1)) |> Enum.join("\n"),
            start_line: start_line,
            end_line: end_line,
            defines_struct: struct_defining_module?(node),
            refs: struct_refs(node)
          }

        _ ->
          nil
      end
    end)
    |> then(fn records -> if Enum.any?(records, &is_nil/1), do: [], else: records end)
  end

  defp statement_name({:defmodule, _, [{:__aliases__, _, parts}, _body]}, _index)
       when is_list(parts),
       do: Enum.map_join(parts, ".", &Atom.to_string/1)

  # Not a module: a name nothing can reference, so it never becomes a dependency.
  defp statement_name(_node, index), do: "__statement_#{index}__"

  # The body's own version of `covers_all_content?/2`: every non-blank line between the
  # first and last statement must belong to a statement, or the rebuild would drop it.
  # A comment sitting between two statements is exactly that case.
  defp covers_all_content_between?(statements, lines) do
    first = statements |> Enum.map(& &1.start_line) |> Enum.min()
    last = statements |> Enum.map(& &1.end_line) |> Enum.max()

    covered =
      Enum.reduce(statements, MapSet.new(), fn s, acc ->
        Enum.reduce(s.start_line..s.end_line, acc, &MapSet.put(&2, &1))
      end)

    Enum.all?(first..last, fn index ->
      String.trim(Enum.at(lines, index - 1, "")) == "" or MapSet.member?(covered, index)
    end)
  end

  defp reorder_body(statements, outer_name, lines, source) do
    sorted = topo_sort(statements, body_deps(statements, outer_name))

    if Enum.map(sorted, & &1.name) == Enum.map(statements, & &1.name) do
      nil
    else
      first = statements |> Enum.map(& &1.start_line) |> Enum.min()
      last = statements |> Enum.map(& &1.end_line) |> Enum.max()

      rebuilt =
        Enum.slice(lines, 0, first - 1) ++
          [Enum.map_join(sorted, "\n\n", & &1.source)] ++
          Enum.slice(lines, last..-1//1)

      case confirm_reorder(Enum.join(rebuilt, "\n"), source) do
        ^source -> nil
        reordered -> reordered
      end
    end
  end

  # A reference matches a nested module by its own name OR by the outer-qualified one,
  # because both spellings occur and both raise the diagnostic: `%U{}` inside
  # `defmodule O` and `%O.U{}` name the same module once the definition is in scope.
  defp body_deps(statements, outer_name) do
    definers = Enum.filter(statements, & &1.defines_struct)

    Map.new(statements, fn s ->
      relevant =
        definers
        |> Enum.filter(fn d ->
          d.name != s.name and
            Enum.any?(s.refs, &(&1 == d.name or &1 == outer_name <> "." <> d.name))
        end)
        |> Enum.map(& &1.name)
        |> Enum.uniq()

      {s.name, relevant}
    end)
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
    by_name = Map.new(modules, &{&1.name, &1})

    case Enum.reduce_while(modules, {:ok, %{}, []}, fn module, {:ok, states, acc} ->
           case topo_visit(module.name, by_name, deps, states, acc) do
             :cycle -> {:halt, :cycle}
             result -> {:cont, result}
           end
         end) do
      {:ok, _states, acc} -> Enum.reverse(acc)
      :cycle -> modules
    end
  end

  defp topo_visit(name, by_name, deps, states, acc) do
    case states[name] do
      :done ->
        {:ok, states, acc}

      :visiting ->
        :cycle

      nil ->
        states = Map.put(states, name, :visiting)

        with {:ok, states, acc} <-
               Enum.reduce_while(deps[name], {:ok, states, acc}, fn dependency, result ->
                 {:ok, current_states, current_acc} = result

                 case topo_visit(dependency, by_name, deps, current_states, current_acc) do
                   :cycle -> {:halt, :cycle}
                   visited -> {:cont, visited}
                 end
               end) do
          {:ok, Map.put(states, name, :done), [Map.fetch!(by_name, name) | acc]}
        end
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
