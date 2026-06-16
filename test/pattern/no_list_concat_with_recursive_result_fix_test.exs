defmodule Credence.Pattern.NoListConcatWithRecursiveResultFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoListConcatWithRecursiveResult

  describe "rewrites [literal] ++ recursive_result to a cons" do
    test "single-element literal ++ direct self-call" do
      code = """
      defmodule Bad do
        def build([]), do: []

        def build([h | t]) do
          [h] ++ build(t)
        end
      end
      """

      expected = """
      defmodule Bad do
        def build([]), do: []

        def build([h | t]) do
          [h | build(t)]
        end
      end
      """

      confirm_fix(fix(NoListConcatWithRecursiveResult, code), expected)
    end

    test "multi-element literal ++ self-call on a single-line clause" do
      code = """
      defmodule Bad do
        def pre([]), do: []
        def pre([h | t]), do: [h, h * 2] ++ pre(t)
      end
      """

      expected = """
      defmodule Bad do
        def pre([]), do: []
        def pre([h | t]), do: [h, h * 2 | pre(t)]
      end
      """

      confirm_fix(fix(NoListConcatWithRecursiveResult, code), expected)
    end

    test "literal ++ variable bound to a recursive call" do
      code = """
      defmodule Bad do
        def build([]), do: []

        def build([h | t]) do
          rest = build(t)
          [h] ++ rest
        end
      end
      """

      expected = """
      defmodule Bad do
        def build([]), do: []

        def build([h | t]) do
          rest = build(t)
          [h | rest]
        end
      end
      """

      confirm_fix(fix(NoListConcatWithRecursiveResult, code), expected)
    end

    test "fixes only the literal-prefix clause, leaves the others" do
      code = """
      defmodule Bad do
        defp flatten([], acc), do: acc

        defp flatten([h | t], acc) when is_list(h) do
          rest = flatten(t, acc)
          flatten(h, []) ++ rest
        end

        defp flatten([h | t], acc) do
          rest = flatten(t, acc)
          [h] ++ rest
        end
      end
      """

      expected = """
      defmodule Bad do
        defp flatten([], acc), do: acc

        defp flatten([h | t], acc) when is_list(h) do
          rest = flatten(t, acc)
          flatten(h, []) ++ rest
        end

        defp flatten([h | t], acc) do
          rest = flatten(t, acc)
          [h | rest]
        end
      end
      """

      confirm_fix(fix(NoListConcatWithRecursiveResult, code), expected)
    end
  end

  describe "no-ops (dropped shapes are not touched)" do
    test "computed variable ++ recursive result unchanged" do
      code = """
      defmodule Safe do
        defp substrings(string, count, start_index) when start_index >= count, do: []

        defp substrings(string, count, start_index) do
          current =
            for len <- 1..(count - start_index) do
              String.slice(string, start_index, len)
            end

          rest = substrings(string, count, start_index + 1)
          current ++ rest
        end
      end
      """

      confirm_fix(fix(NoListConcatWithRecursiveResult, code), code)
    end

    test "recursive_result ++ [literal] unchanged" do
      code = """
      defmodule Safe do
        def build([]), do: []

        def build([h | t]) do
          build(t) ++ [h]
        end
      end
      """

      confirm_fix(fix(NoListConcatWithRecursiveResult, code), code)
    end

    test "empty list literal ++ recursive result unchanged" do
      code = """
      defmodule Safe do
        def build([]), do: []

        def build([_h | t]) do
          [] ++ build(t)
        end
      end
      """

      confirm_fix(fix(NoListConcatWithRecursiveResult, code), code)
    end
  end

  describe "round-trip" do
    test "fixed code produces zero issues" do
      code = """
      defmodule Bad do
        def build([]), do: []
        def build([h | t]), do: [h, h * 2] ++ build(t)
      end
      """

      assert check(NoListConcatWithRecursiveResult, fix(NoListConcatWithRecursiveResult, code)) ==
               []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Bad do
        def build([]), do: []
        def build([h | t]), do: [h] ++ build(t)
      end
      """

      assert valid_syntax?(fix(NoListConcatWithRecursiveResult, code))
    end
  end
end
