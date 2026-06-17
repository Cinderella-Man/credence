defmodule Credence.Pattern.PreferConcatOverFlatMapIdentityFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferConcatOverFlatMapIdentity

  describe "fix/2 — direct calls" do
    test "fixes Enum.flat_map(list, fn x -> x end) → Enum.concat(list)" do
      input = """
      defmodule Example do
        def flatten(matrix), do: Enum.flat_map(matrix, fn row -> row end)
      end
      """

      expected = """
      defmodule Example do
        def flatten(matrix), do: Enum.concat(matrix)
      end
      """

      confirm_fix(fix(PreferConcatOverFlatMapIdentity, input), expected)
    end

    test "fixes Enum.flat_map(list, & &1) → Enum.concat(list)" do
      input = """
      defmodule Example do
        def flatten(list), do: Enum.flat_map(list, & &1)
      end
      """

      expected = """
      defmodule Example do
        def flatten(list), do: Enum.concat(list)
      end
      """

      confirm_fix(fix(PreferConcatOverFlatMapIdentity, input), expected)
    end
  end

  describe "fix/2 — piped calls" do
    test "fixes |> Enum.flat_map(fn x -> x end) → |> Enum.concat()" do
      input = """
      defmodule Example do
        def flatten(matrix), do: matrix |> Enum.flat_map(fn row -> row end)
      end
      """

      expected = """
      defmodule Example do
        def flatten(matrix), do: matrix |> Enum.concat()
      end
      """

      confirm_fix(fix(PreferConcatOverFlatMapIdentity, input), expected)
    end

    test "fixes in a longer pipeline" do
      input = """
      defmodule Example do
        def flatten(matrix) do
          matrix |> Enum.flat_map(fn row -> row end)
        end
      end
      """

      expected = """
      defmodule Example do
        def flatten(matrix) do
          matrix |> Enum.concat()
        end
      end
      """

      confirm_fix(fix(PreferConcatOverFlatMapIdentity, input), expected)
    end

    test "fixes piped & &1" do
      input = """
      defmodule Example do
        def flatten(list), do: list |> Enum.flat_map(& &1)
      end
      """

      expected = """
      defmodule Example do
        def flatten(list), do: list |> Enum.concat()
      end
      """

      confirm_fix(fix(PreferConcatOverFlatMapIdentity, input), expected)
    end
  end

  describe "fix/2 — non-trivial shapes" do
    test "rebuilds a complex first argument" do
      input = """
      defmodule Example do
        def flatten(matrix), do: Enum.flat_map(get_rows(matrix), fn row -> row end)
      end
      """

      expected = """
      defmodule Example do
        def flatten(matrix), do: Enum.concat(get_rows(matrix))
      end
      """

      confirm_fix(fix(PreferConcatOverFlatMapIdentity, input), expected)
    end

    test "patches only the flat_map stage in the middle of a longer pipeline" do
      input = """
      defmodule Example do
        def flatten(data), do: data |> transform() |> Enum.flat_map(& &1) |> Enum.sort()
      end
      """

      expected = """
      defmodule Example do
        def flatten(data), do: data |> transform() |> Enum.concat() |> Enum.sort()
      end
      """

      confirm_fix(fix(PreferConcatOverFlatMapIdentity, input), expected)
    end
  end

  describe "fix/2 — edge cases" do
    test "does not touch non-identity callbacks" do
      code = """
      defmodule Example do
        def flatten(list), do: Enum.flat_map(list, fn x -> [x] end)
      end
      """

      confirm_fix(fix(PreferConcatOverFlatMapIdentity, code), code)
    end

    test "returns source unchanged when nothing to fix" do
      code = """
      defmodule Example do
        def flatten(list), do: Enum.concat(list)
      end
      """

      confirm_fix(fix(PreferConcatOverFlatMapIdentity, code), code)
    end

    test "preserves surrounding code" do
      input = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(list), do: list |> Enum.flat_map(fn x -> x end)
        def baz(y), do: y * 2
      end
      """

      expected = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(list), do: list |> Enum.concat()
        def baz(y), do: y * 2
      end
      """

      confirm_fix(fix(PreferConcatOverFlatMapIdentity, input), expected)
    end
  end
end
