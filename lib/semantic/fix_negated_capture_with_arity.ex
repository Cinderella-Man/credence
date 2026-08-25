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

  ## Bad

      defmodule ExampleFNCWA do
        def any_full?(lists) do
          Enum.any?(lists, &(!Enum.empty?/1))
        end
      end

  ## Good

      defmodule ExampleFNCWA do
        def any_full?(lists) do
          Enum.any?(lists, &(!Enum.empty?(&1)))
        end
      end
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
  def fix(source, diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, target_position} <- position(diagnostic) do
      {_ast, patches} =
        Macro.prewalk(ast, [], fn
          # &(!Mod.fun/arity) or &(not Mod.fun/arity) — remote function ref
          {:&, am,
           [
             {:/, _dm,
              [
                {neg_op, nm, [{{:., dm2, [mod, fun]}, cm, []}]},
                {:__block__, _, [arity]}
              ]}
           ]} = node,
          patches
          when neg_op in [:!, :not] and is_integer(arity) and arity in 1..255 ->
            args = for i <- 1..arity, do: {:&, [], [i]}
            new_call = {{:., dm2, [mod, fun]}, Keyword.delete(cm, :no_parens), args}

            if at_position?(node, target_position) do
              replacement = {:&, am, [{neg_op, nm, [new_call]}]}
              {node, [patch(node, replacement) | patches]}
            else
              {node, patches}
            end

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
           ]} = node,
          patches
          when neg_op in [:!, :not] and is_atom(atom) and (no_args == nil or no_args == []) and
                 is_integer(arity) and arity in 1..255 ->
            args = for i <- 1..arity, do: {:&, [], [i]}
            new_call = {atom, Keyword.delete(fm, :no_parens), args}

            if at_position?(node, target_position) do
              replacement = {:&, am, [{neg_op, nm, [new_call]}]}
              {node, [patch(node, replacement) | patches]}
            else
              {node, patches}
            end

          node, acc ->
            {node, acc}
        end)

      if patches == [], do: source, else: Sourceror.patch_string(source, patches)
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line

  defp position(%{position: {line, col}}) when is_integer(line) and is_integer(col),
    do: {:ok, {line, col}}

  defp position(%{position: line}) when is_integer(line), do: {:ok, {line, nil}}
  defp position(_diagnostic), do: :error

  defp patch(original, replacement) do
    %{range: Sourceror.get_range(original), change: Sourceror.to_string(replacement)}
  end

  defp at_position?(node, {target_line, nil}) do
    case Sourceror.get_range(node) do
      %{start: [{:line, first} | _], end: [{:line, last} | _]} -> target_line in first..last
      _ -> false
    end
  end

  defp at_position?(node, {target_line, target_col}) do
    case Sourceror.get_range(node) do
      %{start: [line: first_line, column: first_col], end: [line: last_line, column: last_col]} ->
        {target_line, target_col} >= {first_line, first_col} and
          {target_line, target_col} <= {last_line, last_col}

      _ ->
        false
    end
  end
end
