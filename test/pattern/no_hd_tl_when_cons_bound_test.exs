defmodule Credence.Pattern.NoHdTlWhenConsBoundTest do
  use ExUnit.Case

  alias Credence.Pattern.NoHdTlWhenConsBound

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoHdTlWhenConsBound.check(ast, [])
  end

  describe "check" do
    # --- POSITIVE CASES ---

    test "flags hd(var) when var is bound as var = [_ | _] in function head" do
      code = """
      defmodule Bad do
        def first(list = [_ | _]), do: hd(list)
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_hd_tl_when_cons_bound
      assert hd(issues).message =~ "hd(list)"
    end

    test "flags tl(var) when var is bound as var = [_ | _] in function head" do
      code = """
      defmodule Bad do
        def rest(list = [_ | _]), do: tl(list)
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_hd_tl_when_cons_bound
      assert hd(issues).message =~ "tl(list)"
    end

    test "flags both hd and tl on the same cons-bound variable" do
      code = """
      defmodule Bad do
        def split(list = [_ | _]), do: {hd(list), tl(list)}
      end
      """

      issues = check(code)
      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.rule == :no_hd_tl_when_cons_bound))
    end

    test "flags hd/tl on different cons-bound params with guard" do
      code = """
      defmodule Bad do
        def merge(list1 = [_ | _], list2 = [_ | _]) when list1 >= list2 do
          [hd(list1) | merge(tl(list1), list2)]
        end

        def merge(list1 = [_ | _], list2 = [_ | _]) do
          [hd(list2) | merge(list1, tl(list2))]
        end
      end
      """

      issues = check(code)
      # Clause 1: hd(list1) + tl(list1) = 2
      # Clause 2: hd(list2) + tl(list2) = 2
      assert length(issues) == 4
      assert Enum.all?(issues, &(&1.rule == :no_hd_tl_when_cons_bound))
    end

    test "flags reversed cons binding [_ | _] = var" do
      code = """
      defmodule Bad do
        def first([_ | _] = list), do: hd(list)
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_hd_tl_when_cons_bound
    end

    test "flags hd/tl when cons pattern has named bindings" do
      code = """
      defmodule Bad do
        def first([_head | _tail] = list), do: hd(list)
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_hd_tl_when_cons_bound
    end

    # --- NEGATIVE CASES ---

    test "does not flag hd/1 when param is not cons-bound" do
      code = """
      defmodule Good do
        def first(list), do: hd(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag tl/1 when param is not cons-bound" do
      code = """
      defmodule Good do
        def rest(list), do: tl(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag when already using pattern matching" do
      code = """
      defmodule Good do
        def first([head | _tail]), do: head
        def split([head | tail]), do: {head, tail}
      end
      """

      assert check(code) == []
    end

    test "does not flag hd/tl on non-parameter variables" do
      code = """
      defmodule Good do
        def first(list) do
          other = [1, 2, 3]
          hd(other)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag hd/tl when the cons-bound var is not referenced" do
      code = """
      defmodule Good do
        def first([head | _tail] = _list), do: head
      end
      """

      assert check(code) == []
    end
  end
end
