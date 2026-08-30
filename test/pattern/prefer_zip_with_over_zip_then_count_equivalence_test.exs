defmodule Credence.Pattern.PreferZipWithOverZipThenCountEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `a |> Enum.zip(b) |> Enum.count(fn {x, y} -> x != y end)`
  → `a |> Enum.zip_with(b, fn x, y -> {x, y} end) |> Enum.count(fn {x, y} -> x != y end)`.

  For eager lists, both zip element-wise, apply the predicate to each pair, and
  count the truthy results. The predicate stays in `Enum.count/2`, preserving
  the original evaluation order for lazy enumerables.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferZipWithOverZipThenCount

  test "zip |> count(fn {x, y} -> x != y end) preserves the count" do
    assert_equivalent(
      "a |> Enum.zip(b) |> Enum.count(fn {x, y} -> x != y end)",
      rule: PreferZipWithOverZipThenCount,
      vars: [:a, :b],
      inputs: [
        {[], []},
        {[], [1, 2]},
        {[1], [1]},
        {[1, 2, 3], [1, 2, 3]},
        {[1, 2, 3], [4, 5, 6]},
        {[1, 2, 3], [1, 5, 3]},
        {[1, 2], [1, 2, 3, 4]},
        {[nil, false, 1], [1, false, nil]},
        {["a", "b"], ["a", "c"]}
      ]
    )
  end

  test "non-boolean truthy predicate results count the same" do
    assert_equivalent(
      "a |> Enum.zip(b) |> Enum.count(fn {x, y} -> x && y end)",
      rule: PreferZipWithOverZipThenCount,
      vars: [:a, :b],
      inputs: [
        {[], []},
        {[1, nil, false, 0], [true, 1, 2, 3]},
        {[:ok, nil], [nil, :ok]},
        {["x"], ["y", "z"]}
      ]
    )
  end

  test "lazy enumerable failures preserve source consumption before the predicate" do
    original =
      "a |> Enum.zip(b) |> Enum.count(fn {x, y} -> if x == 1 and y == 1, do: raise(ArgumentError, \"predicate-first\"), else: true end)"

    emitted = fix(PreferZipWithOverZipThenCount, original)

    expected = """
    a |> Enum.zip_with(b, fn x, y -> {x, y} end) |> Enum.count(fn {x, y} ->
      if x == 1 and y == 1, do: raise(ArgumentError, "predicate-first"), else: true
    end)
    """

    confirm_fix(emitted, expected)

    executable = """
    defmodule Credence.Pattern.PreferZipWithOverZipThenCountLazyOrderFixture do
      def source do
        Stream.map([1, 2], fn
          1 -> 1
          2 -> raise "source-second"
        end)
      end

      def original(a, b), do: #{original}
      def repaired(a, b), do: #{emitted}

      def outcome(fun) do
        try do
          fun.(source(), [1, 2])
        rescue
          error -> {error.__struct__, Exception.message(error)}
        end
      end
    end

    alias Credence.Pattern.PreferZipWithOverZipThenCountLazyOrderFixture, as: Fixture

    {RuntimeError, "source-second"} = Fixture.outcome(&Fixture.original/2)
    {RuntimeError, "source-second"} = Fixture.outcome(&Fixture.repaired/2)
    """

    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(executable)
  end
end
