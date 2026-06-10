defmodule Credence.Pattern.AvoidLengthGuardLessThan2FixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.AvoidLengthGuardLessThan2

  describe "rewrites the anti-pattern" do
    test "length(list) < 2 with do: block" do
      input = """
      defmodule Example do
        def maximumdifference(list) when length(list) < 2, do: 0
        def maximumdifference([head | tail]) do
          do_maximumdifference(tail, head, 0)
        end
      end
      """

      expected = """
      defmodule Example do
        def maximumdifference([]), do: 0
        def maximumdifference([_]), do: 0
        def maximumdifference([head | tail]) do
          do_maximumdifference(tail, head, 0)
        end
      end
      """

      assert fix(AvoidLengthGuardLessThan2, input) == expected
    end

    test "length(list) <= 1 with do: block" do
      input = """
      defmodule Example do
        def process(list) when length(list) <= 1, do: :ok
      end
      """

      expected = """
      defmodule Example do
        def process([]), do: :ok
        def process([_]), do: :ok
      end
      """

      assert fix(AvoidLengthGuardLessThan2, input) == expected
    end

    test "2 > length(list) — reversed" do
      input = """
      defmodule Example do
        def process(list) when 2 > length(list), do: :ok
      end
      """

      expected = """
      defmodule Example do
        def process([]), do: :ok
        def process([_]), do: :ok
      end
      """

      assert fix(AvoidLengthGuardLessThan2, input) == expected
    end

    test "1 >= length(list) — reversed" do
      input = """
      defmodule Example do
        def process(list) when 1 >= length(list), do: :ok
      end
      """

      expected = """
      defmodule Example do
        def process([]), do: :ok
        def process([_]), do: :ok
      end
      """

      assert fix(AvoidLengthGuardLessThan2, input) == expected
    end

    test "defp variant" do
      input = """
      defmodule Example do
        defp process(list) when length(list) < 2, do: :ok
      end
      """

      expected = """
      defmodule Example do
        defp process([]), do: :ok
        defp process([_]), do: :ok
      end
      """

      assert fix(AvoidLengthGuardLessThan2, input) == expected
    end

    test "multi-line body" do
      input = """
      defmodule Example do
        def process(list) when length(list) < 2 do
          :empty_or_single
        end
      end
      """

      expected = """
      defmodule Example do
        def process([]) do
          :empty_or_single
        end

        def process([_]) do
          :empty_or_single
        end
      end
      """

      assert fix(AvoidLengthGuardLessThan2, input) == expected
    end
  end

  describe "no-ops" do
    test "length(list) < 3 passes through" do
      code = """
      defmodule Example do
        def process(list) when length(list) < 3, do: :ok
      end
      """

      assert fix(AvoidLengthGuardLessThan2, code) == code
    end

    test "no guard passes through" do
      code = """
      defmodule Example do
        def process(list), do: :ok
      end
      """

      assert fix(AvoidLengthGuardLessThan2, code) == code
    end

    test "already pattern-matched passes through" do
      code = """
      defmodule Example do
        def process([]), do: :ok
        def process([_]), do: :ok
      end
      """

      assert fix(AvoidLengthGuardLessThan2, code) == code
    end
  end

  describe "round-trip" do
    test "fixed code produces zero issues" do
      code = """
      defmodule Example do
        def maximumdifference(list) when length(list) < 2, do: 0
        def maximumdifference([head | tail]) do
          do_maximumdifference(tail, head, 0)
        end
      end
      """

      assert check(AvoidLengthGuardLessThan2, fix(AvoidLengthGuardLessThan2, code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def maximumdifference(list) when length(list) < 2, do: 0
        def maximumdifference([head | tail]) do
          do_maximumdifference(tail, head, 0)
        end
      end
      """

      assert valid_syntax?(fix(AvoidLengthGuardLessThan2, code))
    end
  end
end
