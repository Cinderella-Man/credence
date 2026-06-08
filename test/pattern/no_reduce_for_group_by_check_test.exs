defmodule Credence.Pattern.NoReduceForGroupByCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoReduceForGroupBy

  describe "flags the full reduce |> Map.new(reverse) pipeline" do
    test "inline key, direct reduce" do
      code = """
      defmodule Bad do
        def group(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.update(acc, String.first(x), [x], &[x | &1])
          end)
          |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
        end
      end
      """

      [issue] = check(NoReduceForGroupBy, code)
      assert issue.rule == :no_reduce_for_group_by
      assert issue.message =~ "Enum.group_by"
    end

    test "single key binding, direct reduce" do
      code = """
      defmodule Bad do
        def group(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            key = String.first(x)
            Map.update(acc, key, [x], &[x | &1])
          end)
          |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
        end
      end
      """

      [issue] = check(NoReduceForGroupBy, code)
      assert issue.rule == :no_reduce_for_group_by
    end

    test "piped reduce" do
      code = """
      defmodule Bad do
        def group(list) do
          list
          |> Enum.reduce(%{}, fn x, acc ->
            Map.update(acc, String.first(x), [x], &[x | &1])
          end)
          |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
        end
      end
      """

      [issue] = check(NoReduceForGroupBy, code)
      assert issue.rule == :no_reduce_for_group_by
    end
  end

  describe "does NOT flag unsafe / non-equivalent shapes" do
    # A bare reduce builds value lists in reverse insertion order, which is a
    # *different* result from Enum.group_by/2 — no behaviour-preserving fix, so
    # it is intentionally not flagged.
    test "bare reduce without the trailing reverse (direct)" do
      code = """
      defmodule Good do
        def group(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.update(acc, String.first(x), [x], &[x | &1])
          end)
        end
      end
      """

      assert check(NoReduceForGroupBy, code) == []
    end

    test "bare reduce without the trailing reverse (piped)" do
      code = """
      defmodule Good do
        def group(list) do
          list
          |> Enum.reduce(%{}, fn x, acc ->
            Map.update(acc, String.first(x), [x], &[x | &1])
          end)
        end
      end
      """

      assert check(NoReduceForGroupBy, code) == []
    end

    # Map.new that does NOT reverse the value list keeps reverse insertion
    # order, so the pipeline is not equivalent to Enum.group_by/2.
    test "trailing Map.new without reverse" do
      code = """
      defmodule Good do
        def group(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.update(acc, String.first(x), [x], &[x | &1])
          end)
          |> Map.new(fn {k, v} -> {k, v} end)
        end
      end
      """

      assert check(NoReduceForGroupBy, code) == []
    end

    # The Map.update is not the returned value (a later statement is), so the
    # accumulator is not the map being built — dropping/reordering statements
    # would change behaviour. Not flagged.
    test "block with Map.update not last" do
      code = """
      defmodule Good do
        def group(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.update(acc, String.first(x), [x], &[x | &1])
            acc
          end)
          |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
        end
      end
      """

      assert check(NoReduceForGroupBy, code) == []
    end

    # Extra side-effecting statement before Map.update would be dropped by any
    # rewrite to group_by. Not flagged.
    test "block with an extra statement before the binding" do
      code = """
      defmodule Good do
        def group(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            IO.inspect(x)
            key = String.first(x)
            Map.update(acc, key, [x], &[x | &1])
          end)
          |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
        end
      end
      """

      assert check(NoReduceForGroupBy, code) == []
    end
  end

  describe "does NOT flag unrelated code" do
    test "Enum.group_by" do
      code = """
      defmodule Good do
        def group(list) do
          Enum.group_by(list, &String.first/1)
        end
      end
      """

      assert check(NoReduceForGroupBy, code) == []
    end

    test "Enum.reduce with Map.put" do
      code = """
      defmodule Good do
        def build(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.put(acc, x, String.length(x))
          end)
          |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
        end
      end
      """

      assert check(NoReduceForGroupBy, code) == []
    end

    test "Enum.reduce with non-empty initial map" do
      code = """
      defmodule Good do
        def group(list, existing) do
          Enum.reduce(list, existing, fn x, acc ->
            Map.update(acc, String.first(x), [x], &[x | &1])
          end)
          |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
        end
      end
      """

      assert check(NoReduceForGroupBy, code) == []
    end

    test "Enum.reduce with different default value" do
      code = """
      defmodule Good do
        def group(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.update(acc, String.first(x), 0, &(&1 + 1))
          end)
          |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
        end
      end
      """

      assert check(NoReduceForGroupBy, code) == []
    end

    test "Enum.reduce with append instead of prepend" do
      code = """
      defmodule Good do
        def group(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.update(acc, String.first(x), [x], &(&1 ++ [x]))
          end)
          |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
        end
      end
      """

      assert check(NoReduceForGroupBy, code) == []
    end

    test "Map.new (already idiomatic)" do
      code = """
      defmodule Good do
        def build(list) do
          Map.new(list, fn x -> {x, String.length(x)} end)
        end
      end
      """

      assert check(NoReduceForGroupBy, code) == []
    end
  end
end
