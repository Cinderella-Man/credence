defmodule Credence.Pattern.NoListConcatWithRecursiveResultTest do
  use ExUnit.Case

  alias Credence.Pattern.NoListConcatWithRecursiveResult

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoListConcatWithRecursiveResult.check(ast, [])
  end

  describe "NoListConcatWithRecursiveResult check" do
    # --- POSITIVE CASES ---

    test "flags computed list ++ recursive result via variable binding" do
      code = """
      defmodule Bad do
        defp substrings(string, count, start_index) when start_index >= count, do: []

        defp substrings(string, count, start_index) do
          max_length = count - start_index

          current =
            for len <- 1..max_length do
              String.slice(string, start_index, len)
            end

          rest = substrings(string, count, start_index + 1)
          current ++ rest
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_concat_with_recursive_result
      assert hd(issues).message =~ "++"
    end

    test "flags direct self_call ++ expr" do
      code = """
      defmodule Bad do
        def build([]), do: []

        def build([h | t]) do
          build(t) ++ [h]
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_concat_with_recursive_result
    end

    test "flags expr ++ direct self_call" do
      code = """
      defmodule Bad do
        def build([]), do: []

        def build([h | t]) do
          [h] ++ build(t)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "flags guarded recursive clause with concat" do
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

      issues = check(code)
      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.rule == :no_list_concat_with_recursive_result))
    end

    test "flags the exact pattern from row 44196 (generate_substrings)" do
      code = """
      defmodule Solution do
        def generate_substrings(string) do
          case string do
            "" -> []
            _ -> generate_substrings_recursive(string, String.length(string), 0, [])
          end
        end

        defp generate_substrings_recursive(_string, count, start_index, _accumulator)
             when start_index >= count, do: []

        defp generate_substrings_recursive(string, count, start_index, _accumulator) do
          max_length = count - start_index

          substrings_from_start =
            for count <- 1..max_length do
              String.slice(string, start_index, count)
            end

          next_substrings = generate_substrings_recursive(string, count, start_index + 1, [])
          substrings_from_start ++ next_substrings
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_concat_with_recursive_result
    end

    # --- NEGATIVE CASES ---

    test "does not flag non-recursive function" do
      code = """
      defmodule Safe do
        def combine(a, b), do: a ++ b
      end
      """

      assert check(code) == []
    end

    test "does not flag recursive function without ++ in return" do
      code = """
      defmodule Safe do
        def build([]), do: []
        def build([h | t]), do: [h | build(t)]
      end
      """

      assert check(code) == []
    end

    test "does not flag ++ with no recursive operand" do
      code = """
      defmodule Safe do
        def process(list) do
          _result = process(tl(list))
          [1, 2, 3] ++ [4, 5, 6]
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag acc ++ [expr] in tail-call position" do
      code = """
      defmodule Safe do
        def build([h | t], acc), do: build(t, acc ++ [h])
        def build([], acc), do: acc
      end
      """

      # This pattern is handled by no_list_append_in_recursion
      assert check(code) == []
    end

    test "does not flag idiomatic recursive prepend" do
      code = """
      defmodule Safe do
        def build([]), do: []
        def build([h | t]), do: [h * 2 | build(t)]
      end
      """

      assert check(code) == []
    end

    test "does not flag ++ in non-return position of recursive function" do
      code = """
      defmodule Safe do
        def process([]), do: []

        def process([h | t]) do
          combined = [h] ++ [h * 2]
          process(t)
          combined
        end
      end
      """

      assert check(code) == []
    end
  end
end
