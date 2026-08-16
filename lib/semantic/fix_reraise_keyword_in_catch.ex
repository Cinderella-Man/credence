defmodule Credence.Semantic.FixReraiseKeywordInCatch do
  @moduledoc """
  Fixes bare `reraise` inside `catch` clauses.

  LLMs frequently emit bare `reraise` (a Python habit — `raise` with no
  argument re-raises the current exception) inside `catch` clauses. Elixir's
  `reraise` is a 2/3-arity macro, so a bare reference compiles as a variable
  and produces an `undefined variable "reraise"` error. The fix replaces the
  bare `reraise` with `:erlang.raise(kind, reason, __STACKTRACE__)`, built
  from the clause's own head.

  The clause head is never rewritten — the arguments are read out of it:

    * a literal atom pattern (`:error`, `:exit`, `:throw`) is passed as the
      same literal;
    * a plain variable pattern is reused as-is;
    * a single-pattern clause (`catch value ->`, shorthand for
      `catch :throw, value ->`) re-raises with kind `:throw`.

  Clauses whose head cannot be read back safely are left untouched (the fix
  no-ops): guards (`when`), composite patterns (`{:badmatch, v}`), `_`, and
  underscore-prefixed variables (unreadable or warning-producing in a body).
  Bare `reraise` outside a `try`'s `catch` clauses (e.g. in `rescue`) is also
  left alone — there is no caught kind/reason pair to rebuild the raise from.

  ## Dispatch

  `match?/1` sees only the diagnostic, and `FixCaseBranchAssignmentScope`
  claims the whole `undefined variable "name"` family at priority 500.
  `undefined variable "reraise"` is claimed here at priority 450: `reraise`
  is a Kernel macro name, so an LLM emitting it bare means the Python
  re-raise habit, not an ordinary variable. `should_report?/2` keeps
  `analyze` honest by reporting only when the fix would rewrite the source.

  ## Bad

      defmodule M do
        def f do
          try do
            :ok
          catch
            :error, reason ->
              reraise
          end
        end
      end

  ## Good

      defmodule M do
        def f do
          try do
            :ok
          catch
            :error, reason ->
              :erlang.raise(:error, reason, __STACKTRACE__)
          end
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "undefined variable \"reraise\""

  @impl true
  def priority, do: 450

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source. A bare `reraise` outside a
  fixable `catch` clause (e.g. in `rescue`) matches the diagnostic but has
  no safe rewrite, so it must not be flagged.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

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
        {{:__block__, catch_meta, [:catch]}, clauses}, acc when is_list(clauses) ->
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
      {:->, arrow_meta, [patterns, body]} = clause, acc ->
        case clause_raise_args(patterns) do
          {:ok, kind_arg, reason_arg} ->
            {new_body, changed?} = replace_reraise(body, kind_arg, reason_arg)

            if changed? do
              {{:->, arrow_meta, [patterns, new_body]}, true}
            else
              {clause, acc}
            end

          :skip ->
            {clause, acc}
        end

      other, acc ->
        {other, acc}
    end)
  end

  # -- clause-head helpers -------------------------------------------------------

  # `catch kind, reason ->` — re-raise the same kind with the same reason.
  defp clause_raise_args([kind_pat, reason_pat]) do
    with {:ok, kind_arg} <- pattern_arg(kind_pat),
         {:ok, reason_arg} <- pattern_arg(reason_pat) do
      {:ok, kind_arg, reason_arg}
    else
      _ -> :skip
    end
  end

  # `catch value ->` is shorthand for `catch :throw, value ->`.
  defp clause_raise_args([value_pat]) do
    case pattern_arg(value_pat) do
      {:ok, reason_arg} -> {:ok, {:__block__, [], [:throw]}, reason_arg}
      :skip -> :skip
    end
  end

  defp clause_raise_args(_), do: :skip

  # A pattern can be read back as an argument only when it is a literal atom
  # (pass the same literal — the clause matched, so the value IS that atom) or
  # a plain variable (reuse the binding). Everything else — guards, composite
  # patterns, pins, `_`, underscore-prefixed names — is skipped: the head must
  # never be rewritten, and those bindings cannot be referenced cleanly.
  defp pattern_arg({:__block__, _meta, [atom]}) when is_atom(atom),
    do: {:ok, {:__block__, [], [atom]}}

  defp pattern_arg({name, _meta, ctx}) when is_atom(name) and (ctx == nil or ctx == Elixir) do
    if String.starts_with?(Atom.to_string(name), "_") do
      :skip
    else
      {:ok, {name, [], ctx}}
    end
  end

  defp pattern_arg(_), do: :skip

  # -- body replacement --------------------------------------------------------

  # Replace every bare `reraise` in the clause body. A nested `try` is NOT
  # descended into: its own catch clauses re-bind kind/reason, and the outer
  # prewalk in fix/2 visits that `try` separately with the right bindings.
  defp replace_reraise({:reraise, _meta, nil}, kind_arg, reason_arg),
    do: {build_erlang_raise(kind_arg, reason_arg), true}

  defp replace_reraise({:try, _, _} = node, _kind_arg, _reason_arg), do: {node, false}

  defp replace_reraise({form, meta, args}, kind_arg, reason_arg) when is_list(args) do
    {new_form, form_changed?} = replace_reraise(form, kind_arg, reason_arg)
    {new_args, args_changed?} = replace_in_list(args, kind_arg, reason_arg)
    {{new_form, meta, new_args}, form_changed? or args_changed?}
  end

  defp replace_reraise({left, right}, kind_arg, reason_arg) do
    {new_left, left_changed?} = replace_reraise(left, kind_arg, reason_arg)
    {new_right, right_changed?} = replace_reraise(right, kind_arg, reason_arg)
    {{new_left, new_right}, left_changed? or right_changed?}
  end

  defp replace_reraise(list, kind_arg, reason_arg) when is_list(list),
    do: replace_in_list(list, kind_arg, reason_arg)

  defp replace_reraise(other, _kind_arg, _reason_arg), do: {other, false}

  defp replace_in_list(list, kind_arg, reason_arg) do
    Enum.map_reduce(list, false, fn element, acc ->
      {new_element, changed?} = replace_reraise(element, kind_arg, reason_arg)
      {new_element, acc or changed?}
    end)
  end

  defp build_erlang_raise(kind_arg, reason_arg) do
    {
      {:., [], [{:__block__, [], [:erlang]}, :raise]},
      [],
      [kind_arg, reason_arg, {:__STACKTRACE__, [], nil}]
    }
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
