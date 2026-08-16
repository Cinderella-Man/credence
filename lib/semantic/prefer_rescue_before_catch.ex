defmodule Credence.Semantic.PreferRescueBeforeCatch do
  @moduledoc """
  Fixes the compiler warning when `catch` appears before `rescue` in a `try` block.

  The compiler emits:

      "catch" should always come after "rescue" in try

  Reordering `rescue`-before-`catch` is behaviour-preserving: the compiler
  always places the `rescue` clauses ahead of the user's `catch` clauses in the
  code it emits, whatever order the source wrote them in — that mismatch is
  exactly what the warning is about. Verified end to end: with a narrow
  `rescue e in ArgumentError` competing against `catch :error, e`, both source
  orders return the same value for an `ArgumentError`, a `RuntimeError`, a
  `throw`, an `exit`, a plain return and `:erlang.error(:badarith)`, and the
  `after` block runs the same either way. The fix also removes a compiler
  warning that blocks `--warnings-as-errors`.

  ## Scope

  The warning text is form-specific: a `def` body with the same mistake reads
  `"catch" should always come after "rescue" in def`, which this rule does not
  match and does not rewrite. Only literal `try` blocks are touched, and
  `should_report?/2` re-checks the source for a real out-of-order `try` before
  reporting, so a warning raised from a macro expansion (no literal `try` in
  the file to reorder) is never flagged as an issue this rule won't fix.

  ## Bad

      defmodule CredenceRescueOrderLiveReproPRBC do
        def run(f) do
          try do
            f.()
          catch
            :exit, reason -> {:exit, reason}
            :throw, value -> {:throw, value}
          rescue
            e -> {:rescue, e}
          end
        end
      end

  ## Good

      defmodule CredenceRescueOrderLiveReproPRBC do
        def run(f) do
          try do
            f.()
          rescue
            e -> {:rescue, e}
          catch
            :exit, reason -> {:exit, reason}
            :throw, value -> {:throw, value}
          end
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "\"catch\" should always come after \"rescue\" in try"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @doc """
  Only report when the source really holds a `try` whose `catch` section comes
  before its `rescue` section — the same predicate `fix/2` reorders on, so the
  check and the fix can never disagree.
  """
  def should_report?(_diagnostic, source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> out_of_order_try?(ast)
      _ -> false
    end
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :prefer_rescue_before_catch,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.postwalk(ast, fn
          {:try, meta, [clauses]} = node when is_list(clauses) ->
            case out_of_order(clauses) do
              {catch_idx, rescue_idx} ->
                {:try, meta, [reorder(clauses, catch_idx, rescue_idx)]}

              nil ->
                node
            end

          node ->
            node
        end)

      Sourceror.to_string(result)
    else
      _ -> source
    end
  end

  # True when any `try` in the AST writes its `catch` section before its
  # `rescue` section. Shared with `should_report?/2` so check and fix agree.
  defp out_of_order_try?(ast) do
    {_ast, found?} =
      Macro.postwalk(ast, false, fn
        {:try, _meta, [clauses]} = node, acc when is_list(clauses) ->
          {node, acc or out_of_order(clauses) != nil}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  # `{catch_index, rescue_index}` when both sections are present and `catch`
  # comes first; `nil` otherwise (no `catch`, no `rescue`, or already ordered).
  defp out_of_order(clauses) do
    catch_idx = Enum.find_index(clauses, &section?(&1, :catch))
    rescue_idx = Enum.find_index(clauses, &section?(&1, :rescue))

    if catch_idx && rescue_idx && catch_idx < rescue_idx do
      {catch_idx, rescue_idx}
    end
  end

  defp section?({{:__block__, _, [name]}, _value}, name), do: true
  defp section?(_clause, _name), do: false

  # Lift both sections out and re-insert them as `rescue`-then-`catch` where the
  # `catch` used to sit, leaving every other section (`do`, `else`, `after`) in
  # its original relative order.
  defp reorder(clauses, catch_idx, rescue_idx) do
    catch_clause = Enum.at(clauses, catch_idx)
    rescue_clause = Enum.at(clauses, rescue_idx)

    without =
      clauses
      |> Enum.with_index()
      |> Enum.reject(fn {_, i} -> i == catch_idx or i == rescue_idx end)
      |> Enum.map(fn {c, _} -> c end)

    {before, after_} = Enum.split(without, catch_idx)
    before ++ [rescue_clause, catch_clause] ++ after_
  end

  defp line(%{position: {line, _col}}) when is_integer(line), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_diagnostic), do: nil
end
