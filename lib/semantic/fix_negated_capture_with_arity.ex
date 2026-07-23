defmodule Credence.Semantic.FixNegatedCaptureWithArity do
  @moduledoc """
  Fixes `&(!fun/arity)` and `&(not fun/arity)` capture syntax.

  LLMs negate a capture by bolting `!`/`not` onto the `&fun/arity` form.
  That is invalid — inside `&(...)` the body must use `&1`-style arguments —
  so the compiler emits:

      invalid args for &, expected one of: ...
      Got: !Enum.empty?() / 1

  The fix replaces the bare `/N` arity with `&1`-style argument placeholders:

      &(!Enum.empty?/1)    →  &(!Enum.empty?(&1))
      &(not Enum.empty?/1) →  &(not Enum.empty?(&1))

  Semantics are identical — the capture still negates the function result,
  just in the argument form the compiler accepts.

  ## Matching vs fixing

  `Credence.Semantic.FixInvalidCaptureWithArguments` claims every
  `invalid args for &` diagnostic, and rule dispatch is first-match, so at
  equal priority it would shadow this rule and no-op on the negated shapes
  (its `fixable_call?` refuses operators, including `!` and `not`). This
  rule therefore runs at a lower `priority`, and narrows `match?/1` to
  diagnostics whose `Got:` line starts with a negation — every other
  `invalid args for &` diagnostic still falls through to that rule. The
  `should_report?/2` phase hook keeps `analyze` honest by reporting an
  issue only when the fix would actually rewrite the source.

  ## Deliberately skipped (no fix)

    * `/0` arities (`&(!foo/0)`) — a capture must take at least one
      argument, so no `&1`-placeholder rewrite can have the declared arity;
      likewise arities above 255, which captures cannot express;
    * negated bodies without a bare `/arity` (`&(!x)`) — there is no
      declared arity to build the argument list from, and valid captures
      such as `&(!Enum.empty?(&1))` or `&(!&1 / 2)` must not be touched.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "invalid args for &"
  @negated_got ~r/Got: (!|not )/

  # Must sort before FixInvalidCaptureWithArguments (priority 500): its
  # broader match? would otherwise claim every negated-capture diagnostic
  # first and this rule would never fire.
  @impl true
  def priority, do: 490

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring) and Regex.match?(@negated_got, msg)
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source. `match?/1` sees just the
  diagnostic, so without this gate negated shapes this rule deliberately
  skips (`/0` arities, `&(!x)`) would be attributed to this rule.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_negated_capture_with_arity,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed?} =
        Macro.prewalk(ast, false, fn
          # &(!Mod.fun/arity) or &(not Mod.fun/arity) — remote function ref
          {:&, am,
           [
             {:/, _dm,
              [
                {neg_op, nm, [{{:., dm2, [mod, fun]}, cm, []}]},
                {:__block__, _, [arity]}
              ]}
           ]},
          _acc
          when neg_op in [:!, :not] and is_integer(arity) and arity in 1..255 ->
            args = for i <- 1..arity, do: {:&, [], [i]}
            new_call = {{:., dm2, [mod, fun]}, Keyword.delete(cm, :no_parens), args}
            {{:&, am, [{neg_op, nm, [new_call]}]}, true}

          # &(!fun/arity) or &(not fun/arity) — local function ref, written
          # bare (`!fun/1`, parsed as a variable node) or with empty call
          # parens (`!fun()/1`)
          {:&, am,
           [
             {:/, _dm,
              [
                {neg_op, nm, [{atom, fm, no_args}]},
                {:__block__, _, [arity]}
              ]}
           ]},
          _acc
          when neg_op in [:!, :not] and is_atom(atom) and (no_args == nil or no_args == []) and
                 is_integer(arity) and arity in 1..255 ->
            args = for i <- 1..arity, do: {:&, [], [i]}
            new_call = {atom, Keyword.delete(fm, :no_parens), args}
            {{:&, am, [{neg_op, nm, [new_call]}]}, true}

          node, acc ->
            {node, acc}
        end)

      if changed?, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
