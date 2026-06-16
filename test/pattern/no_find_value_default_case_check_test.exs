defmodule Credence.Pattern.NoFindValueDefaultCaseCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoFindValueDefaultCase

  describe "flags the safe core" do
    test "case Enum.find_value/2 with nil -> default; val -> val" do
      code = """
      case Enum.find_value(list, &process/1) do
        nil -> :default
        val -> val
      end
      """

      issues = check(NoFindValueDefaultCase, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_find_value_default_case
    end

    test "Enum.find_value/2 || default" do
      code = "Enum.find_value(list, &process/1) || :default"

      issues = check(NoFindValueDefaultCase, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_find_value_default_case
    end

    test "piped case: Enum.find_value/2 |> case do" do
      code = """
      Enum.find_value(list, &process/1)
      |> case do
        nil -> :default
        val -> val
      end
      """

      issues = check(NoFindValueDefaultCase, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_find_value_default_case
    end

    test "1-arg pipe case: coll |> Enum.find_value(fun) |> case do" do
      code = """
      list
      |> Enum.find_value(fun)
      |> case do
        nil -> :default
        val -> val
      end
      """

      issues = check(NoFindValueDefaultCase, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_find_value_default_case
    end
  end

  describe "does not flag — unsafe / out of scope" do
    # Reversed clause order: `val -> val` matches nil too, so `nil -> d` is
    # dead code and the expression returns nil (never the default). Rewriting
    # to /3 would change the answer.
    test "reversed clauses (identity first) is NOT flagged" do
      code = """
      case Enum.find_value(list, fun) do
        val -> val
        nil -> :default
      end
      """

      assert check(NoFindValueDefaultCase, code) == []
    end

    # Enum.find/2 returns the matching element, which can be nil — so the
    # nil-check cannot distinguish "found nil" from "not found". Not covered.
    test "case Enum.find/2 nil-identity is NOT flagged" do
      code = """
      case Enum.find(list, &valid?/1) do
        nil -> :not_found
        val -> val
      end
      """

      assert check(NoFindValueDefaultCase, code) == []
    end

    test "Enum.find/2 || default is NOT flagged" do
      code = "Enum.find(list, &valid?/1) || :not_found"

      assert check(NoFindValueDefaultCase, code) == []
    end

    test "piped Enum.find/2 case is NOT flagged" do
      code = """
      Enum.find(list, &valid?/1)
      |> case do
        nil -> :not_found
        val -> val
      end
      """

      assert check(NoFindValueDefaultCase, code) == []
    end

    # Tuple-extraction (find/2 -> find_value/3 with extracted element) is
    # unsafe: a falsy extracted value would fall through to the default.
    test "Enum.find/2 with tuple extraction is NOT flagged" do
      code = """
      case Enum.find(scores, fn {_k, v} -> v == target end) do
        {key, _} -> key
        nil -> -1
      end
      """

      assert check(NoFindValueDefaultCase, code) == []
    end

    test "Enum.find_value/3 (already has default) is NOT flagged" do
      code = """
      case Enum.find_value(list, :default, &process/1) do
        nil -> :other
        val -> val
      end
      """

      assert check(NoFindValueDefaultCase, code) == []
    end

    test "non-identity body is NOT flagged" do
      code = """
      case Enum.find_value(list, &process/1) do
        nil -> :default
        val -> transform(val)
      end
      """

      assert check(NoFindValueDefaultCase, code) == []
    end

    test "missing nil clause is NOT flagged" do
      code = """
      case Enum.find_value(list, &process/1) do
        :not_found -> :default
        val -> val
      end
      """

      assert check(NoFindValueDefaultCase, code) == []
    end

    test "bare Enum.find_value/2 without nil check is NOT flagged" do
      code = "Enum.find_value(list, &process/1)"

      assert check(NoFindValueDefaultCase, code) == []
    end

    test "bare Enum.find/2 without nil check is NOT flagged" do
      code = "Enum.find(list, &valid?/1)"

      assert check(NoFindValueDefaultCase, code) == []
    end
  end
end
