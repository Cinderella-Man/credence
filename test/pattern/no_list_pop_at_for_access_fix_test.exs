defmodule Credence.Pattern.NoListPopAtForAccessFixTest do
  use ExUnit.Case

  alias Credence.RuleHelpers

  defp fix(code) do
    RuleHelpers.apply_rule_fix(Credence.Pattern.NoListPopAtForAccess, code)
  end

  describe "fix — elem(0) head extraction => List.first/1" do
    test "fully piped form" do
      code = """
      defmodule Bad do
        def pop_head(list) do
          list |> List.pop_at(0) |> elem(0)
        end
      end
      """

      expected = """
      defmodule Bad do
        def pop_head(list) do
          List.first(list)
        end
      end
      """

      assert fix(code) == expected
    end

    test "direct pop_at piped into elem(0)" do
      code = """
      defmodule Bad do
        def pop_head(list) do
          List.pop_at(list, 0) |> elem(0)
        end
      end
      """

      expected = """
      defmodule Bad do
        def pop_head(list) do
          List.first(list)
        end
      end
      """

      assert fix(code) == expected
    end

    test "nested form" do
      code = """
      defmodule Bad do
        def pop_head(list) do
          elem(List.pop_at(list, 0), 0)
        end
      end
      """

      expected = """
      defmodule Bad do
        def pop_head(list) do
          List.first(list)
        end
      end
      """

      assert fix(code) == expected
    end
  end

  describe "fix — elem(1) rest extraction => List.delete_at/2" do
    test "fully piped form" do
      code = """
      defmodule Bad do
        def pop_rest(list) do
          list |> List.pop_at(0) |> elem(1)
        end
      end
      """

      expected = """
      defmodule Bad do
        def pop_rest(list) do
          List.delete_at(list, 0)
        end
      end
      """

      assert fix(code) == expected
    end

    test "nested form" do
      code = """
      defmodule Bad do
        def pop_rest(list) do
          elem(List.pop_at(list, 0), 1)
        end
      end
      """

      expected = """
      defmodule Bad do
        def pop_rest(list) do
          List.delete_at(list, 0)
        end
      end
      """

      assert fix(code) == expected
    end
  end

  describe "fix — leaves non-matching code untouched" do
    test "non-zero pop_at index is a no-op" do
      code = """
      defmodule Good do
        def pop(list) do
          list |> List.pop_at(3) |> elem(0)
        end
      end
      """

      assert fix(code) == code
    end

    test "elem index outside {popped, rest} is a no-op" do
      code = """
      defmodule Good do
        def pop(list) do
          list |> List.pop_at(0) |> elem(2)
        end
      end
      """

      assert fix(code) == code
    end

    test "plain elem on a tuple is a no-op" do
      code = """
      defmodule Good do
        def get(tuple) do
          elem(tuple, 1)
        end
      end
      """

      assert fix(code) == code
    end
  end
end
