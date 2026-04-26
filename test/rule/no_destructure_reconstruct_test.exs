defmodule Credence.Rule.NoDestructureReconstructTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoDestructureReconstruct.check(ast, [])
  end

  describe "NoDestructureReconstruct" do
    test "detects destructure-reconstruct in case branch" do
      code = """
      defmodule Bad do
        def check(ip) do
          case String.split(ip, ".") do
            [p1, p2, p3, p4] ->
              Enum.all?([p1, p2, p3, p4], &valid_octet?/1)
            _ ->
              false
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_destructure_reconstruct
      assert issue.severity == :info
      assert issue.message =~ "p1"
      assert issue.message =~ "p4"
      assert issue.message =~ "reassembled"
    end

    test "detects with two variables" do
      code = """
      defmodule Bad do
        def swap(input) do
          case String.split(input, ":") do
            [a, b] -> Enum.join([a, b], "-")
            _ -> input
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "a, b"
    end

    test "detects with three variables" do
      code = """
      defmodule Bad do
        def process(data) do
          case data do
            [x, y, z] -> Enum.map([x, y, z], &to_string/1)
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "x, y, z"
    end

    test "detects in function head (def)" do
      code = """
      defmodule Bad do
        def process([a, b, c]) do
          Enum.map([a, b, c], &(&1 * 2))
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "a, b, c"
    end

    test "detects in function head (defp)" do
      code = """
      defmodule Bad do
        defp transform([first, second]) do
          Enum.join([first, second], ",")
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "first, second"
    end

    test "detects in guarded function head" do
      code = """
      defmodule Bad do
        def validate([a, b, c, d]) when is_binary(a) do
          Enum.all?([a, b, c, d], &is_binary/1)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "a, b, c, d"
    end

    test "detects when reconstructed list is nested in body" do
      code = """
      defmodule Bad do
        def check(input) do
          case String.split(input, ",") do
            [a, b, c] ->
              result = Enum.max([a, b, c])
              {:ok, result}
            _ ->
              :error
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "a, b, c"
    end

    # ---- Negative cases ----

    test "does not flag when variables are used individually" do
      code = """
      defmodule Good do
        def check(ip) do
          case String.split(ip, ".") do
            [p1, p2, p3, p4] ->
              {p1, p2, p3, p4}
            _ ->
              nil
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when bound as a whole with =" do
      code = """
      defmodule Good do
        def check(ip) do
          case String.split(ip, ".") do
            [_, _, _, _] = parts ->
              Enum.all?(parts, &valid_octet?/1)
            _ ->
              false
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when list order differs" do
      code = """
      defmodule Good do
        def reverse_pair(input) do
          case String.split(input, ":") do
            [a, b] -> Enum.join([b, a], ":")
            _ -> input
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when pattern contains literals" do
      code = """
      defmodule Good do
        def check(list) do
          case list do
            [1, b, c] -> Enum.sum([1, b, c])
            _ -> 0
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when pattern contains underscore variables" do
      code = """
      defmodule Good do
        def check(list) do
          case list do
            [_a, b, c] -> {b, c}
            _ -> nil
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag single-element list patterns" do
      code = """
      defmodule Good do
        def wrap(data) do
          case data do
            [x] -> Enum.map([x], &to_string/1)
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when pattern is not a list" do
      code = """
      defmodule Good do
        def check({a, b}) do
          Enum.max([a, b])
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when body list has different length" do
      code = """
      defmodule Good do
        def extend(input) do
          case String.split(input, ",") do
            [a, b] -> Enum.join([a, b, "extra"], ",")
            _ -> input
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag non-list function args" do
      code = """
      defmodule Good do
        def process(a, b, c) do
          Enum.map([a, b, c], &to_string/1)
        end
      end
      """

      assert check(code) == []
    end
  end
end
