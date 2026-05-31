defmodule Credence.Pattern.AvoidCharlistForIterationTest do
  use ExUnit.Case

  alias Credence.Pattern.AvoidCharlistForIteration
  alias Credence.Issue

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    AvoidCharlistForIteration.check(ast, [])
  end

  describe "check" do
    test "passes String.graphemes in a pipe" do
      code = """
      defmodule Good do
        def check(s) do
          s
          |> String.graphemes()
          |> process()
        end
      end
      """

      assert check(code) == []
    end

    test "passes String.to_charlist without a pipe (direct call)" do
      code = """
      defmodule Good do
        def check(s) do
          chars = String.to_charlist(s)
          :string.trim(chars)
        end
      end
      """

      assert check(code) == []
    end

    test "detects String.to_charlist in a simple pipe" do
      code = """
      defmodule Bad do
        def check(s) do
          s |> String.to_charlist() |> process()
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :avoid_charlist_for_iteration
      assert issue.message =~ "String.graphemes/1"
      assert issue.meta.line != nil
    end

    test "detects String.to_charlist in a multi-step pipe" do
      code = """
      defmodule Bad do
        def validparantheses(s) do
          s
          |> String.to_charlist()
          |> check_valid(0, false)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :avoid_charlist_for_iteration
    end

    test "detects String.to_charlist piped after other transforms" do
      code = """
      defmodule Bad do
        def check(s) do
          s
          |> String.downcase()
          |> String.to_charlist()
          |> process()
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :avoid_charlist_for_iteration
    end

    test "does not fire on Enum.at with charlist (handled by avoid_charlist_enum_at)" do
      code = """
      defmodule Good do
        def get(s, i) do
          chars = String.to_charlist(s)
          Enum.at(chars, i)
        end
      end
      """

      assert check(code) == []
    end

    test "reports line numbers" do
      code = """
      defmodule Bad do
        def check(s) do
          s |> String.to_charlist() |> process()
        end
      end
      """

      issues = check(code)

      assert Enum.all?(issues, &(&1.meta.line != nil))
    end

    test "detects multiple pipe usages" do
      code = """
      defmodule Bad do
        def check(s1, s2) do
          a = s1 |> String.to_charlist() |> process()
          b = s2 |> String.to_charlist() |> process()
          {a, b}
        end
      end
      """

      issues = check(code)

      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.rule == :avoid_charlist_for_iteration))
    end
  end

  describe "fix_patches" do
    test "returns empty list (check-only rule)" do
      code = """
      s |> String.to_charlist() |> process()
      """

      ast = Sourceror.parse_string!(code)
      assert AvoidCharlistForIteration.fix_patches(ast, source: code) == []
    end
  end
end
