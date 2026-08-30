defmodule Credence.Pattern.NoHallucinatedEtsKeytypeOptionFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoHallucinatedEtsKeytypeOption

  test "removes keytype: :term and keeps every real option" do
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

    confirm_fix(fix(NoHallucinatedEtsKeytypeOption, input), expected)
  end

  # Regression pin. The first Pattern implementation emitted the patch at the
  # bare list's range, which starts one column *inside* the `[`, while the
  # replacement text carries its own brackets — producing
  # `:ets.new(:a, [[:set, keypos: 2]])`. The safety invariants did not catch it:
  # the double-wrapped list parses and preserves every comment.
  test "patches at the bracket, not inside it — the list is not double-wrapped" do
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

    confirm_fix(fix(NoHallucinatedEtsKeytypeOption, input), expected)
  end

  test "preserves the other options when keytype is last" do
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

    confirm_fix(fix(NoHallucinatedEtsKeytypeOption, input), expected)
  end

  test "leaves keytype with a non-:term value unchanged" do
    input = """
    defmodule KeytypeBag do
      def create do
        :ets.new(:test, [:set, keytype: :bag])
      end
    end
    """

    confirm_fix(fix(NoHallucinatedEtsKeytypeOption, input), input)
  end

  test "leaves the tuple form {:keytype, :term} unchanged" do
    input = """
    defmodule KeytypeTuple do
      def create do
        :ets.new(:test, [:set, {:keytype, :term}])
      end
    end
    """

    confirm_fix(fix(NoHallucinatedEtsKeytypeOption, input), input)
  end

  test "leaves options passed as a variable unchanged" do
    input = """
    defmodule OptsVar do
      def create do
        opts = [keytype: :term]
        :ets.new(:test, opts)
      end
    end
    """

    confirm_fix(fix(NoHallucinatedEtsKeytypeOption, input), input)
  end

  test "output parses" do
    input = """
    defmodule ParsesAfterFix do
      def create do
        :ets.new(:test, [:set, keytype: :term, keypos: 2])
      end
    end
    """

    assert valid_syntax?(fix(NoHallucinatedEtsKeytypeOption, input))
  end
end
