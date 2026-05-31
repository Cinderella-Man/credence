defmodule Credence.Pattern.AvoidCharlistEnumAtTest do
  use ExUnit.Case

  alias Credence.Pattern.AvoidCharlistEnumAt
  alias Credence.Issue

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    AvoidCharlistEnumAt.check(ast, [])
  end

  describe "check" do
    test "passes code using String.at directly" do
      code = """
      defmodule Good do
        def char_match?(s, i, j) do
          String.at(s, i) == String.at(s, j)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.at on a non-charlist variable" do
      code = """
      defmodule Good do
        def get(list, i) do
          Enum.at(list, i)
        end
      end
      """

      assert check(code) == []
    end

    test "detects Enum.at on a charlist variable" do
      code = """
      defmodule Bad do
        def char_eq?(s, i, j) do
          chars = String.to_charlist(s)
          Enum.at(chars, i) == Enum.at(chars, j)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.rule == :avoid_charlist_enum_at))
    end

    test "detects inline Enum.at(String.to_charlist(x), idx)" do
      code = """
      defmodule Bad do
        def first_char(s) do
          Enum.at(String.to_charlist(s), 0)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :avoid_charlist_enum_at
      assert issue.message =~ "String.at/2"
      assert issue.meta.line != nil
    end

    test "detects pipe: charlist_var |> Enum.at(idx)" do
      code = """
      defmodule Bad do
        def get_char(s, i) do
          chars = String.to_charlist(s)
          chars |> Enum.at(i)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :avoid_charlist_enum_at
    end

    test "detects charlist from piped String.to_charlist" do
      code = """
      defmodule Bad do
        def get_char(s, i) do
          chars = s |> String.to_charlist()
          Enum.at(chars, i)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :avoid_charlist_enum_at
    end

    test "does not fire on String.graphemes variable" do
      code = """
      defmodule Good do
        def get_char(s, i) do
          graphemes = String.graphemes(s)
          Enum.at(graphemes, i)
        end
      end
      """

      assert check(code) == []
    end

    test "reports line numbers" do
      code = """
      defmodule Bad do
        def char_eq?(s) do
          chars = String.to_charlist(s)
          Enum.at(chars, 0) == Enum.at(chars, 1)
        end
      end
      """

      issues = check(code)

      assert Enum.all?(issues, &(&1.meta.line != nil))
    end

    test "handles multiple charlist variables" do
      code = """
      defmodule Bad do
        def compare(s1, s2) do
          c1 = String.to_charlist(s1)
          c2 = String.to_charlist(s2)
          Enum.at(c1, 0) == Enum.at(c2, 0)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 2
    end
  end

  describe "fix_patches" do
    test "returns empty list (check-only rule)" do
      code = """
      chars = String.to_charlist(s)
      Enum.at(chars, 0)
      """

      ast = Sourceror.parse_string!(code)
      assert AvoidCharlistEnumAt.fix_patches(ast, source: code) == []
    end
  end
end
