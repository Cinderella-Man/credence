defmodule Credence.Pattern.NoReduceForGroupByFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoReduceForGroupBy

  test "rewrites reduce |> Map.new(reverse) with inline key to Enum.group_by" do
    code = """
    Enum.reduce(list, %{}, fn x, acc ->
      Map.update(acc, String.first(x), [x], &[x | &1])
    end)
    |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
    """

    expected = """
    Enum.group_by(
      list,
      fn x -> String.first(x) end
    )
    """

    assert fix(NoReduceForGroupBy, code) == expected
  end

  test "rewrites reduce with single key binding to Enum.group_by" do
    code = """
    Enum.reduce(list, %{}, fn x, acc ->
      key = String.first(x)
      Map.update(acc, key, [x], &[x | &1])
    end)
    |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
    """

    expected = """
    Enum.group_by(
      list,
      fn x -> String.first(x) end
    )
    """

    assert fix(NoReduceForGroupBy, code) == expected
  end

  test "rewrites the piped reduce form to Enum.group_by" do
    code = """
    list
    |> Enum.reduce(%{}, fn x, acc ->
      Map.update(acc, String.first(x), [x], &[x | &1])
    end)
    |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
    """

    expected = """
    Enum.group_by(
      list,
      fn x -> String.first(x) end
    )
    """

    assert fix(NoReduceForGroupBy, code) == expected
  end

  test "preserves surrounding code" do
    code = """
    defmodule M do
      def group(list) do
        result =
          Enum.reduce(list, %{}, fn x, acc ->
            Map.update(acc, String.first(x), [x], &[x | &1])
          end)
          |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)

        Map.keys(result)
      end
    end
    """

    expected = """
    defmodule M do
      def group(list) do
        result =
          Enum.group_by(
            list,
            fn x -> String.first(x) end
          )

        Map.keys(result)
      end
    end
    """

    assert fix(NoReduceForGroupBy, code) == expected
  end

  test "no-op on bare reduce without the trailing reverse" do
    code = """
    Enum.reduce(list, %{}, fn x, acc ->
      Map.update(acc, String.first(x), [x], &[x | &1])
    end)
    """

    assert fix(NoReduceForGroupBy, code) == code
  end

  test "no-op when the trailing Map.new does not reverse the value list" do
    code = """
    Enum.reduce(list, %{}, fn x, acc ->
      Map.update(acc, String.first(x), [x], &[x | &1])
    end)
    |> Map.new(fn {k, v} -> {k, v} end)
    """

    assert fix(NoReduceForGroupBy, code) == code
  end
end
