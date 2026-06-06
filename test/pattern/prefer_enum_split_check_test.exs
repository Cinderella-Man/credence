defmodule Credence.Pattern.PreferEnumSplitCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.PreferEnumSplit

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    PreferEnumSplit.check(ast, [])
  end

  describe "fires on the safe core" do
    test "adjacent take/drop, same var, same literal count" do
      code = """
      defmodule Bad do
        def halves(list) do
          first = Enum.take(list, 3)
          rest = Enum.drop(list, 3)
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

    test "count literal of zero still fires" do
      code = """
      defmodule Bad do
        def halves(list) do
          a = Enum.take(list, 0)
          b = Enum.drop(list, 0)
          {a, b}
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "reports the issue at the Enum.drop line" do
      code = """
      defmodule LineCheck do
        def halves(list) do
          first = Enum.take(list, 3)
          rest = Enum.drop(list, 3)
          {first, rest}
        end
      end
      """

      issue = hd(check(code))
      assert issue.meta.line == 4
    end

    test "drop's bound var may equal the source var" do
      code = """
      defmodule Bad do
        def halves(list) do
          first = Enum.take(list, 3)
          list = Enum.drop(list, 3)
          {first, list}
        end
      end
      """

      assert length(check(code)) == 1
    end
  end

  describe "does NOT fire (already good / not the pattern)" do
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

    test "Enum.take alone" do
      code = """
      defmodule TakeOnly do
        def first_three(list) do
          Enum.take(list, 3)
        end
      end
      """

      assert check(code) == []
    end

    test "Enum.drop alone" do
      code = """
      defmodule DropOnly do
        def skip_three(list) do
          Enum.drop(list, 3)
        end
      end
      """

      assert check(code) == []
    end

    test "different enumerables" do
      code = """
      defmodule Different do
        def process(a, b) do
          first = Enum.take(a, 3)
          rest = Enum.drop(b, 3)
          {first, rest}
        end
      end
      """

      assert check(code) == []
    end

    test "different counts" do
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

    test "unbound take/drop calls" do
      code = """
      defmodule Unbound do
        def process(list) do
          Enum.take(list, 3)
          Enum.drop(list, 3)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "does NOT fire (deliberately dropped unsafe cases)" do
    test "variable count (sign unknown) is not flagged" do
      code = """
      defmodule VarCount do
        def halves(list, n) do
          first = Enum.take(list, n)
          rest = Enum.drop(list, n)
          {first, rest}
        end
      end
      """

      assert check(code) == []
    end

    test "negative literal count is not flagged" do
      code = """
      defmodule NegCount do
        def halves(list) do
          first = Enum.take(list, -3)
          rest = Enum.drop(list, -3)
          {first, rest}
        end
      end
      """

      assert check(code) == []
    end

    test "Enum.reverse(Enum.drop(...)) is not flagged" do
      code = """
      defmodule ReverseWrapped do
        def split_halves(sorted) do
          first_half = Enum.take(sorted, 3)
          last_half = Enum.reverse(Enum.drop(sorted, 3))
          {first_half, last_half}
        end
      end
      """

      assert check(code) == []
    end

    test "piped take/drop is not flagged" do
      code = """
      defmodule Piped do
        def halves(list) do
          first = list |> Enum.take(3)
          rest = list |> Enum.drop(3)
          {first, rest}
        end
      end
      """

      assert check(code) == []
    end

    test "non-adjacent take/drop is not flagged" do
      code = """
      defmodule NonAdjacent do
        def halves(list) do
          first = Enum.take(list, 3)
          mid = process(first)
          rest = Enum.drop(list, 3)
          {first, mid, rest}
        end
      end
      """

      assert check(code) == []
    end

    test "take rebinding the source (a == src) is not flagged" do
      code = """
      defmodule Rebind do
        def halves(list) do
          list = Enum.take(list, 3)
          rest = Enum.drop(list, 3)
          {list, rest}
        end
      end
      """

      assert check(code) == []
    end

    test "same bound var on both (a == b) is not flagged" do
      code = """
      defmodule SameVar do
        def halves(list) do
          x = Enum.take(list, 3)
          x = Enum.drop(list, 3)
          x
        end
      end
      """

      assert check(code) == []
    end
  end
end
