defmodule Credence.Pattern.PreferMapNewFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapNew

  test "rewrites Enum.into(enum, %{}) to Map.new(enum)" do
    code = """
    Enum.into(list, %{})
    """

    expected = """
    Map.new(list)
    """

    assert fix(PreferMapNew, code) == expected
  end

  test "rewrites piped Enum.into(%{}) to Map.new()" do
    code = """
    pairs |> Enum.into(%{})
    """

    expected = """
    pairs |> Map.new()
    """

    assert fix(PreferMapNew, code) == expected
  end

  test "rewrites Enum.into in a longer pipeline" do
    code = """
    keys
    |> Enum.zip(vals)
    |> Enum.into(%{})
    """

    expected = """
    keys
    |> Enum.zip(vals)
    |> Map.new()
    """

    assert fix(PreferMapNew, code) == expected
  end

  test "preserves surrounding code" do
    code = """
    defmodule M do
      def build(data) do
        map = Enum.into(data, %{})
        Map.keys(map)
      end
    end
    """

    expected = """
    defmodule M do
      def build(data) do
        map = Map.new(data)
        Map.keys(map)
      end
    end
    """

    assert fix(PreferMapNew, code) == expected
  end

  # ── No-op cases (check does not fire → fix leaves code unchanged) ──

  test "leaves Map.new(enum) untouched" do
    code = """
    Map.new(list)
    """

    assert fix(PreferMapNew, code) == code
  end

  test "leaves Enum.into with a variable target untouched" do
    code = """
    Enum.into(list, existing_map)
    """

    assert fix(PreferMapNew, code) == code
  end

  test "leaves Enum.into with a non-empty map literal untouched" do
    code = """
    Enum.into(list, %{a: 1})
    """

    assert fix(PreferMapNew, code) == code
  end
end
