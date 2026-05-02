defmodule Credence.Rule.UseMapJoinTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.UseMapJoin.check(ast, [])
  end

  describe "UseMapJoin" do
    test "detects Enum.map |> Enum.join() pipeline (default separator)" do
      code = """
      defmodule Bad do
        def stringify(list) do
          list
          |> Enum.map(&to_string/1)
          |> Enum.join()
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :use_map_join

      assert issue.message =~ "Enum.map_join/3"
    end

    test "detects Enum.map |> Enum.join with separator" do
      code = """
      defmodule Bad do
        def csv(list) do
          list
          |> Enum.map(&to_string/1)
          |> Enum.join(", ")
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :use_map_join
    end

    test "detects two-step pipeline: Enum.map(list, f) |> Enum.join()" do
      code = """
      defmodule Bad do
        def format(items) do
          Enum.map(items, &elem(&1, 0)) |> Enum.join("-")
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :use_map_join
    end

    test "detects nested call: Enum.join(Enum.map(...))" do
      code = """
      defmodule Bad do
        def format(list) do
          Enum.join(Enum.map(list, &(&1 * 2)), "-")
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :use_map_join
    end

    test "detects nested call without separator: Enum.join(Enum.map(...))" do
      code = """
      defmodule Bad do
        def format(list) do
          Enum.join(Enum.map(list, &to_string/1))
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :use_map_join
    end

    test "detects in a longer pipeline where map and join are adjacent" do
      code = """
      defmodule Bad do
        def format(list) do
          list
          |> Enum.filter(&(&1 > 0))
          |> Enum.map(&to_string/1)
          |> Enum.join(", ")
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :use_map_join
    end

    test "detects with anonymous function in map" do
      code = """
      defmodule Bad do
        def render(items) do
          items
          |> Enum.map(fn {k, v} -> "\#{k}=\#{v}" end)
          |> Enum.join("&")
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :use_map_join
    end

    # ---- Negative cases ----

    test "does not flag Enum.map_join (already correct)" do
      code = """
      defmodule Good do
        def stringify(list) do
          Enum.map_join(list, ",", &to_string/1)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when map and join are on separate variables" do
      code = """
      defmodule Good do
        def process(list) do
          mapped = Enum.map(list, &(&1 * 2))
          Enum.join(mapped, ",")
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when there's an intervening step between map and join" do
      code = """
      defmodule Good do
        def format(list) do
          list
          |> Enum.map(&to_string/1)
          |> Enum.uniq()
          |> Enum.join(", ")
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.map without join" do
      code = """
      defmodule Good do
        def double(list) do
          Enum.map(list, &(&1 * 2))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.join without map" do
      code = """
      defmodule Good do
        def combine(list) do
          Enum.join(list, ", ")
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag non-Enum map piped into Enum.join" do
      code = """
      defmodule Good do
        def process(list) do
          list
          |> Stream.map(&to_string/1)
          |> Enum.join(", ")
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.map piped into non-Enum join" do
      code = """
      defmodule Good do
        def process(list) do
          list
          |> Enum.map(&to_string/1)
          |> MyModule.join(", ")
        end
      end
      """

      assert check(code) == []
    end
  end
end
