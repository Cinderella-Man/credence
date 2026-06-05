defmodule Credence.Pattern.NoHdTlWhenConsBoundCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoHdTlWhenConsBound

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoHdTlWhenConsBound.check(ast, [])
  end

  describe "check — flags hd/tl on anonymous-cons-bound params" do
    test "flags hd(var) when var is bound as var = [_ | _]" do
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

    test "flags tl(var) when var is bound as var = [_ | _]" do
      code = """
      defmodule Bad do
        def rest(list = [_ | _]), do: tl(list)
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "tl(list)"
    end

    test "flags both hd and tl on the same cons-bound variable" do
      code = """
      defmodule Bad do
        def split(list = [_ | _]), do: {hd(list), tl(list)}
      end
      """

      assert length(check(code)) == 2
    end

    test "flags reversed cons binding [_ | _] = var" do
      code = """
      defmodule Bad do
        def first([_ | _] = list), do: hd(list)
      end
      """

      assert length(check(code)) == 1
    end

    test "flags hd/tl across two clauses with guards" do
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

      assert length(check(code)) == 4
    end

    test "still flags when the var is also used elsewhere (binding kept)" do
      code = """
      defmodule Bad do
        def first(list = [_ | _]), do: {hd(list), length(list)}
      end
      """

      assert length(check(code)) == 1
    end

    test "flags even when the natural name collides with another param" do
      code = """
      defmodule Bad do
        def first(list = [_ | _], head), do: hd(list) + head
      end
      """

      assert length(check(code)) == 1
    end
  end

  describe "check — deliberately not flagged (locks the safe-core choice)" do
    test "no issue for named cons pattern [head | tail] = var" do
      code = """
      defmodule Skip do
        def first([head | _tail] = list), do: hd(list)
      end
      """

      # Named cons already binds the parts; reusing/renaming those bindings is
      # outside the safe core, so this is left alone.
      assert check(code) == []
    end

    test "no issue for underscore-named cons pattern [_head | _tail] = var" do
      code = """
      defmodule Skip do
        def first([_head | _tail] = list), do: hd(list)
      end
      """

      assert check(code) == []
    end

    test "no issue when param is not cons-bound" do
      code = """
      defmodule Good do
        def first(list), do: hd(list)
      end
      """

      assert check(code) == []
    end

    test "no issue when already pattern matching in the head" do
      code = """
      defmodule Good do
        def first([head | _tail]), do: head
      end
      """

      assert check(code) == []
    end

    test "no issue for hd/tl on a non-parameter variable" do
      code = """
      defmodule Good do
        def first(list = [_ | _]) do
          other = [1, 2, 3]
          hd(other)
        end
      end
      """

      assert check(code) == []
    end

    test "no issue when the cons-bound var is never referenced" do
      code = """
      defmodule Good do
        def first([_ | _] = _list), do: :ok
      end
      """

      assert check(code) == []
    end

    test "no issue when the body rebinds with = (could shadow the var)" do
      code = """
      defmodule Skip do
        def first(list = [_ | _]) do
          list = process(list)
          hd(list)
        end
      end
      """

      assert check(code) == []
    end

    test "no issue when the body contains an anonymous fn (could shadow the var)" do
      code = """
      defmodule Skip do
        def first(list = [_ | _]), do: Enum.map([1], fn _ -> hd(list) end)
      end
      """

      assert check(code) == []
    end

    test "no issue when the body contains a case (could shadow the var)" do
      code = """
      defmodule Skip do
        def first(list = [_ | _]) do
          case list do
            list -> hd(list)
          end
        end
      end
      """

      assert check(code) == []
    end
  end
end
