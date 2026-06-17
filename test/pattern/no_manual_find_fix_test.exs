defmodule Credence.Pattern.NoManualFindFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoManualFind

  describe "collapse to Enum.find/3" do
    test "arity 1 with a literal default" do
      code = """
      defmodule Bad do
        defp find_positive([]), do: -1
        defp find_positive([h | _t]) when h > 0, do: h
        defp find_positive([_h | t]), do: find_positive(t)
      end
      """

      expected = """
      defmodule Bad do
        defp find_positive(list) when is_list(list), do: Enum.find(list, -1, fn h -> h > 0 end)
      end
      """

      confirm_fix(fix(NoManualFind, code), expected)
    end

    test "arity 2 threading a default parameter" do
      code = """
      defmodule Bad do
        defp find_first([], default), do: default
        defp find_first([h | _t], _default) when h > 0, do: h
        defp find_first([_h | t], default), do: find_first(t, default)
      end
      """

      expected = """
      defmodule Bad do
        defp find_first(list, default) when is_list(list), do: Enum.find(list, default, fn h -> h > 0 end)
      end
      """

      confirm_fix(fix(NoManualFind, code), expected)
    end

    test "clauses in reversed order collapse at the first clause position" do
      code = """
      defmodule Bad do
        defp find([h | _t]) when h > 0, do: h
        defp find([_ | t]), do: find(t)
        defp find([]), do: nil
      end
      """

      expected = """
      defmodule Bad do
        defp find(list) when is_list(list), do: Enum.find(list, nil, fn h -> h > 0 end)
      end
      """

      confirm_fix(fix(NoManualFind, code), expected)
    end

    test "is_* guard over the head" do
      code = """
      defmodule Bad do
        defp first_atom([]), do: nil
        defp first_atom([h | _]) when is_atom(h), do: h
        defp first_atom([_ | t]), do: first_atom(t)
      end
      """

      expected = """
      defmodule Bad do
        defp first_atom(list) when is_list(list), do: Enum.find(list, nil, fn h -> is_atom(h) end)
      end
      """

      confirm_fix(fix(NoManualFind, code), expected)
    end

    test "compound boolean guard over the head" do
      code = """
      defmodule Bad do
        defp find([]), do: -1
        defp find([h | _]) when is_integer(h) and h > 0, do: h
        defp find([_ | t]), do: find(t)
      end
      """

      expected = """
      defmodule Bad do
        defp find(list) when is_list(list), do: Enum.find(list, -1, fn h -> is_integer(h) and h > 0 end)
      end
      """

      confirm_fix(fix(NoManualFind, code), expected)
    end

    test "public def" do
      code = """
      defmodule Bad do
        def find_positive([]), do: nil
        def find_positive([h | _]) when h > 0, do: h
        def find_positive([_ | t]), do: find_positive(t)
      end
      """

      expected = """
      defmodule Bad do
        def find_positive(list) when is_list(list), do: Enum.find(list, nil, fn h -> h > 0 end)
      end
      """

      confirm_fix(fix(NoManualFind, code), expected)
    end
  end

  describe "idempotency and no-ops" do
    test "the collapsed output is left unchanged on a second pass" do
      code = """
      defmodule Bad do
        defp find_positive(list) when is_list(list), do: Enum.find(list, -1, fn h -> h > 0 end)
      end
      """

      confirm_fix(fix(NoManualFind, code), code)
    end

    test "leaves a raising guard untouched" do
      code = """
      defmodule Good do
        defp find_odd([]), do: -1
        defp find_odd([h | _t]) when rem(h, 2) != 0, do: h
        defp find_odd([_h | t]), do: find_odd(t)
      end
      """

      confirm_fix(fix(NoManualFind, code), code)
    end

    test "leaves a guard referencing the second parameter untouched" do
      code = """
      defmodule Good do
        defp find([], _target), do: nil
        defp find([h | _], target) when h == target, do: h
        defp find([_ | t], target), do: find(t, target)
      end
      """

      confirm_fix(fix(NoManualFind, code), code)
    end

    test "leaves an existing Enum.find/3 call untouched" do
      code = """
      defmodule Good do
        def find_odd(list), do: Enum.find(list, -1, &(rem(&1, 2) != 0))
      end
      """

      confirm_fix(fix(NoManualFind, code), code)
    end
  end
end
