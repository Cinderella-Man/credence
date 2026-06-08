defmodule Credence.Pattern.PreferRegexMatch do
  @moduledoc """
  Rewrites a `case` over `Regex.run/2` that only tests **whether** the regex
  matched — never the captured groups — into the idiomatic boolean form built
  on `Regex.match?/2`.

  ## Bad

      case Regex.run(~r/ab{3,}/, string) do
        [_ | _] -> "Found a match!"
        _ -> "Not matched!"
      end

  ## Good

      if Regex.match?(~r/ab{3,}/, string) do
        "Found a match!"
      else
        "Not matched!"
      end

  ## Scope (the safe core)

  `Regex.run(re, str)` (default `:capture`) returns `nil` on no match and a
  **non-empty** list (the whole match is always element 0) on a match. So the
  pattern `[_ | _]` matches *exactly* the "matched" case and `nil`/`_` the
  "no match" case — which is precisely what `Regex.match?/2` decides. The fix
  fires only when ALL of these hold:

  - The scrutinee is `Regex.run(re, str)` with **exactly two arguments**.
  - There are **exactly two clauses**, neither guarded.
  - One clause pattern is `[_ | _]` (wildcard head *and* tail — binds nothing).
  - The other clause pattern is `nil` or `_`.
  - When the other clause is the catch-all `_`, the `[_ | _]` clause comes
    **first** (otherwise `_` shadows it and the `[_ | _]` body is dead code —
    converting to an `if` would change the result). When the other clause is
    `nil` the two patterns are disjoint, so either order is safe.

  The `[_ | _]` body becomes the `do` branch and the `nil`/`_` body the `else`
  branch, regardless of source order.

  ## Does NOT fire (deliberately dropped — not provably behaviour-preserving)

  - **`Regex.run/3` with options.** `capture: :none` (and `:all_but_first`
    with no subpatterns) returns `[]` on a match, which `[_ | _]` does *not*
    match — the two forms disagree, so any 3-argument call is skipped.
  - **A bound head** (`[match | _]`) — the body reads the capture, which
    `Regex.match?/2` does not provide.
  - **More than two clauses, or specific-capture patterns** (`["x"]`,
    `[_, a, b]`, `[]`) — these inspect the captures, not mere existence.
  - **A single clause, or a second clause that does not cover `nil`** — the
    original raises `CaseClauseError` on a no-match where an `if` would not.
  - **A named catch-all** (`other ->`) — its body may read the bound `nil`.
  - **Guarded clauses.**
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:case, meta, [call, [{{:__block__, _, [:do]}, clauses}]]} = node, issues
        when is_list(clauses) ->
          case convert(call, clauses) do
            {:ok, _do_body, _else_body} -> {node, [build_issue(meta) | issues]}
            :no -> {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source) || Sourceror.to_string(ast)
    RuleHelpers.patches_from_ast_transform(ast, source, &rewrite/1)
  end

  defp rewrite(ast) do
    Macro.prewalk(ast, fn
      {:case, meta, [call, [{{:__block__, _, [:do]}, clauses}]]} = node when is_list(clauses) ->
        case convert(call, clauses) do
          {:ok, do_body, else_body} -> build_if(meta, call, do_body, else_body)
          :no -> node
        end

      node ->
        node
    end)
  end

  # The single shared decision used by both check and fix: returns the `do`
  # and `else` bodies of the equivalent `if`, or `:no`. check and fix can
  # never disagree because they call exactly this.
  defp convert(call, clauses) do
    with true <- regex_run_2arg?(call),
         {:ok, do_body, else_body} <- split_clauses(clauses) do
      {:ok, do_body, else_body}
    else
      _ -> :no
    end
  end

  # `Regex.run(re, str)` — exactly two arguments (no options).
  defp regex_run_2arg?({{:., _, [{:__aliases__, _, [:Regex]}, :run]}, _, [_re, _str]}), do: true
  defp regex_run_2arg?(_), do: false

  # Exactly two clauses: a `[_ | _]` clause and a `nil`/`_` clause. The `[_|_]`
  # body is the `do` branch, the other body the `else` branch. A leading `_`
  # would shadow a trailing `[_|_]`, so that ordering is rejected.
  defp split_clauses([c1, c2]) do
    case {classify(c1), classify(c2)} do
      {{:cons, do_body}, {:nil_pat, else_body}} -> {:ok, do_body, else_body}
      {{:nil_pat, else_body}, {:cons, do_body}} -> {:ok, do_body, else_body}
      {{:cons, do_body}, {:wild, else_body}} -> {:ok, do_body, else_body}
      _ -> :no
    end
  end

  defp split_clauses(_), do: :no

  # An unguarded single-pattern clause classified by its pattern. A guarded
  # clause carries a `{:when, ...}` node as its pattern and falls through to
  # `:other`.
  defp classify({:->, _, [[pattern], body]}) do
    cond do
      cons_wildcard?(pattern) -> {:cons, body}
      nil_pattern?(pattern) -> {:nil_pat, body}
      wildcard?(pattern) -> {:wild, body}
      true -> :other
    end
  end

  defp classify(_), do: :other

  # `[_ | _]` — Sourceror wraps the list pattern in `{:__block__, _, [[...]]}`.
  defp cons_wildcard?({:__block__, _, [[{:|, _, [{:_, _, _}, {:_, _, _}]}]]}), do: true
  defp cons_wildcard?(_), do: false

  defp nil_pattern?({:__block__, _, [nil]}), do: true
  defp nil_pattern?(nil), do: true
  defp nil_pattern?(_), do: false

  defp wildcard?({:_, _, ctx}) when is_atom(ctx), do: true
  defp wildcard?(_), do: false

  defp build_if(meta, {_, _, [re, str]}, do_body, else_body) do
    match_call =
      {{:., [], [{:__aliases__, [], [:Regex]}, :match?]}, [], [re, str]}

    {:if, meta,
     [
       match_call,
       [
         {{:__block__, [], [:do]}, do_body},
         {{:__block__, [], [:else]}, else_body}
       ]
     ]}
  end

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_regex_match,
      message:
        "`Regex.run/2` is used only to test whether the regex matches, but `Regex.match?/2` " <>
          "returns a boolean directly and is the idiomatic way to check for a match.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
