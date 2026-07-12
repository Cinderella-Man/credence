defmodule Credence.Semantic.FixReraiseKeywordInCatch do
  @moduledoc """
  Fixes bare `reraise` inside `catch` clauses.

  LLMs frequently emit bare `reraise` (a Python keyword) inside `catch` clauses,
  producing an `undefined variable "reraise"` compile error. A semantic rule can
  match this specific diagnostic and replace it with
  `:erlang.raise(kind, reason, __STACKTRACE__)` using the already-bound catch variables.

  When the catch clause's kind pattern is a literal atom (e.g. `:error`, `:exit`),
  it is replaced with a `kind` variable so that `:erlang.raise/3` can re-raise
  whatever was caught. When the kind is already a variable, it is reused as-is.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "undefined variable \"reraise\""

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_reraise_keyword_in_catch,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed?} =
        Macro.prewalk(ast, false, fn
          {:try, meta, children}, acc ->
            {new_children, child_changed?} = fix_try_catch(children)

            if child_changed? do
              {{:try, meta, new_children}, true}
            else
              {{:try, meta, children}, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed?, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # -- try/catch transformation ------------------------------------------------

  # In Sourceror's AST, `try` children is `[keyword_list]` where keyword_list
  # is `[{do_pair}, {catch_pair}, ...]`. We unwrap the outer list, transform the
  # catch pair, then re-wrap.
  defp fix_try_catch([keyword_list]) when is_list(keyword_list) do
    {new_kw, changed?} =
      Enum.map_reduce(keyword_list, false, fn
        {{:__block__, catch_meta, [:catch]}, clauses}, acc ->
          {new_clauses, clause_changed?} = fix_catch_clauses(clauses)

          if clause_changed? do
            {{{:__block__, catch_meta, [:catch]}, new_clauses}, true}
          else
            {{{:__block__, catch_meta, [:catch]}, clauses}, acc}
          end

        other, acc ->
          {other, acc}
      end)

    {[new_kw], changed?}
  end

  defp fix_try_catch(children), do: {children, false}

  defp fix_catch_clauses(clauses) do
    Enum.map_reduce(clauses, false, fn
      {:->, arrow_meta, [patterns, body]}, acc ->
        if has_bare_reraise?(body) do
          {kind_name, new_patterns} = resolve_kind_pattern(patterns)
          reason_name = resolve_reason_name(patterns)
          new_body = replace_reraise(body, kind_name, reason_name)
          {{:->, arrow_meta, [new_patterns, new_body]}, true}
        else
          {{:->, arrow_meta, [patterns, body]}, acc}
        end

      other, acc ->
        {other, acc}
    end)
  end

  # -- detection helpers -------------------------------------------------------

  defp has_bare_reraise?(body) do
    {_, found?} =
      Macro.prewalk(body, false, fn
        {:reraise, _, nil} = node, _ -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  # -- pattern helpers ---------------------------------------------------------

  # Given the catch clause patterns list `[kind_pattern, reason_pattern, ...]`,
  # determine the kind variable name and produce the (possibly updated) patterns.
  # If the kind is a literal atom (e.g. `:error`), replace it with a fresh
  # `kind` variable. If it is already a variable, reuse its name.
  defp resolve_kind_pattern([kind_ast | rest]) do
    case kind_ast do
      {:__block__, _meta, [atom]} when is_atom(atom) ->
        {:kind, [{:kind, [], nil} | rest]}

      {name, _meta, ctx} when is_atom(name) and (ctx == nil or ctx == Elixir) ->
        {name, [kind_ast | rest]}

      _ ->
        {:kind, [{:kind, [], nil} | rest]}
    end
  end

  # Extract the reason variable name from the catch patterns list.
  defp resolve_reason_name([_kind, reason_ast | _]) do
    case reason_ast do
      {name, _meta, ctx} when is_atom(name) and (ctx == nil or ctx == Elixir) -> name
      _ -> :reason
    end
  end

  # -- body replacement --------------------------------------------------------

  defp replace_reraise(body, kind_name, reason_name) do
    Macro.prewalk(body, fn
      {:reraise, _meta, nil} ->
        build_erlang_raise(kind_name, reason_name)

      node ->
        node
    end)
  end

  defp build_erlang_raise(kind_name, reason_name) do
    {
      {:., [], [{:__block__, [], [:erlang]}, :raise]},
      [],
      [
        {kind_name, [], nil},
        {reason_name, [], nil},
        {:__STACKTRACE__, [], nil}
      ]
    }
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
