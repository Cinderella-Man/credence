defmodule Credence.Semantic.NoRescueInException do
  @moduledoc """
  Fixes the common LLM mistake of using `rescue e in Exception`, which warns
  because `Exception` is a behaviour module, not a struct.

  The compiler emits:

      struct Exception is undefined (there is such module but it does not define a struct)

  The clause is dead — `rescue e in Exception` can never match, because the
  rescue lowers to a `%Exception{}` struct match and no such struct exists.
  Removing the dead clause preserves that behaviour:

      rescue e in Exception -> ...   # WRONG — warns, and never matches
      # clause removed; exceptions continue to propagate

  Only a `rescue` clause is removed, and only when its type is spelled exactly
  `Exception` or `Elixir.Exception`. Everything else that happens to parse as
  `_ in Exception` is left alone — see `fix/2`.

  ## Bad

      defmodule ExampleNRIE do
        def run do
          try do
            raise "boom"
          rescue
            e in Elixir.Exception ->
              {:error, e}
          end
        end
      end

  ## Good

      defmodule ExampleNRIE do
        def run do
          try do
            raise "boom"
          rescue
            e ->
              {:error, e}
          end
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "struct Exception is undefined"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @doc """
  Only report what `fix/2` will actually repair. The diagnostic alone cannot
  tell us whether the flagged `Exception` is the stdlib module or a locally
  aliased struct, so the source-aware narrowing lives in `fix/2` and the check
  simply defers to it.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_rescue_in_exception,
      message: "rescue e in Exception is not valid; remove the dead rescue clause",
      meta: %{line: line(diagnostic)}
    }
  end

  @doc """
  Removes every dead `rescue _ in Exception` clause in `source`.

  The diagnostic's position is deliberately *not* used to scope the rewrite:
  the compiler collapses repeated occurrences (two `rescue e in Exception`
  blocks in one function yield a single diagnostic), and the semantic phase
  handles warnings in one terminal pass with no retry — so a position-scoped
  fix would leave the collapsed siblings behind, still warning. Scoping is
  structural instead, and refuses three shapes the sweep would otherwise get
  wrong:

    * `_ in Exception` outside a rescue head — `if x in Exception`, a `cond`
      clause — where `in` means `Enum.member?/2`, not a struct match. Dropping
      it turns a call that raises `Protocol.UndefinedError` into a truthiness
      test.
    * any alias other than `Exception` / `Elixir.Exception`, i.e. a real
      exception struct, which must keep its narrow rescue.
    * a bare `Exception` in a file that aliases the name at all. A
      block-scoped `alias MyApp.Exception` shadows the stdlib module for part
      of a file only, so a genuine struct rescue can sit in the same file as a
      flagged one. Rather than track lexical alias scopes, the whole file is
      left untouched — `Elixir.Exception` still gets fixed, since no alias can
      shadow the fully-qualified name.
  """
  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      shadowed? = aliases_exception?(ast)

      {rewritten, changed?} =
        Macro.postwalk(ast, false, fn
          {:try, _, [[{{:__block__, _, [:do]}, body}]]}, true ->
            {body, true}

          entries, acc when is_list(entries) ->
            Enum.map_reduce(entries, acc, &remove_exception_clause(&1, &2, shadowed?))
            |> then(fn {fixed, touched?} -> {Enum.reject(fixed, &is_nil/1), touched?} end)

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

  defp remove_exception_clause(
         {{:__block__, _, [:rescue]} = key, clauses} = entry,
         acc,
         shadowed?
       )
       when is_list(clauses) do
    {kept, removed?} = Enum.map_reduce(clauses, false, &keep_clause(&1, &2, shadowed?))
    kept = Enum.reject(kept, &is_nil/1)

    cond do
      not removed? -> {entry, acc}
      kept == [] -> {nil, true}
      true -> {{key, kept}, true}
    end
  end

  defp remove_exception_clause(entry, acc, _shadowed?), do: {entry, acc}

  # A rescue clause is `{:->, meta, [[head], body]}`; only a bare-variable head
  # (`e in Exception`) is removed. `e in Exception when ...`, a pinned or
  # destructured head, or a multi-element head all fall through untouched.
  defp keep_clause(
         {:->, _, [[{:in, _, [{_name, _, nil}, {:__aliases__, _, segments}]}], _]} = clause,
         removed?,
         shadowed?
       ) do
    if rewritable?(segments, shadowed?), do: {nil, true}, else: {clause, removed?}
  end

  defp keep_clause(clause, removed?, _shadowed?), do: {clause, removed?}

  # `Elixir.Exception` is unambiguous — no alias can shadow a fully-qualified
  # name — so it stays fixable even in a file that aliases `Exception`.
  defp rewritable?([Elixir, :Exception], _shadowed?), do: true
  defp rewritable?([:Exception], shadowed?), do: not shadowed?
  defp rewritable?(_segments, _shadowed?), do: false

  # True when the file has any `alias`/`require` that mentions `Exception`,
  # covering `alias A.Exception`, `alias A.B, as: Exception` and
  # `alias A.{Exception, C}` in one conservative sweep. Over-triggering only
  # costs us a fix we decline to make; under-triggering would widen a real
  # struct rescue into a catch-all.
  defp aliases_exception?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {directive, _, args} = node, acc when directive in [:alias, :require] and is_list(args) ->
          {node, acc or mentions_exception?(args)}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp mentions_exception?({:__aliases__, _, segments}) when is_list(segments) do
    :Exception in segments
  end

  defp mentions_exception?({left, _, right}) do
    mentions_exception?(left) or mentions_exception?(right)
  end

  defp mentions_exception?({left, right}) do
    mentions_exception?(left) or mentions_exception?(right)
  end

  defp mentions_exception?(list) when is_list(list), do: Enum.any?(list, &mentions_exception?/1)
  defp mentions_exception?(_other), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
