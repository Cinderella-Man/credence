defmodule Credence.Semantic.NoMapHasFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoMapHas
  alias Credence.RuleHelpers

  @matching_msg "Map.has?/2 is undefined or private"

  defp fix(source, line) do
    NoMapHas.fix(source, %{severity: :warning, message: @matching_msg, position: {line, 1}})
  end

  test "fixes Map.has? to Map.has_key?" do
    input = """
    defmodule Example do
      def has_key?(map, key) do
        Map.has?(map, key)
      end
    end
    """

    expected = """
    defmodule Example do
      def has_key?(map, key) do
        Map.has_key?(map, key)
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "rewrites only the stdlib Map.has? when another *Map.has? shares the line" do
    input = """
    defmodule Example do
      def check(m, k) do
        SomeMap.has?(m, k) or Map.has?(m, k)
      end
    end
    """

    expected = """
    defmodule Example do
      def check(m, k) do
        SomeMap.has?(m, k) or Map.has_key?(m, k)
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def has_key?(map, key) do
        Map.has?(map, key)
      end
    end
    """

    assert valid_syntax?(fix(input, 3))
  end

  test "leaves a same-line string alone and repairs the diagnosed call" do
    input = """
    defmodule NoMapHasStringRegression do
      def check(map, key), do: {"Map.has?", Map.has?(map, key)}
    end
    """

    expected = """
    defmodule NoMapHasStringRegression do
      def check(map, key), do: {"Map.has?", Map.has_key?(map, key)}
    end
    """

    assert {:ok, diagnostics} = RuleHelpers.compile_and_capture(input)
    diagnostic = Enum.find(diagnostics, &NoMapHas.match?/1)
    assert diagnostic
    confirm_fix(NoMapHas.fix(input, diagnostic), expected)
  end

  test "repairs an aliased Map call identified by the compiler" do
    input = """
    defmodule NoMapHasAliasRegression do
      alias Map, as: M
      def check(map, key), do: M.has?(map, key)
    end
    """

    expected = """
    defmodule NoMapHasAliasRegression do
      alias Map, as: M
      def check(map, key), do: M.has_key?(map, key)
    end
    """

    assert {:ok, diagnostics} = RuleHelpers.compile_and_capture(input)
    diagnostic = Enum.find(diagnostics, &NoMapHas.match?/1)
    assert diagnostic
    confirm_fix(NoMapHas.fix(input, diagnostic), expected)
  end
end
