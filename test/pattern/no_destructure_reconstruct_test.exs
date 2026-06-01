defmodule Credence.Pattern.NoDestructureReconstructTest do
  use ExUnit.Case

  alias Credence.Pattern.NoDestructureReconstruct

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoDestructureReconstruct.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoDestructureReconstruct, code, [])
  end

  describe "NoDestructureReconstruct" do
    test "detects destructure-reconstruct in case branch" do
      code = """
      defmodule Bad do
        def check(ip) do
          case String.split(ip, ".") do
            [p1, p2, p3, p4] ->
              Enum.all?([p1, p2, p3, p4], &valid_octet?/1)
            _ ->
              false
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_destructure_reconstruct

      assert issue.message =~ "p1"
      assert issue.message =~ "p4"
      assert issue.message =~ "reassembled"
    end

    test "detects with two variables" do
      code = """
      defmodule Bad do
        def swap(input) do
          case String.split(input, ":") do
            [a, b] -> Enum.join([a, b], "-")
            _ -> input
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "a, b"
    end

    test "detects with three variables" do
      code = """
      defmodule Bad do
        def process(data) do
          case data do
            [x, y, z] -> Enum.map([x, y, z], &to_string/1)
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "x, y, z"
    end

    test "detects in function head (def)" do
      code = """
      defmodule Bad do
        def process([a, b, c]) do
          Enum.map([a, b, c], &(&1 * 2))
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "a, b, c"
    end

    test "detects in function head (defp)" do
      code = """
      defmodule Bad do
        defp transform([first, second]) do
          Enum.join([first, second], ",")
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "first, second"
    end

    test "detects in guarded function head" do
      code = """
      defmodule Bad do
        def validate([a, b, c, d]) when is_binary(a) do
          Enum.all?([a, b, c, d], &is_binary/1)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "a, b, c, d"
    end

    test "detects when reconstructed list is nested in body" do
      code = """
      defmodule Bad do
        def check(input) do
          case String.split(input, ",") do
            [a, b, c] ->
              result = Enum.max([a, b, c])
              {:ok, result}
            _ ->
              :error
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "a, b, c"
    end

    # ---- Negative cases ----

    test "does not flag when variables are used individually" do
      code = """
      defmodule Good do
        def check(ip) do
          case String.split(ip, ".") do
            [p1, p2, p3, p4] ->
              {p1, p2, p3, p4}
            _ ->
              nil
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when bound as a whole with =" do
      code = """
      defmodule Good do
        def check(ip) do
          case String.split(ip, ".") do
            [_, _, _, _] = parts ->
              Enum.all?(parts, &valid_octet?/1)
            _ ->
              false
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when list order differs" do
      code = """
      defmodule Good do
        def reverse_pair(input) do
          case String.split(input, ":") do
            [a, b] -> Enum.join([b, a], ":")
            _ -> input
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when pattern contains literals" do
      code = """
      defmodule Good do
        def check(list) do
          case list do
            [1, b, c] -> Enum.sum([1, b, c])
            _ -> 0
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when pattern contains underscore variables" do
      code = """
      defmodule Good do
        def check(list) do
          case list do
            [_a, b, c] -> {b, c}
            _ -> nil
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag single-element list patterns" do
      code = """
      defmodule Good do
        def wrap(data) do
          case data do
            [x] -> Enum.map([x], &to_string/1)
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when pattern is not a list" do
      code = """
      defmodule Good do
        def check({a, b}) do
          Enum.max([a, b])
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when body list has different length" do
      code = """
      defmodule Good do
        def extend(input) do
          case String.split(input, ",") do
            [a, b] -> Enum.join([a, b, "extra"], ",")
            _ -> input
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag non-list function args" do
      code = """
      defmodule Good do
        def process(a, b, c) do
          Enum.map([a, b, c], &to_string/1)
        end
      end
      """

      assert check(code) == []
    end

    # ---- Cons pattern cases ----

    test "detects cons pattern reconstruction in function head" do
      code = """
      defmodule Bad do
        defp advance([h | t], list2) when h < 0 do
          advance(t, [h | t])
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
      cons_issue = Enum.find(issues, &(&1.message =~ "Cons"))
      assert cons_issue
      assert cons_issue.message =~ "h"
      assert cons_issue.message =~ "t"
    end

    test "detects cons pattern reconstruction in case branch" do
      code = """
      defmodule Bad do
        def process(data) do
          case data do
            [h | t] -> wrapper([h | t])
            _ -> :error
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
      cons_issue = Enum.find(issues, &(&1.message =~ "Cons"))
      assert cons_issue
      assert cons_issue.message =~ "h"
      assert cons_issue.message =~ "t"
    end

    test "detects multiple cons pattern reconstructions in one function" do
      code = """
      defmodule Bad do
        defp merge([h1 | t1], [h2 | t2]) when h1 < h2 do
          [h1 | merge(t1, [h2 | t2])]
        end
      end
      """

      issues = check(code)
      cons_issues = Enum.filter(issues, &(&1.message =~ "Cons"))
      # [h2 | t2] is reconstructed
      assert length(cons_issues) >= 1
      assert Enum.any?(cons_issues, &(&1.message =~ "h2"))
    end

    # ---- Cons pattern negative cases ----

    test "does not flag cons when head is used individually" do
      code = """
      defmodule Good do
        defp process([h | t]) do
          IO.puts(h)
          process(t)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag cons with different reconstruction" do
      code = """
      defmodule Good do
        defp transform([h | t]) do
          [transform(h) | t]
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag cons with underscore prefix" do
      code = """
      defmodule Good do
        defp skip([_h | t]) do
          wrapper([_h | t])
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag cons when tail is used individually" do
      code = """
      defmodule Good do
        defp process([h | t]) do
          result = hd(t)
          {h, result}
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag cons when same variable names appear in multiple args" do
      # When two function arguments destructure with the same variable names,
      # the fix would bind both to the same `list`, forcing arg1 == arg2.
      # This is a common pattern in recursive algorithms (e.g. LCS).
      code = """
      defmodule Good do
        defp do_lcs([c1 | rest1], [c2 | rest2]) do
          if c1 == c2 do
            1 + do_lcs(rest1, rest2)
          else
            max(
              do_lcs(rest1, [c2 | rest2]),
              do_lcs([c1 | rest1], rest2)
            )
          end
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix/2 — case branches" do
    test "replaces reconstructed list with binding variable" do
      code = """
      defmodule Bad do
        def check(ip) do
          case String.split(ip, ".") do
            [p1, p2, p3, p4] ->
              Enum.all?([p1, p2, p3, p4], &valid_octet?/1)
            _ ->
              false
          end
        end
      end
      """

      result = fix(code)

      # Should have = items binding on the pattern
      assert result =~ "= items"
      # The body should use items, not the reconstructed list
      assert result =~ "Enum.all?(items"
      # Individual vars unused → replaced with _ in pattern
      assert result =~ ~r/\[_, _, _, _\] = items/
    end

    test "fixes two-variable case" do
      code = """
      defmodule Bad do
        def swap(input) do
          case String.split(input, ":") do
            [a, b] -> Enum.join([a, b], "-")
            _ -> input
          end
        end
      end
      """

      result = fix(code)

      assert result =~ "= items"
      assert result =~ "Enum.join(items"
    end

    test "preserves other case branches" do
      code = """
      defmodule Bad do
        def check(ip) do
          case String.split(ip, ".") do
            [p1, p2, p3, p4] ->
              Enum.all?([p1, p2, p3, p4], &valid_octet?/1)
            _ ->
              false
          end
        end
      end
      """

      result = fix(code)

      assert result =~ "_ ->"
      assert result =~ "false"
    end
  end

  describe "fix/2 — function heads" do
    test "fixes def function head" do
      code = """
      defmodule Bad do
        def process([a, b, c]) do
          Enum.map([a, b, c], &(&1 * 2))
        end
      end
      """

      result = fix(code)

      assert result =~ "= items"
      assert result =~ "Enum.map(items"
    end

    test "fixes defp function head" do
      code = """
      defmodule Bad do
        defp transform([first, second]) do
          Enum.join([first, second], ",")
        end
      end
      """

      result = fix(code)

      assert result =~ "= items"
      assert result =~ "Enum.join(items"
    end

    test "fixes guarded function head" do
      code = """
      defmodule Bad do
        def validate([a, b, c, d]) when is_binary(a) do
          Enum.all?([a, b, c, d], &is_binary/1)
        end
      end
      """

      result = fix(code)

      assert result =~ "= items"
      assert result =~ "Enum.all?(items"
      # a is still used in the guard, so it stays in pattern
      assert result =~ ~r/\[a, _, _, _\] = items/
    end
  end

  describe "fix/2 — partial variable usage" do
    test "keeps individually-used variables, underscores the rest" do
      code = """
      defmodule Bad do
        def check(input) do
          case String.split(input, ",") do
            [a, b, c] ->
              Logger.info(a)
              Enum.max([a, b, c])
            _ ->
              :error
          end
        end
      end
      """

      result = fix(code)

      # a is still used individually (Logger.info), so stays bound
      assert result =~ ~r/\[a, _, _\] = items/
      assert result =~ "Logger.info(a)"
      assert result =~ "Enum.max(items"
    end

    test "keeps multiple individually-used variables" do
      code = """
      defmodule Bad do
        def run(data) do
          case data do
            [x, y, z] ->
              IO.puts(x)
              IO.puts(z)
              Enum.sum([x, y, z])
          end
        end
      end
      """

      result = fix(code)

      # x and z are used individually, y is not
      assert result =~ ~r/\[x, _, z\] = items/
      assert result =~ "Enum.sum(items"
    end
  end

  describe "fix/2 — cons patterns" do
    test "fixes cons pattern reconstruction in function head" do
      code = """
      defmodule Bad do
        defp advance([h | t], list2) when h < 0 do
          advance(t, [h | t])
        end
      end
      """

      result = fix(code)

      # Both h (guard) and t (body) are used individually,
      # so pattern stays but gets bound as a whole
      assert result =~ "[h | t] = list"
      # Body should use bound variable, not reconstructed cons
      assert result =~ "advance(t, list)"
    end

    test "fixes cons pattern keeping individually-used head" do
      code = """
      defmodule Bad do
        defp process([h | t]) when is_integer(h) do
          IO.puts(h)
          wrapper([h | t])
        end
      end
      """

      result = fix(code)

      # h is used individually, so it stays; t is only in reconstruction
      assert result =~ "= list"
      assert result =~ "IO.puts(h)"
      assert result =~ "wrapper(list)"
    end

    test "round-trip: fixed cons code produces zero issues" do
      code = """
      defmodule Bad do
        defp advance([h | t], list2) when h < 0 do
          advance(t, [h | t])
        end
      end
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert [] == NoDestructureReconstruct.check(ast, [])
    end

    test "round-trip: cons case branch fix produces zero issues" do
      code = """
      defmodule Bad do
        def process(data) do
          case data do
            [h | t] -> wrapper([h | t])
            _ -> :error
          end
        end
      end
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert [] == NoDestructureReconstruct.check(ast, [])
    end

    test "does not fix when same cons variables appear in multiple args" do
      code = """
      defmodule Good do
        defp do_lcs([c1 | rest1], [c2 | rest2]) do
          if c1 == c2 do
            1 + do_lcs(rest1, rest2)
          else
            max(
              do_lcs(rest1, [c2 | rest2]),
              do_lcs([c1 | rest1], rest2)
            )
          end
        end
      end
      """

      result = fix(code)

      # Should NOT introduce a `= list` binding
      refute result =~ "= list"
      # Original code should be preserved
      assert result =~ "[c1 | rest1]"
      assert result =~ "[c2 | rest2]"
    end
  end

  describe "fix/2 — edge cases" do
    test "returns valid code when nothing to fix" do
      code = """
      defmodule Good do
        def process(list) do
          Enum.map(list, &to_string/1)
        end
      end
      """

      result = fix(code)
      assert {:ok, _} = Sourceror.parse_string(result)
    end

    test "does not touch already-idiomatic code" do
      code = """
      defmodule Good do
        def check(ip) do
          case String.split(ip, ".") do
            [_, _, _, _] = parts ->
              Enum.all?(parts, &valid_octet?/1)
            _ ->
              false
          end
        end
      end
      """

      result = fix(code)

      assert result =~ "parts"
      refute result =~ "items"
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Bad do
        def check(ip) do
          case String.split(ip, ".") do
            [p1, p2, p3, p4] ->
              Enum.all?([p1, p2, p3, p4], &valid_octet?/1)
            _ ->
              false
          end
        end
      end
      """

      fixed = fix(code)
      assert {:ok, _} = Sourceror.parse_string(fixed)
    end

    test "round-trip: fixed code produces zero issues" do
      code = """
      defmodule Bad do
        def check(ip) do
          case String.split(ip, ".") do
            [p1, p2, p3, p4] ->
              Enum.all?([p1, p2, p3, p4], &valid_octet?/1)
            _ ->
              false
          end
        end
      end
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert [] == NoDestructureReconstruct.check(ast, [])
    end

    test "round-trip: function head fix produces zero issues" do
      code = """
      defmodule Bad do
        def process([a, b, c]) do
          Enum.map([a, b, c], &(&1 * 2))
        end
      end
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert [] == NoDestructureReconstruct.check(ast, [])
    end
  end
end
