defmodule Credence.Semantic.NoHallucinatedEtsKeytypeOptionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedEtsKeytypeOption

  @real_message "errors were found at the given arguments:\n\n  * 2nd argument: invalid options\n"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedEtsKeytypeOption.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "removes keytype: :term from ets options" do
    input = """
    defmodule HallucinatedEtsKeyType do
      def create_table do
        :ets.new(:my_table, [:set, :public, :named_table, keytype: :term, read_concurrency: true])
      end
    end
    """

    expected = """
    defmodule HallucinatedEtsKeyType do
      def create_table do
        :ets.new(:my_table, [:set, :public, :named_table, read_concurrency: true])
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule HallucinatedEtsKeyType do
      def create_table do
        :ets.new(:my_table, [:set, :public, :named_table, keytype: :term, read_concurrency: true])
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no keytype present" do
    input = """
    defmodule CleanETS do
      def create_table do
        :ets.new(:my_table, [:set, :public, :named_table, read_concurrency: true])
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule Unrelated do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "does not touch keytype with a non-:term value (narrow scope)" do
    input = """
    defmodule KeytypeBag do
      def create do
        :ets.new(:test, [:set, keytype: :bag])
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "does not touch the tuple form {:keytype, :term} (narrow scope)" do
    input = """
    defmodule KeytypeTuple do
      def create do
        :ets.new(:test, [:set, {:keytype, :term}])
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "leaves options unchanged when passed as a variable" do
    input = """
    defmodule OptsVar do
      def create do
        opts = [keytype: :term]
        :ets.new(:test, opts)
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "removes keytype only from the affected call, preserving keypos" do
    input = """
    defmodule TwoTables do
      def create do
        :ets.new(:a, [:set, keytype: :term, keypos: 2])
        :ets.new(:b, [:bag])
      end
    end
    """

    expected = """
    defmodule TwoTables do
      def create do
        :ets.new(:a, [:set, keypos: 2])
        :ets.new(:b, [:bag])
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "preserves other options when removing keytype" do
    input = """
    defmodule ETSWithKeytype do
      def create do
        :ets.new(:test, [:ordered_set, :protected, keytype: :term])
      end
    end
    """

    expected = """
    defmodule ETSWithKeytype do
      def create do
        :ets.new(:test, [:ordered_set, :protected])
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end
end
