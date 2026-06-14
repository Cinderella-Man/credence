defmodule Credence.Pattern.NoHdTlWhenConsBoundFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoHdTlWhenConsBound

  describe "fix — rewrites hd/tl to head/tail destructuring" do
    test "hd only collapses the binding" do
      code = """
      defmodule M do
        def first(list = [_ | _]), do: hd(list)
      end
      """

      expected = """
      defmodule M do
        def first([head | _]), do: head
      end
      """

      confirm_fix(fix(NoHdTlWhenConsBound, code), expected)
    end

    test "tl only collapses the binding" do
      code = """
      defmodule M do
        def rest(list = [_ | _]), do: tl(list)
      end
      """

      expected = """
      defmodule M do
        def rest([_ | tail]), do: tail
      end
      """

      confirm_fix(fix(NoHdTlWhenConsBound, code), expected)
    end

    test "both hd and tl" do
      code = """
      defmodule M do
        def split(list = [_ | _]), do: {hd(list), tl(list)}
      end
      """

      expected = """
      defmodule M do
        def split([head | tail]), do: {head, tail}
      end
      """

      confirm_fix(fix(NoHdTlWhenConsBound, code), expected)
    end

    test "reversed cons binding [_ | _] = var" do
      code = """
      defmodule M do
        def first([_ | _] = list), do: hd(list)
      end
      """

      expected = """
      defmodule M do
        def first([head | _]), do: head
      end
      """

      confirm_fix(fix(NoHdTlWhenConsBound, code), expected)
    end

    test "keeps the binding when the var is used elsewhere in the body" do
      code = """
      defmodule M do
        def first(list = [_ | _]), do: {hd(list), length(list)}
      end
      """

      expected = """
      defmodule M do
        def first(list = [head | _]), do: {head, length(list)}
      end
      """

      confirm_fix(fix(NoHdTlWhenConsBound, code), expected)
    end

    test "keeps the binding when the var is used in a guard" do
      code = """
      defmodule M do
        def g(list = [_ | _]) when length(list) > 2, do: hd(list)
      end
      """

      expected = """
      defmodule M do
        def g(list = [head | _]) when length(list) > 2, do: head
      end
      """

      confirm_fix(fix(NoHdTlWhenConsBound, code), expected)
    end

    test "merge: rewrites the flagged param, keeps the other, keeps guard binding" do
      code = """
      defmodule M do
        def m(l1 = [_ | _], l2 = [_ | _]) when l1 >= l2 do
          [hd(l1) | m(tl(l1), l2)]
        end
      end
      """

      expected = """
      defmodule M do
        def m(l1 = [head | tail], l2 = [_ | _]) when l1 >= l2 do
          [head | m(tail, l2)]
        end
      end
      """

      confirm_fix(fix(NoHdTlWhenConsBound, code), expected)
    end

    test "picks a fresh name when the natural one collides with another param" do
      code = """
      defmodule M do
        def first(list = [_ | _], head), do: hd(list) + head
      end
      """

      expected = """
      defmodule M do
        def first([head1 | _], head), do: head1 + head
      end
      """

      confirm_fix(fix(NoHdTlWhenConsBound, code), expected)
    end
  end

  describe "fix — leaves non-core shapes untouched" do
    test "no-op for named cons pattern" do
      code = """
      defmodule M do
        def first([_head | _tail] = list), do: hd(list)
      end
      """

      confirm_fix(fix(NoHdTlWhenConsBound, code), code)
    end

    test "no-op when not cons-bound" do
      code = """
      defmodule M do
        def first(list), do: hd(list)
      end
      """

      confirm_fix(fix(NoHdTlWhenConsBound, code), code)
    end

    test "no-op when the body rebinds the var" do
      code = """
      defmodule M do
        def first(list = [_ | _]) do
          list = process(list)
          hd(list)
        end
      end
      """

      confirm_fix(fix(NoHdTlWhenConsBound, code), code)
    end

    test "no-op when the body contains an anonymous fn" do
      code = """
      defmodule M do
        def first(list = [_ | _]), do: Enum.map([1], fn _ -> hd(list) end)
      end
      """

      confirm_fix(fix(NoHdTlWhenConsBound, code), code)
    end
  end
end
