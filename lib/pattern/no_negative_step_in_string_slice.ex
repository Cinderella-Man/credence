defmodule Credence.Pattern.NoNegativeStepInStringSlice do
  @moduledoc """
  Detects `String.slice(str, n..-1)` where the range carries no explicit step.

  A range whose first element is greater than its last defaults to step -1, and
  writing that implicitly has been deprecated since the `first..last//step` syntax
  arrived in **Elixir 1.12** — not 1.19, as this rule's first draft claimed. The
  auto-fix makes the step explicit: `n..-1` → `n..-1//1`.

  ## What it does today, measured on 1.20.2

      String.slice("abcdefghij", 4..-1)     #=> "efghij"   + 2 warnings
      String.slice("abcdefghij", 4..-1//1)  #=> "efghij"   silent

  So the value returned today is still the suffix, with a warning — it does **not**
  return `""`, which the accepting rationale claimed. The repair is therefore
  behaviour-preserving now and future-proofing against the warning becoming an
  error; it is not fixing a wrong answer.

  ## Scope

  Only a literal `-1` endpoint is flagged, and only where the implicit step really
  is -1. A **negative literal start** is declined, because `-6..-1` ascends, warns
  about nothing, and needs no repair (measured above). Explicit steps and other
  endpoints are left alone.

  ## Bad

      String.slice(str, n..-1)

  ## Good

      String.slice(str, n..-1//1)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  # Rule Standard item 5 (docs/19), decided deliberately. The construct the static
  # scan flags here is the `-` of the literal `-1` endpoint and the `//` of the
  # step it introduces — neither is arithmetic in a DSL expression, both are parts
  # of a range literal in the second argument of `String.slice/2`. Ash.Expr,
  # Ecto.Query and Nx.Defn give no second meaning to `String.slice/2`, and none of
  # them accepts it in an expression at all, so the rewrite cannot land inside one.
  @impl true
  def unsafe_in_dsl, do: []

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Both spellings. `String.slice(str, range)` arrives with two arguments and
        # `str |> String.slice(range)` with one — the pipe's left side is not in
        # this node. Matching only the two-argument form is what let the fix
        # rewrite piped calls the check had never reported.
        {{:., _, [{:__aliases__, _, [:String]}, :slice]}, _meta, args} = node, issues
        when is_list(args) ->
          case slice_range(args) do
            {:ok, range} ->
              if bare_neg_one_range?(range) do
                {node, [build_issue(get_line(range)) | issues]}
              else
                {node, issues}
              end

            :error ->
              {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, fn
      {{:., _, [{:__aliases__, _, [:String]}, :slice]}, _, args} = node when is_list(args) ->
        with {:ok, range} <- slice_range(args),
             true <- bare_neg_one_range?(range) do
          put_elem(node, 2, replace_range(args, with_step_one(range)))
        else
          _ -> node
        end

      node ->
        node
    end)
  end

  # The one place that decides which argument is the range, shared by `check/2`
  # and `fix_patches/2`. Keeping two copies of it is how the fix came to rewrite
  # the piped form while the check reported only the direct one — and, after the
  # acceptance narrowing, how it came to rewrite `-6..-1` that the check declines.
  defp slice_range([_str, range]), do: {:ok, range}
  defp slice_range([range]), do: {:ok, range}
  defp slice_range(_args), do: :error

  defp replace_range([str, _range], new_range), do: [str, new_range]
  defp replace_range([_range], new_range), do: [new_range]

  defp with_step_one({:.., range_meta, [start, last]}),
    do: {:..//, range_meta, [start, last, {:__block__, [], [1]}]}

  defp bare_neg_one_range?({:.., _, [start, {:-, _, [{:__block__, _, [1]}]}]}),
    do: not negative_int_literal?(start)

  defp bare_neg_one_range?(_range), do: false

  # `-6` parses as unary minus over a literal, not as a literal -6.
  defp negative_int_literal?({:-, _, [{:__block__, _, [n]}]}) when is_integer(n), do: true
  defp negative_int_literal?(_node), do: false

  defp get_line({_, meta, _}) when is_list(meta), do: Keyword.get(meta, :line)
  defp get_line(_), do: nil

  defp build_issue(line) do
    %Issue{
      rule: :no_negative_step_in_string_slice,
      message:
        "`String.slice(str, n..-1)` uses a range with implicit step -1 in Elixir 1.19+. " <>
          "Use `String.slice(str, n..-1//1)` to make the positive step explicit.",
      meta: %{line: line}
    }
  end
end
