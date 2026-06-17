defmodule Credence.Pattern.PreferMapsetForSetEquality do
  @moduledoc """
  Detects two `String.codepoints/1` (or `String.graphemes/1`) results that are
  each run through `Enum.uniq() |> Enum.sort()` and then compared with `==` for
  set-equality checking, and rewrites them to compare `MapSet.new/1` directly.

  ## Why this matters

  The pattern `Enum.uniq() |> Enum.sort()` builds an unnecessary intermediate
  list and sort when the only goal is to compare two collections for equal
  membership (set equality). `MapSet.new/1` is semantically explicit and avoids
  the sort overhead.

  ## Safe core

  The rule fires only when the compared collections come from
  `String.codepoints/1` or `String.graphemes/1`. Those always return lists of
  binaries, so the two formulations agree exactly:

    * list `==` compares elements with `==`, which coerces numbers
      (`[1] == [1.0]` is `true`), whereas `MapSet` comparison treats `1` and
      `1.0` as distinct keys (`MapSet.new([1]) == MapSet.new([1.0])` is
      `false`). Restricting to binary-returning calls removes that divergence —
      binaries never coerce.
    * `Enum.uniq/1` and `MapSet.new/1` both deduplicate with `===`, so set
      membership is preserved.

  It also fires only on a block of exactly the two sorted-uniq assignments
  followed by their comparison, so collapsing the block to a single expression
  cannot drop other statements or break references to the assigned variables.

  ## Bad

      first_set = String.codepoints(first) |> Enum.uniq() |> Enum.sort()
      second_set = String.codepoints(second) |> Enum.uniq() |> Enum.sort()
      first_set == second_set

  ## Good

      MapSet.new(String.codepoints(first)) == MapSet.new(String.codepoints(second))
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case check_block(node) do
          {:ok, issues} -> {node, issues ++ acc}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:__block__, _, stmts} = node when is_list(stmts) ->
        case match_block(stmts) do
          {:ok, arg1, arg2} -> make_mapset_eq(arg1, arg2)
          :no -> node
        end

      node ->
        node
    end)
  end

  # Returns {:ok, issues} when `stmts` is exactly:
  #   v1 = String.codepoints(a) |> Enum.uniq() |> Enum.sort()
  #   v2 = String.codepoints(b) |> Enum.uniq() |> Enum.sort()
  #   v1 == v2            (v1, v2 in either order; v1 != v2)
  defp check_block({:__block__, meta, stmts}) when is_list(stmts) do
    case match_block(stmts) do
      {:ok, _arg1, _arg2} ->
        line = Keyword.get(meta, :line) || find_line(stmts)

        issue = %Issue{
          rule: :prefer_mapset_for_set_equality,
          message:
            "Using `Enum.uniq() |> Enum.sort()` for set equality is non-idiomatic. " <>
              "Use `MapSet.new/1` directly — it is semantically explicit and avoids " <>
              "unnecessary sort overhead.",
          meta: %{line: line}
        }

        {:ok, [issue]}

      :no ->
        :no
    end
  end

  defp check_block(_), do: :no

  # Recognise the exact safe shape and return the two inner String-call args.
  defp match_block([s1, s2, s3]) do
    with {:ok, name1, arg1} <- sorted_uniq_assignment(s1),
         {:ok, name2, arg2} <- sorted_uniq_assignment(s2),
         true <- name1 != name2,
         true <- compares?(s3, name1, name2) do
      {:ok, arg1, arg2}
    else
      _ -> :no
    end
  end

  defp match_block(_), do: :no

  # `var = String.codepoints(arg) |> Enum.uniq() |> Enum.sort()`
  # Returns {:ok, var_name, arg}.
  defp sorted_uniq_assignment({:=, _, [{name, _, ctx}, rhs]})
       when is_atom(name) and is_atom(ctx) do
    case sorted_uniq_pipeline(rhs) do
      {:ok, arg} -> {:ok, name, arg}
      :no -> :no
    end
  end

  defp sorted_uniq_assignment(_), do: :no

  # `string_list_call |> Enum.uniq() |> Enum.sort()` -> {:ok, string_list_call}
  defp sorted_uniq_pipeline(
         {:|>, _,
          [
            {:|>, _, [inner, {{:., _, [{:__aliases__, _, [:Enum]}, :uniq]}, _, []}]},
            {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, []}
          ]}
       ) do
    if string_list_call?(inner), do: {:ok, inner}, else: :no
  end

  defp sorted_uniq_pipeline(_), do: :no

  # `String.codepoints(arg)` or `String.graphemes(arg)` — both always return
  # lists of binaries, which never coerce under `==`.
  defp string_list_call?({{:., _, [{:__aliases__, _, [:String]}, fun]}, _, [_arg]})
       when fun in [:codepoints, :graphemes],
       do: true

  defp string_list_call?(_), do: false

  defp compares?({:==, _, [{a, _, _}, {b, _, _}]}, n1, n2)
       when is_atom(a) and is_atom(b) do
    (a == n1 and b == n2) or (a == n2 and b == n1)
  end

  defp compares?(_, _, _), do: false

  # Build: MapSet.new(arg1) == MapSet.new(arg2)
  defp make_mapset_eq(arg1, arg2) do
    {:==, [],
     [
       {{:., [], [{:__aliases__, [], [:MapSet]}, :new]}, [], [arg1]},
       {{:., [], [{:__aliases__, [], [:MapSet]}, :new]}, [], [arg2]}
     ]}
  end

  defp find_line(stmts) do
    Enum.find_value(stmts, 1, fn
      {_, meta, _} when is_list(meta) -> Keyword.get(meta, :line)
      _ -> nil
    end)
  end
end
