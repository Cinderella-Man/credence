defmodule Credence.Semantic.FixEtsNewStringNameFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixEtsNewStringName

  @real_message "string interpolation passed as table name to :ets.new/2 — use atom interpolation (:\"...\") instead"

  defp fix(source, message, line) do
    FixEtsNewStringName.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "converts string interpolation to atom interpolation on the flagged line" do
    input = ~S'data = :ets.new("#{name}_data", [:set, :named_table])'
    expected = ~S'data = :ets.new(:"#{name}_data", [:set, :named_table])'
    confirm_fix(fix(input, @real_message, 1), expected)
  end

  test "only fixes the flagged line, leaving other lines intact" do
    input = """
    defmodule EtsStringName do
      def create_tables(name) do
        data = :ets.new(\"\#{name}_data\", [:set, :named_table])
        freq = :ets.new(\"\#{name}_freq\", [:ordered_set, :named_table])
        {data, freq}
      end
    end
    """

    expected = """
    defmodule EtsStringName do
      def create_tables(name) do
        data = :ets.new(:\"\#{name}_data\", [:set, :named_table])
        freq = :ets.new(\"\#{name}_freq\", [:ordered_set, :named_table])
        {data, freq}
      end
    end
    """

    confirm_fix(fix(input, @real_message, 3), expected)
  end

  test "fixes multiple occurrences on a single flagged line" do
    input = ~S'{:ets.new("#{p}_a", []), :ets.new("#{p}_b", [])}'
    expected = ~S'{:ets.new(:"#{p}_a", []), :ets.new(:"#{p}_b", [])}'
    confirm_fix(fix(input, @real_message, 1), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S'data = :ets.new("#{name}_data", [:set, :named_table])'
    assert valid_syntax?(fix(input, @real_message, 1))
  end

  test "returns source unchanged when no string interpolation on the flagged line" do
    input = "data = :ets.new(:my_table, [:set, :named_table])"
    confirm_fix(fix(input, @real_message, 1), input)
  end

  test "returns source unchanged when line is out of bounds" do
    input = """
    line one
    line two
    """

    confirm_fix(fix(input, @real_message, 99), input)
  end

  test "does not double-prefix already-correct atom interpolation" do
    input = ~S'data = :ets.new(:"#{name}_data", [:set, :named_table])'
    confirm_fix(fix(input, @real_message, 1), input)
  end

  test "leaves non-ETS string interpolation on other lines untouched" do
    input = """
    IO.puts(\"\#{name} created\")
    data = :ets.new(\"\#{name}_data\", [:set, :named_table])
    """

    expected = """
    IO.puts(\"\#{name} created\")
    data = :ets.new(:\"\#{name}_data\", [:set, :named_table])
    """

    confirm_fix(fix(input, @real_message, 2), expected)
  end
end
