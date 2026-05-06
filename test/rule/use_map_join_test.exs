defmodule Credence.Pattern.UseMapJoinTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.UseMapJoin.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.UseMapJoin.fix(code, [])
  end

  describe "check" do
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

  describe "fix" do
    test "is fixable" do
      assert Credence.Pattern.UseMapJoin.fixable?() == true
    end

    # --- Pipeline: 2-arg Enum.map |> Enum.join ---

    test "fixes direct pipeline: Enum.map(enum, f) |> Enum.join()" do
      input = """
      defmodule Bad do
        def stringify(list) do
          Enum.map(list, &to_string/1) |> Enum.join()
        end
      end
      """

      output = fix(input)
      assert {:ok, _} = Code.string_to_quoted(output)
      assert check(output) == []
      assert output =~ "map_join"
    end

    test "fixes direct pipeline: Enum.map(enum, f) |> Enum.join(sep)" do
      input = """
      defmodule Bad do
        def csv(list) do
          Enum.map(list, &to_string/1) |> Enum.join(", ")
        end
      end
      """

      output = fix(input)
      assert {:ok, _} = Code.string_to_quoted(output)
      assert check(output) == []
      assert output =~ "map_join"
    end

    # --- Pipeline: enum |> Enum.map(f) |> Enum.join ---

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

      output = fix(input)
      assert {:ok, _} = Code.string_to_quoted(output)
      assert check(output) == []
      assert output =~ "map_join"
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

      output = fix(input)
      assert {:ok, _} = Code.string_to_quoted(output)
      assert check(output) == []
      assert output =~ "map_join"
    end

    # --- Nested: Enum.join(Enum.map(...)) ---

    test "fixes nested: Enum.join(Enum.map(enum, f), sep)" do
      input = """
      defmodule Bad do
        def format(list) do
          Enum.join(Enum.map(list, &(&1 * 2)), "-")
        end
      end
      """

      output = fix(input)
      assert {:ok, _} = Code.string_to_quoted(output)
      assert check(output) == []
      assert output =~ "map_join"
    end

    test "fixes nested without separator" do
      input = """
      defmodule Bad do
        def format(list) do
          Enum.join(Enum.map(list, &to_string/1))
        end
      end
      """

      output = fix(input)
      assert {:ok, _} = Code.string_to_quoted(output)
      assert check(output) == []
      assert output =~ "map_join"
    end

    # --- Longer pipelines ---

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

      output = fix(input)
      assert {:ok, _} = Code.string_to_quoted(output)
      assert check(output) == []
      assert output =~ "map_join"
      assert output =~ "filter"
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

      output = fix(input)
      assert {:ok, _} = Code.string_to_quoted(output)
      assert check(output) == []
      assert output =~ "map_join"
      assert output =~ "String.upcase"
    end

    # --- Complex mapper functions ---

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

      output = fix(input)
      assert {:ok, _} = Code.string_to_quoted(output)
      assert check(output) == []
      assert output =~ "map_join"
    end

    test "fixes pipeline with two-arg Enum.map and capture" do
      input = """
      defmodule Bad do
        def format(items) do
          Enum.map(items, &elem(&1, 0)) |> Enum.join("-")
        end
      end
      """

      output = fix(input)
      assert {:ok, _} = Code.string_to_quoted(output)
      assert check(output) == []
      assert output =~ "map_join"
    end

    # --- Multiple occurrences ---

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

      output = fix(input)
      assert {:ok, _} = Code.string_to_quoted(output)
      assert check(output) == []
      assert output =~ "map_join"
    end

    # --- Nested inside other expressions ---

    test "fixes pattern inside callback" do
      input = """
      Enum.map(list, fn x ->
        Enum.map(x, &to_string/1) |> Enum.join(", ")
      end)
      """

      output = fix(input)
      assert {:ok, _} = Code.string_to_quoted(output)
      assert check(output) == []
    end

    # --- Idempotence / no-op cases ---

    test "preserves code that does not need fixing" do
      input = """
      defmodule Good do
        def stringify(list) do
          Enum.map_join(list, ",", &to_string/1)
        end
      end
      """

      output = fix(input)
      assert {:ok, _} = Code.string_to_quoted(output)
      assert check(output) == []
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

      output = fix(input)
      assert {:ok, _} = Code.string_to_quoted(output)
      assert check(output) == []
      assert output =~ "uniq"
    end
  end
end
