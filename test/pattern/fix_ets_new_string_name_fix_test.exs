defmodule Credence.Pattern.FixEtsNewStringNameFixTest do
  use Credence.RuleCase, async: false

  alias Credence.Pattern.FixEtsNewStringName

  describe "fix_patches/2" do
    test "does not intern source-controlled table names" do
      # Warm the parser and fixer before measuring their atom footprint.
      fix(FixEtsNewStringName, ~S':ets.new("atom_count_warmup", [])')
      before_count = :erlang.system_info(:atom_count)

      outputs =
        for i <- 1..100 do
          name = "ets_review_unique_name_#{i}"
          fix(FixEtsNewStringName, ":ets.new(\"#{name}\", [])")
        end

      assert Enum.at(outputs, 42) ==
               ~S|:ets.new(:erlang.binary_to_atom("ets_review_unique_name_43"), [])|

      assert :erlang.system_info(:atom_count) == before_count
    end

    test "converts the string to the atom" do
      confirm_fix(
        fix(FixEtsNewStringName, """
        defmodule EtsFixA do
          def start, do: :ets.new("cache", [:set])
        end
        """),
        """
        defmodule EtsFixA do
          def start, do: :ets.new(:erlang.binary_to_atom("cache"), [:set])
        end
        """
      )
    end

    test "leaves the option list untouched" do
      confirm_fix(
        fix(FixEtsNewStringName, """
        defmodule EtsFixB do
          def start, do: :ets.new("my_cache", [:set, :named_table, {:keypos, 2}])
        end
        """),
        """
        defmodule EtsFixB do
          def start, do: :ets.new(:erlang.binary_to_atom("my_cache"), [:set, :named_table, {:keypos, 2}])
        end
        """
      )
    end

    test "converts every occurrence" do
      confirm_fix(
        fix(FixEtsNewStringName, """
        defmodule EtsFixC do
          def a, do: :ets.new("one", [:set])
          def b, do: :ets.new("two", [:bag])
        end
        """),
        """
        defmodule EtsFixC do
          def a, do: :ets.new(:erlang.binary_to_atom("one"), [:set])
          def b, do: :ets.new(:erlang.binary_to_atom("two"), [:bag])
        end
        """
      )
    end

    test "the fix output parses" do
      assert valid_syntax?(
               fix(FixEtsNewStringName, """
               defmodule EtsFixD do
                 def start, do: :ets.new("cache", [:set])
               end
               """)
             )
    end
  end

  describe "declines" do
    test "an atom name is left byte-identical" do
      source = """
      defmodule EtsFixE do
        def start, do: :ets.new(:cache, [:set])
      end
      """

      confirm_fix(fix(FixEtsNewStringName, source), source)
    end

    test "a non-literal name is left byte-identical" do
      source = """
      defmodule EtsFixF do
        def start(name), do: :ets.new(name, [:set])
      end
      """

      confirm_fix(fix(FixEtsNewStringName, source), source)
    end

    test "a name that is not a bare atom is left byte-identical" do
      source = """
      defmodule EtsFixG do
        def start, do: :ets.new("my table", [:set])
      end
      """

      confirm_fix(fix(FixEtsNewStringName, source), source)
    end
  end
end
