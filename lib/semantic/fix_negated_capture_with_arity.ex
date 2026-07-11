defmodule Credence.Semantic.FixNegatedCaptureWithArity do
  @moduledoc """
  Fixes `&(!fn/arity)` and `&(not fn/arity)` capture syntax.

  LLMs write negated captures with the `/arity` form, which is invalid inside
  a compound `&()` expression. The compiler emits:

      "invalid args for &, expected one of: ..."

  The fix replaces the bare `/N` arity with `&1`-style argument placeholders:

      &(!Enum.empty?/1)   →  &(!Enum.empty?(&1))
      &(not Enum.empty?/1) →  &(not Enum.empty?(&1))

  Semantics are identical — the capture still negates the function result, just
  with the idiomatic `&1` argument form that the compiler accepts.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "invalid args for &"

  @impl true
  def match?(%{severity: sev, message: msg})
      when sev in [:warning, :error] and is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

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
          when neg_op in [:!, :not] and is_integer(arity) ->
            args = for i <- 1..arity, do: {:&, [], [i]}
            new_call = {{:., dm2, [mod, fun]}, Keyword.delete(cm, :no_parens), args}
            {{:&, am, [{neg_op, nm, [new_call]}]}, true}

          # &(!func/arity) or &(not func/arity) — local function ref
          {:&, am,
           [
             {:/, _dm,
              [
                {neg_op, nm, [{atom, fm, nil}]},
                {:__block__, _, [arity]}
              ]}
           ]},
          _acc
          when neg_op in [:!, :not] and is_atom(atom) and is_integer(arity) ->
            args = for i <- 1..arity, do: {:&, [], [i]}
            new_call = {atom, fm, args}
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
