defmodule Credence.Semantic.NoUndefinedModuleInRescue do
  @moduledoc """
  Drops a hallucinated exception module from a multi-module `rescue` list.

  LLMs commonly invent exception modules (`NotImplementedError`,
  `BadStructError`, …) and list them alongside real ones in a rescue clause.
  The compiler emits a warning, which fails the build under
  `--warnings-as-errors`:

      struct NotImplementedError is undefined (module NotImplementedError is
      not available or is yet to be defined)

  Only one shape is rewritten — a `rescue` clause head `e in [A, B, ...]` whose
  list names the flagged module **and at least one surviving module**:

      rescue e in [NotImplementedError, RuntimeError] -> ...   # warns
      rescue e in [RuntimeError] -> ...                        # fixed

  That rewrite is behaviour-preserving: the module does not exist, so no raised
  exception can ever have it as its struct, and the clause matches exactly the
  same set of exceptions before and after. See `fix/2` for the shapes that are
  deliberately left alone.

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
            e in [RuntimeError] -> e
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
  Removes the flagged module from every `rescue e in [...]` head that names it.

  The diagnostic's position is deliberately *not* used to scope the rewrite:
  the compiler reports one diagnostic per undefined module per module body, so
  a position-scoped fix would leave sibling occurrences behind, still warning,
  and the semantic phase handles warnings in one terminal pass with no retry.
  Scoping is structural instead, and four shapes are refused outright:

    * **`in` outside a `rescue` clause head.** `if x in [Undefined]` is
      `Enum.member?/2`, not a struct match; dropping the module there would
      turn a membership test into something else entirely (and emptying the
      list would turn it into a bare truthiness test on `x`).
    * **A list that would be left empty** — `rescue e in [Undefined]`. The
      clause currently matches *nothing* (the struct cannot exist, so the
      exception propagates); rewriting it to a catch-all `rescue e` would
      swallow every exception, shadow the clauses after it, and change the
      answer for every input that raises. What the author meant instead is not
      recoverable from the diagnostic.
    * **A non-list head** — `rescue e in Undefined` — for the same reason:
      there is nothing to drop the module *from*.
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
      {rewritten, changed?} =
        Macro.prewalk(ast, false, fn
          {{:__block__, _, [:rescue]} = key, clauses}, acc when is_list(clauses) ->
            {fixed, touched?} = Enum.map_reduce(clauses, acc, &drop_module(&1, &2, segments))
            {{key, fixed}, touched?}

          node, acc ->
            {node, acc}
        end)

      # Round-tripping through Sourceror reflows the whole file, so only emit a
      # new string when a clause actually changed. A rule that "fixes" nothing
      # must hand back the source byte-for-byte, or `should_report?/2` cannot
      # tell a repair from a reformat.
      if changed?, do: Sourceror.to_string(rewritten), else: source
    else
      _ -> source
    end
  end

  # A rescue clause is `{:->, meta, [[head], body]}`. Only a bare-variable head
  # over a literal list is rewritten, and only when the flagged module is in
  # that list *and* another module survives it.
  defp drop_module(
         {:->, meta, [[{:in, in_meta, [var, {:__block__, list_meta, [modules]}]}], body]} = clause,
         acc,
         segments
       )
       when is_list(modules) do
    {dropped, kept} = Enum.split_with(modules, &alias_of?(&1, segments))

    if dropped != [] and kept != [] do
      list = {:__block__, list_meta, [carry_comments(kept, dropped)]}
      {{:->, meta, [[{:in, in_meta, [var, list]}], body]}, true}
    else
      {clause, acc}
    end
  end

  defp drop_module(clause, acc, _segments), do: {clause, acc}

  # `Elixir.Foo` is the same module as `Foo`; the diagnostic spells it without
  # the `Elixir.` prefix either way.
  defp alias_of?({:__aliases__, _, segments}, segments), do: true
  defp alias_of?({:__aliases__, _, [Elixir | segments]}, segments), do: true
  defp alias_of?(_node, _segments), do: false

  # Comments written on a removed module would vanish with it, so they move to
  # the first module that survives.
  defp carry_comments([{form, meta, args} | rest], dropped) do
    case Enum.flat_map(dropped, &comments/1) do
      [] ->
        [{form, meta, args} | rest]

      carried ->
        leading = carried ++ Keyword.get(meta, :leading_comments, [])
        [{form, Keyword.put(meta, :leading_comments, leading), args} | rest]
    end
  end

  defp carry_comments(kept, _dropped), do: kept

  defp comments({_form, meta, _args}) do
    Keyword.get(meta, :leading_comments, []) ++ Keyword.get(meta, :trailing_comments, [])
  end

  defp comments(_node), do: []

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
