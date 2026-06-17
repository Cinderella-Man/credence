defmodule Credence.Pattern.NoListFoldlFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoListFoldl, as: Rule

  test "rewrites direct List.foldl on a literal list" do
    confirm_fix(
      fix(Rule, "List.foldl([1, 2, 3], 0, fn x, acc -> x + acc end)"),
      "Enum.reduce([1, 2, 3], 0, fn x, acc -> x + acc end)"
    )
  end

  test "rewrites a direct list-returning-call argument" do
    confirm_fix(
      fix(Rule, "List.foldl(Map.keys(m), [], fn k, acc -> [k | acc] end)"),
      "Enum.reduce(Map.keys(m), [], fn k, acc -> [k | acc] end)"
    )
  end

  test "rewrites piped List.foldl on a list-returning step" do
    confirm_fix(
      fix(Rule, "nums |> Enum.filter(&(&1 > 0)) |> List.foldl(0, fn x, acc -> x + acc end)"),
      "nums |> Enum.filter(&(&1 > 0)) |> Enum.reduce(0, fn x, acc -> x + acc end)"
    )
  end

  test "leaves a bare-variable argument unchanged" do
    code = "List.foldl(list, 0, fn x, acc -> x + acc end)"
    confirm_fix(fix(Rule, code), code)
  end

  test "leaves a range argument unchanged" do
    code = "List.foldl(1..3, 0, fn x, acc -> x + acc end)"
    confirm_fix(fix(Rule, code), code)
  end
end
