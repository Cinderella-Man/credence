defmodule Credence.Pattern.PreferEnumSplitTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.PreferEnumSplit

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    PreferEnumSplit.check(ast, [])
  end

  describe "does NOT fire on good code" do
    test "code that already uses Enum.split" do
      code = """
      defmodule Good do
        def halves(list) do
          {first, rest} = Enum.split(list, 3)
          {first, rest}
        end
      end
      """

      assert check(code) == []
    end

    test "Enum.take alone without Enum.drop" do
      code = """
      defmodule TakeOnly do
        def first_three(list) do
          Enum.take(list, 3)
        end
      end
      """

      assert check(code) == []
    end

    test "Enum.drop alone without Enum.take" do
      code = """
      defmodule DropOnly do
        def skip_three(list) do
          Enum.drop(list, 3)
        end
      end
      """

      assert check(code) == []
    end

    test "Enum.take and Enum.drop on different enumerables" do
      code = """
      defmodule Different do
        def process(a, b, n) do
          first = Enum.take(a, n)
          rest = Enum.drop(b, n)
          {first, rest}
        end
      end
      """

      assert check(code) == []
    end

    test "Enum.take and Enum.drop with different counts" do
      code = """
      defmodule DifferentCounts do
        def process(list) do
          first = Enum.take(list, 3)
          rest = Enum.drop(list, 5)
          {first, rest}
        end
      end
      """

      assert check(code) == []
    end

    test "unbound Enum.take and Enum.drop calls" do
      code = """
      defmodule Unbound do
        def process(list, n) do
          Enum.take(list, n)
          Enum.drop(list, n)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fires on bad code" do
    test "detects separate Enum.take and Enum.drop on same list" do
      code = """
      defmodule Bad do
        def halves(list, n) do
          first = Enum.take(list, n)
          rest = Enum.drop(list, n)
          {first, rest}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :prefer_enum_split
      assert issue.message =~ "Enum.split"
    end

    test "detects Enum.drop wrapped in Enum.reverse" do
      code = """
      defmodule ReverseWrapped do
        def split_halves(sorted, count) do
          first_half = Enum.take(sorted, count)
          last_half = Enum.reverse(Enum.drop(sorted, count))
          {first_half, last_half}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :prefer_enum_split
    end

    test "detects piped Enum.take and Enum.drop" do
      code = """
      defmodule Piped do
        def halves(list, n) do
          first = list |> Enum.take(n)
          rest = list |> Enum.drop(n)
          {first, rest}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :prefer_enum_split
    end

    test "detects pattern with integer literal count" do
      code = """
      defmodule LiteralCount do
        def halves(list) do
          first = Enum.take(list, 5)
          rest = Enum.drop(list, 5)
          {first, rest}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :prefer_enum_split
    end

    test "reports issue at the Enum.drop line" do
      code = """
      defmodule LineCheck do
        def halves(list, n) do
          first = Enum.take(list, n)
          rest = Enum.drop(list, n)
          {first, rest}
        end
      end
      """

      issues = check(code)
      issue = hd(issues)
      assert issue.meta.line != nil
    end
  end

  describe "fix_patches/2" do
    test "returns empty list (check-only rule)" do
      code = """
      first = Enum.take(list, n)
      rest = Enum.drop(list, n)
      """

      ast = Sourceror.parse_string!(code)
      assert PreferEnumSplit.fix_patches(ast, source: code) == []
    end
  end
end
