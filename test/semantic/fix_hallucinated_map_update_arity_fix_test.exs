defmodule Credence.Semantic.FixHallucinatedMapUpdateArityFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixHallucinatedMapUpdateArity

  @real_message "Map.update/3 is undefined or private. Did you mean:\n\n    * update/4\n"

  defp fix(source, position) do
    FixHallucinatedMapUpdateArity.fix(source, %{
      severity: :warning,
      message: @real_message,
      position: position
    })
  end

  test "re-aims the flagged Map.update/3 at Map.update!/3" do
    input = """
    defmodule MapUpdateArityExample do
      def increment_count(map, key) do
        Map.update(map, key, fn val -> val + 1 end)
      end
    end
    """

    expected = """
    defmodule MapUpdateArityExample do
      def increment_count(map, key) do
        Map.update!(map, key, fn val -> val + 1 end)
      end
    end
    """

    confirm_fix(fix(input, {3, 9}), expected)
  end

  test "keeps a multiline update function byte-identical around the splice" do
    input = """
    defmodule MapUpdateArityExample do
      def add_value(map, key, val) do
        Map.update(map, key, fn existing ->
          existing + val
        end)
      end
    end
    """

    expected = """
    defmodule MapUpdateArityExample do
      def add_value(map, key, val) do
        Map.update!(map, key, fn existing ->
          existing + val
        end)
      end
    end
    """

    confirm_fix(fix(input, {3, 9}), expected)
  end

  test "fixes a call whose update function is a capture" do
    input = """
    defmodule MapUpdateArityExample do
      def increment(map, key) do
        Map.update(map, key, &(&1 + 1))
      end
    end
    """

    expected = """
    defmodule MapUpdateArityExample do
      def increment(map, key) do
        Map.update!(map, key, &(&1 + 1))
      end
    end
    """

    confirm_fix(fix(input, {3, 9}), expected)
  end

  test "fixes with a line-only position when the candidate is unambiguous" do
    input = """
    defmodule MapUpdateArityExample do
      def increment_count(map, key) do
        Map.update(map, key, fn val -> val + 1 end)
      end
    end
    """

    expected = """
    defmodule MapUpdateArityExample do
      def increment_count(map, key) do
        Map.update!(map, key, fn val -> val + 1 end)
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "leaves a valid Map.update/4 call unchanged" do
    input = """
    defmodule CleanExample do
      def increment_count(map, key) do
        Map.update(map, key, 0, fn val -> val + 1 end)
      end
    end
    """

    confirm_fix(fix(input, {3, 9}), input)
  end

  test "never touches a valid piped Map.update/4 elsewhere in the function" do
    input = """
    defmodule PipeSafety do
      def bump(map, key) do
        map
        |> Map.update(key, 0, fn v -> v + 1 end)
        |> Map.merge(Map.update(map, key, fn v -> v + 1 end))
      end
    end
    """

    expected = """
    defmodule PipeSafety do
      def bump(map, key) do
        map
        |> Map.update(key, 0, fn v -> v + 1 end)
        |> Map.merge(Map.update!(map, key, fn v -> v + 1 end))
      end
    end
    """

    confirm_fix(fix(input, {5, 22}), expected)
  end

  test "leaves the piped hallucination (two args at the call site) unfixed" do
    input = """
    defmodule PipedHallucination do
      def bump(map, key) do
        map |> Map.update(key, fn v -> v + 1 end)
      end
    end
    """

    confirm_fix(fix(input, {3, 16}), input)
  end

  test "line-only position with a piped Map.update/4 on the flagged line no-ops" do
    input = """
    defmodule PipeLineOnly do
      def bump(map, key) do
        map |> Map.update(key, & &1) |> Map.update(key, 0, fn v -> v + 1 end)
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "two flagged calls on one line: each column fixes only its own call" do
    input = """
    defmodule TwoOnOneLine do
      def pair(m, k, j) do
        {Map.update(m, k, & &1), Map.update(m, j, & &1)}
      end
    end
    """

    expected_first = """
    defmodule TwoOnOneLine do
      def pair(m, k, j) do
        {Map.update!(m, k, & &1), Map.update(m, j, & &1)}
      end
    end
    """

    expected_second = """
    defmodule TwoOnOneLine do
      def pair(m, k, j) do
        {Map.update(m, k, & &1), Map.update!(m, j, & &1)}
      end
    end
    """

    confirm_fix(fix(input, {3, 10}), expected_first)
    confirm_fix(fix(input, {3, 34}), expected_second)
  end

  test "line-only position with two candidates on the line no-ops" do
    input = """
    defmodule TwoOnOneLine do
      def pair(m, k, j) do
        {Map.update(m, k, & &1), Map.update(m, j, & &1)}
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "leaves the &Map.update/3 capture unfixed" do
    input = """
    defmodule CaptureForm do
      def cap do
        &Map.update/3
      end
    end
    """

    confirm_fix(fix(input, {3, 10}), input)
  end

  test "leaves Elixir.Map.update unfixed" do
    input = """
    defmodule ElixirPrefixed do
      def f(m, k) do
        Elixir.Map.update(m, k, & &1)
      end
    end
    """

    confirm_fix(fix(input, {3, 16}), input)
  end

  test "no-ops when the column matches no candidate" do
    input = """
    defmodule MapUpdateArityExample do
      def increment_count(map, key) do
        Map.update(map, key, fn val -> val + 1 end)
      end
    end
    """

    confirm_fix(fix(input, {3, 10}), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, {1, 1}), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule MapUpdateArityExample do
      def increment_count(map, key) do
        Map.update(map, key, fn val -> val + 1 end)
      end
    end
    """

    assert valid_syntax?(fix(input, {3, 9}))
  end
end
