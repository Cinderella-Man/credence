defmodule Credence.Semantic.NoUndefinedModuleInRescue do
  @moduledoc """
  Quotes an undefined exception module in a multi-module `rescue` list.

  LLMs commonly invent exception modules (`NotImplementedError`,
  `BadStructError`, …) and list them alongside real ones in a rescue clause.
  The compiler emits a warning, which fails the build under
  `--warnings-as-errors`:

      struct NotImplementedError is undefined (module NotImplementedError is
      not available or is yet to be defined)

  Only one shape is rewritten — a `rescue` clause head `e in [A, B, ...]` whose
  list names the flagged module **and at least one surviving module**:

      rescue e in [NotImplementedError, RuntimeError] -> ...       # warns
      rescue e in [:"Elixir.NotImplementedError", RuntimeError] -> ... # fixed

  A literal module atom avoids the compile-time struct check while retaining
  the runtime match if the exception module is loaded before the function runs.
  See `fix/2` for the shapes that are deliberately left alone.

  ## Bad

      defmodule MNUMIR do
        def run do
          try do
            :ok
          rescue
            e in [NotImplementedError, RuntimeError] -> e
          end
        end
      end

  ## Good

      defmodule MNUMIR do
        def run do
          try do
            :ok
          rescue
            e in [:"Elixir.NotImplementedError", RuntimeError] -> e
          end
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "struct "
  @match_infix "is undefined (module "
  @match_suffix " is not available or is yet to be defined)"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @match_prefix) and
      String.contains?(msg, @match_infix) and
      String.contains?(msg, @match_suffix)
  end

  def match?(_), do: false

  @doc """
  Only report what `fix/2` will actually repair.

  The diagnostic names an undefined module but says nothing about the shape it
  was written in — the same warning covers a struct pattern, a one-module
  rescue list and a bare `e in Undefined` head, none of which have a safe fix.
  The narrowing is therefore source-aware and lives in `fix/2`; the check
  simply defers to it.
  """
  def should_report?(diagnostic, source), do: fix(source, diagnostic) != source

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_undefined_module_in_rescue,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @doc """
  Replaces the flagged module with its literal module atom in every
  `rescue e in [...]` head that names it.

  The diagnostic's position is deliberately *not* used to scope the rewrite:
  the compiler reports one diagnostic per undefined module per module body, so
  a position-scoped fix would leave sibling occurrences behind, still warning,
  and the semantic phase handles warnings in one terminal pass with no retry.
  Scoping is structural instead, and these shapes are refused outright:

    * **`in` outside a `rescue` clause head.** `if x in [Undefined]` is
      `Enum.member?/2`, not a rescue struct match, and is outside this rule's
      contract.
    * **A one-module list** — `rescue e in [Undefined]` — and **a non-list
      head** — `rescue e in Undefined`. This rule deliberately retains its
      narrow multi-module-list contract.
    * **A file that aliases the flagged name at all.** The compiler reports the
      *expanded* module, so a bare flagged name means it was unaliased at that
      point — but a block-scoped `alias MyApp.Undefined` can make the very same
      spelling resolve to a real struct elsewhere in the file. Rather than
      track lexical alias scopes, such a file is left untouched.

  A `rescue e in [...] when guard` head is also left alone; it is rare enough
  not to be worth a second rewrite path.
  """
  @impl true
  def fix(source, diagnostic) do
    with segments when segments != [] <- module_segments(diagnostic.message),
         {:ok, ast} <- Sourceror.parse_string(source),
         false <- aliased?(ast, List.last(segments)) do
      {_ast, edits} =
        Macro.prewalk(ast, [], fn
          {{:__block__, _, [:rescue]} = key, clauses}, acc when is_list(clauses) ->
            clause_edits = Enum.flat_map(clauses, &module_edits(&1, segments))
            {{key, clauses}, clause_edits ++ List.wrap(acc)}

          node, acc ->
            {node, acc}
        end)

      apply_edits(source, edits)
    else
      _ -> source
    end
  end

  # A rescue clause is `{:->, meta, [[head], body]}`. Only a bare-variable head
  # over a literal list is rewritten, and only when the flagged module is in
  # that list alongside another module.
  defp module_edits(
         {:->, _, [[{:in, _, [_var, {:__block__, _, [modules]}]}], _body]},
         segments
       )
       when is_list(modules) and length(modules) > 1 do
    Enum.flat_map(modules, fn
      {:__aliases__, meta, alias_segments}
      when alias_segments == segments or alias_segments == [Elixir | segments] ->
        spelling = Enum.map_join(alias_segments, ".", &Atom.to_string/1)
        replacement = ~s(:"Elixir.#{Enum.map_join(segments, ".", &Atom.to_string/1)}")
        [{meta[:line], meta[:column], spelling, replacement}]

      _ ->
        []
    end)
  end

  defp module_edits(_clause, _segments), do: []

  defp apply_edits(source, []), do: source

  defp apply_edits(source, edits) do
    by_line = Enum.group_by(edits, &elem(&1, 0))

    source
    |> String.split("\n", trim: false)
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {line, line_no} ->
      by_line
      |> Map.get(line_no, [])
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.reduce(line, fn {_line, column, spelling, replacement}, current ->
        {:ok, offset} = Credence.SourceMask.byte_offset(current, 1, column)
        <<before::binary-size(^offset), tail::binary>> = current

        before <>
          Credence.SourceMask.replace_code(tail, tail, spelling, replacement, global: false)
      end)
    end)
  end

  # True when the file has any `alias`/`require`/`import` that mentions the
  # flagged name, covering `alias A.Undefined`, `alias A.B, as: Undefined` and
  # `alias A.{Undefined, C}` in one conservative sweep. Over-triggering only
  # costs us a fix we decline to make; under-triggering would delete a module
  # from a rescue list that really does catch something.
  defp aliased?(ast, name) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {directive, _, args} = node, acc
        when directive in [:alias, :require, :import] and is_list(args) ->
          {node, acc or mentions?(args, name)}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp mentions?({:__aliases__, _, segments}, name) when is_list(segments), do: name in segments
  defp mentions?({:__block__, _, [value]}, name), do: mentions?(value, name)
  defp mentions?({left, _, right}, name), do: mentions?(left, name) or mentions?(right, name)
  defp mentions?({left, right}, name), do: mentions?(left, name) or mentions?(right, name)
  defp mentions?(list, name) when is_list(list), do: Enum.any?(list, &mentions?(&1, name))
  defp mentions?(name, name) when is_atom(name), do: true
  defp mentions?(_other, _name), do: false

  # "struct MyApp.Undefined is undefined (module ..." -> [:MyApp, :Undefined]
  defp module_segments(msg) do
    case Regex.run(~r/^struct ([A-Z]\S*) is undefined \(module /, msg) do
      [_, mod] -> mod |> String.split(".") |> Enum.map(&String.to_atom/1)
      _ -> []
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
