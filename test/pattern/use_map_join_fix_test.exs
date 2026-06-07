defmodule Credence.Pattern.UseMapJoinFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.UseMapJoin

  describe "fix" do
    test "fixes direct pipeline: Enum.map(enum, f) |> Enum.join()" do
      input = """
      defmodule Bad do
        def stringify(list) do
          Enum.map(list, &to_string/1) |> Enum.join()
        end
      end
      """

      expected = """
      defmodule Bad do
        def stringify(list) do
          Enum.map_join(list, &to_string/1)
        end
      end
      """

      assert fix(UseMapJoin, input) == expected
    end

    test "fixes direct pipeline: Enum.map(enum, f) |> Enum.join(sep)" do
      input = """
      defmodule Bad do
        def csv(list) do
          Enum.map(list, &to_string/1) |> Enum.join(", ")
        end
      end
      """

      expected = """
      defmodule Bad do
        def csv(list) do
          Enum.map_join(list, ", ", &to_string/1)
        end
      end
      """

      assert fix(UseMapJoin, input) == expected
    end

    test "fixes pipe pipeline: enum |> Enum.map(f) |> Enum.join(sep)" do
      input = """
      defmodule Bad do
        def stringify(list) do
          list
          |> Enum.map(&to_string/1)
          |> Enum.join(", ")
        end
      end
      """

      expected = """
      defmodule Bad do
        def stringify(list) do
          list
          |> Enum.map_join(", ", &to_string/1)
        end
      end
      """

      assert fix(UseMapJoin, input) == expected
    end

    test "fixes pipe pipeline without separator" do
      input = """
      defmodule Bad do
        def stringify(list) do
          list
          |> Enum.map(&to_string/1)
          |> Enum.join()
        end
      end
      """

      expected = """
      defmodule Bad do
        def stringify(list) do
          list
          |> Enum.map_join(&to_string/1)
        end
      end
      """

      assert fix(UseMapJoin, input) == expected
    end

    test "fixes nested: Enum.join(Enum.map(enum, f), sep)" do
      input = """
      defmodule Bad do
        def format(list) do
          Enum.join(Enum.map(list, &(&1 * 2)), "-")
        end
      end
      """

      expected = """
      defmodule Bad do
        def format(list) do
          Enum.map_join(list, "-", &(&1 * 2))
        end
      end
      """

      assert fix(UseMapJoin, input) == expected
    end

    test "fixes nested without separator" do
      input = """
      defmodule Bad do
        def format(list) do
          Enum.join(Enum.map(list, &to_string/1))
        end
      end
      """

      expected = """
      defmodule Bad do
        def format(list) do
          Enum.map_join(list, &to_string/1)
        end
      end
      """

      assert fix(UseMapJoin, input) == expected
    end

    test "fixes longer pipeline with preceding steps" do
      input = """
      defmodule Bad do
        def format(list) do
          list
          |> Enum.filter(&(&1 > 0))
          |> Enum.map(&to_string/1)
          |> Enum.join(", ")
        end
      end
      """

      expected = """
      defmodule Bad do
        def format(list) do
          list
          |> Enum.filter(&(&1 > 0))
          |> Enum.map_join(", ", &to_string/1)
        end
      end
      """

      assert fix(UseMapJoin, input) == expected
    end

    test "fixes pipeline that continues after join" do
      input = """
      defmodule Bad do
        def format(list) do
          list
          |> Enum.map(&to_string/1)
          |> Enum.join(", ")
          |> String.upcase()
        end
      end
      """

      expected = """
      defmodule Bad do
        def format(list) do
          list
          |> Enum.map_join(", ", &to_string/1)
          |> String.upcase()
        end
      end
      """

      assert fix(UseMapJoin, input) == expected
    end

    test "fixes with multi-line anonymous function" do
      input = """
      defmodule Bad do
        def render(items) do
          items
          |> Enum.map(fn {k, v} -> "\#{k}=\#{v}" end)
          |> Enum.join("&")
        end
      end
      """

      expected = """
      defmodule Bad do
        def render(items) do
          items
          |> Enum.map_join("&", fn {k, v} -> "\#{k}=\#{v}" end)
        end
      end
      """

      assert fix(UseMapJoin, input) == expected
    end

    test "fixes pipeline with two-arg Enum.map and capture" do
      input = """
      defmodule Bad do
        def format(items) do
          Enum.map(items, &elem(&1, 0)) |> Enum.join("-")
        end
      end
      """

      expected = """
      defmodule Bad do
        def format(items) do
          Enum.map_join(items, "-", &elem(&1, 0))
        end
      end
      """

      assert fix(UseMapJoin, input) == expected
    end

    test "fixes multiple occurrences in same module" do
      input = """
      defmodule Bad do
        def format(list) do
          a = Enum.map(list, &to_string/1) |> Enum.join(", ")
          b = Enum.join(Enum.map(list, &(&1 * 2)), "-")
          {a, b}
        end
      end
      """

      expected = """
      defmodule Bad do
        def format(list) do
          a = Enum.map_join(list, ", ", &to_string/1)
          b = Enum.map_join(list, "-", &(&1 * 2))
          {a, b}
        end
      end
      """

      assert fix(UseMapJoin, input) == expected
    end

    test "fixes pattern inside callback" do
      input = """
      Enum.map(list, fn x ->
        Enum.map(x, &to_string/1) |> Enum.join(", ")
      end)
      """

      expected = """
      Enum.map(list, fn x ->
        Enum.map_join(x, ", ", &to_string/1)
      end)
      """

      assert fix(UseMapJoin, input) == expected
    end

    test "preserves code that does not need fixing" do
      input = """
      defmodule Good do
        def stringify(list) do
          Enum.map_join(list, ",", &to_string/1)
        end
      end
      """

      assert fix(UseMapJoin, input) == input
    end

    test "does not modify intervening-step pattern" do
      input = """
      defmodule Good do
        def format(list) do
          list
          |> Enum.map(&to_string/1)
          |> Enum.uniq()
          |> Enum.join(", ")
        end
      end
      """

      assert fix(UseMapJoin, input) == input
    end
  end
end
