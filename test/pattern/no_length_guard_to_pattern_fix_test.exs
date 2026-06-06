defmodule Credence.Pattern.NoLengthGuardToPatternFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoLengthGuardToPattern

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoLengthGuardToPattern.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoLengthGuardToPattern, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "NoLengthGuardToPattern fix" do
    test "fixes length(list) > 0 into [_ | _] = list pattern" do
      input = """
      defmodule Example do
        def process(list) when length(list) > 0 do
          Enum.sum(list)
        end
      end
      """

      expected = """
      defmodule Example do
        def process([_ | _] = list) do
          Enum.sum(list)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes length(list) == 1 into [_] = list pattern" do
      input = """
      defmodule Example do
        def singleton(list) when length(list) == 1 do
          hd(list)
        end
      end
      """

      expected = """
      defmodule Example do
        def singleton([_] = list) do
          hd(list)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes length(list) == 3 into [_, _, _] = list pattern" do
      input = """
      defmodule Example do
        defp triplet(list) when length(list) == 3 do
          List.to_tuple(list)
        end
      end
      """

      expected = """
      defmodule Example do
        defp triplet([_, _, _] = list) do
          List.to_tuple(list)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes length(list) == 5 into [_, _, _, _, _] = list pattern" do
      input = """
      defmodule Example do
        def five(list) when length(list) == 5 do
          :ok
        end
      end
      """

      expected = """
      defmodule Example do
        def five([_, _, _, _, _] = list) do
          :ok
        end
      end
      """

      assert fix(input) == expected
    end

    test "preserves remaining guard in compound expression" do
      input = """
      defmodule Example do
        def process(list, x) when length(list) > 0 and is_integer(x) do
          :ok
        end
      end
      """

      expected = """
      defmodule Example do
        def process([_ | _] = list, x) when is_integer(x) do
          :ok
        end
      end
      """

      assert fix(input) == expected
    end

    test "preserves remaining guard when length check is on the right of and" do
      input = """
      defmodule Example do
        def process(list, x) when is_atom(x) and length(list) > 0 do
          :ok
        end
      end
      """

      expected = """
      defmodule Example do
        def process([_ | _] = list, x) when is_atom(x) do
          :ok
        end
      end
      """

      assert fix(input) == expected
    end

    test "does not modify when variable is not a direct parameter" do
      code = """
      defmodule Example do
        def process(%{items: list}) when length(list) > 0 do
          :ok
        end
      end
      """

      # Cannot fix — list is nested inside a map pattern, not a top-level param.
      assert fix(code) == code
    end

    test "does not modify length(list) == N for N > 5" do
      code = """
      defmodule Example do
        def check(list) when length(list) == 6 do
          :ok
        end
      end
      """

      assert fix(code) == code
    end

    test "does not modify unfixable patterns like k <= length(nums)" do
      code = """
      defmodule Example do
        def check(nums, k) when k <= length(nums) do
          :ok
        end
      end
      """

      assert fix(code) == code
    end

    test "fixed code has no remaining issues for > 0" do
      code = """
      defmodule Example do
        def process(list) when length(list) > 0 do
          Enum.sum(list)
        end
      end
      """

      assert check(fix(code)) == []
    end

    test "fixed code has no remaining issues for == N" do
      code = """
      defmodule Example do
        defp triplet(list) when length(list) == 3 do
          List.to_tuple(list)
        end
      end
      """

      assert check(fix(code)) == []
    end
  end
end
