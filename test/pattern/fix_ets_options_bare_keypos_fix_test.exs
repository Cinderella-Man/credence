defmodule Credence.Pattern.FixEtsOptionsBareKeyposFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.FixEtsOptionsBareKeypos

  describe "fix_patches/2" do
    test "wraps the pair into a tuple" do
      confirm_fix(
        fix(FixEtsOptionsBareKeypos, """
        defmodule KpFixA do
          def start, do: :ets.new(:records, [:set, :keypos, 2])
        end
        """),
        """
        defmodule KpFixA do
          def start, do: :ets.new(:records, [:set, {:keypos, 2}])
        end
        """
      )
    end

    # The integer must be CONSUMED by the pair, not left behind as its own
    # element — which is what a naive chunking pass would do.
    test "the surrounding options keep their order and count" do
      confirm_fix(
        fix(FixEtsOptionsBareKeypos, """
        defmodule KpFixB do
          def start, do: :ets.new(:records, [:named_table, :set, :keypos, 3, :public])
        end
        """),
        """
        defmodule KpFixB do
          def start, do: :ets.new(:records, [:named_table, :set, {:keypos, 3}, :public])
        end
        """
      )
    end

    test "the fix output parses" do
      assert valid_syntax?(
               fix(FixEtsOptionsBareKeypos, """
               defmodule KpFixC do
                 def start, do: :ets.new(:records, [:set, :keypos, 2])
               end
               """)
             )
    end
  end

  describe "declines" do
    test "an already-tupled :keypos is left byte-identical" do
      source = """
      defmodule KpFixD do
        def start, do: :ets.new(:records, [:set, {:keypos, 2}])
      end
      """

      confirm_fix(fix(FixEtsOptionsBareKeypos, source), source)
    end

    test "a :keypos followed by a variable is left byte-identical" do
      source = """
      defmodule KpFixE do
        def start(n), do: :ets.new(:records, [:set, :keypos, n])
      end
      """

      confirm_fix(fix(FixEtsOptionsBareKeypos, source), source)
    end
  end
end
