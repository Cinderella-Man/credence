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

      confirm_fix(fix(AvoidLengthGuardLessThan2, input), expected)
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

      confirm_fix(fix(AvoidLengthGuardLessThan2, input), expected)
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

      confirm_fix(fix(AvoidLengthGuardLessThan2, input), expected)
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

      confirm_fix(fix(AvoidLengthGuardLessThan2, input), expected)
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

      confirm_fix(fix(AvoidLengthGuardLessThan2, input), expected)
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

      confirm_fix(fix(AvoidLengthGuardLessThan2, input), expected)
    end
  end

  describe "no-ops" do
    test "length(list) < 3 passes through" do
      code = """
      defmodule Example do
        def process(list) when length(list) < 3, do: :ok
      end
      """

      confirm_fix(fix(AvoidLengthGuardLessThan2, code), code)
    end

    test "no guard passes through" do
      code = """
      defmodule Example do
        def process(list), do: :ok
      end
      """

      confirm_fix(fix(AvoidLengthGuardLessThan2, code), code)
    end

    test "already pattern-matched passes through" do
      code = """
      defmodule Example do
        def process([]), do: :ok
        def process([_]), do: :ok
      end
      """

      confirm_fix(fix(AvoidLengthGuardLessThan2, code), code)
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

  # Regression (row 101469): when the body references the guarded variable, the
  # split clauses must BIND it (`[] = var`) — bare `[]`/`[_]` left it unbound and
  # the fix was reverted as non-compiling. A multi-line block body must also
  # survive (it used to mis-render into a broken one-liner).
  describe "preserves the variable when the body uses it" do
    test "binds the variable for a block body that references it" do
      input = """
      defmodule Example do
        def two(items) when length(items) < 2 do
          Enum.reverse(items)
        end
      end
      """

      expected = """
      defmodule Example do
        def two([] = items) do
          Enum.reverse(items)
        end

        def two([_] = items) do
          Enum.reverse(items)
        end
      end
      """

      confirm_fix(fix(AvoidLengthGuardLessThan2, input), expected)
    end

    test "does not add a binding when the body ignores the variable" do
      input = """
      defmodule Example do
        def f(list) when length(list) < 2, do: 0
      end
      """

      expected = """
      defmodule Example do
        def f([]), do: 0
        def f([_]), do: 0
      end
      """

      confirm_fix(fix(AvoidLengthGuardLessThan2, input), expected)
    end
  end

  describe "parameters containing the guarded variable" do
    test "rewrites a guarded variable nested in a parameter pattern" do
      input = """
      defmodule AvoidLengthNestedParameter do
        def f({list}) when length(list) < 2, do: :ok
      end
      """

      expected = """
      defmodule AvoidLengthNestedParameter do
        def f({[]}), do: :ok
        def f({[_]}), do: :ok
      end
      """

      confirm_fix(fix(AvoidLengthGuardLessThan2, input), expected)
    end

    test "keeps repeated occurrences of the guarded parameter equal" do
      input = """
      defmodule AvoidLengthRepeatedParameter do
        def f(list, list) when length(list) < 2, do: :ok
      end
      """

      expected = """
      defmodule AvoidLengthRepeatedParameter do
        def f([] = list, list), do: :ok
        def f([_] = list, list), do: :ok
      end
      """

      fixed = fix(AvoidLengthGuardLessThan2, input)
      confirm_fix(fixed, expected)
      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(fixed)
    end
  end
end
