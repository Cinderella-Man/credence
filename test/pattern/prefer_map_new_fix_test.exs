defmodule Credence.Pattern.PreferMapNewFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapNew

  test "rewrites Enum.into(enum, %{}) to Map.new(enum)" do
    code = "Enum.into(list, %{})"

    expected = "Map.new(list)"

    confirm_fix(fix(PreferMapNew, code), expected)
  end

  test "rewrites piped Enum.into(%{}) to Map.new()" do
    code = "pairs |> Enum.into(%{})"

    expected = "pairs |> Map.new()"

    confirm_fix(fix(PreferMapNew, code), expected)
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

    confirm_fix(fix(PreferMapNew, code), expected)
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

    confirm_fix(fix(PreferMapNew, code), expected)
  end

  # ── No-op cases (check does not fire → fix leaves code unchanged) ──

  test "leaves Map.new(enum) untouched" do
    code = "Map.new(list)"

    confirm_fix(fix(PreferMapNew, code), code)
  end

  test "leaves Enum.into with a variable target untouched" do
    code = "Enum.into(list, existing_map)"

    confirm_fix(fix(PreferMapNew, code), code)
  end

  test "leaves Enum.into with a non-empty map literal untouched" do
    code = "Enum.into(list, %{a: 1})"

    confirm_fix(fix(PreferMapNew, code), code)
  end

  test "does not rewrite calls through custom Enum and Map aliases" do
    enum_alias = "alias CustomEnum, as: Enum\nEnum.into(items, %{})"
    map_alias = "alias CustomMap, as: Map\nEnum.into(items, %{})"

    confirm_fix(fix(PreferMapNew, enum_alias), enum_alias)
    confirm_fix(fix(PreferMapNew, map_alias), map_alias)
  end
end
