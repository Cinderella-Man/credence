defmodule Credence.Semantic.FixCyclicStructReferenceNestedTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.RuleHelpers
  alias Credence.Semantic.FixCyclicStructReference

  # The NESTED scope. The rule shipped handling only top-level siblings, and on a nested
  # definition it REPORTED and then declined — `analyze/1` returned the issue while
  # `fix/2` returned `:no_op`, which is the report-without-fix shape this project does not
  # ship. `fix_or_drop_test` cannot see it: that gate asks whether a rule fixes nothing
  # at all, and the top-level scope always worked.

  defp diagnostic(message) do
    %{severity: :error, message: message, position: {2, 1}}
  end

  defp fix(source, name \\ "NestedU") do
    FixCyclicStructReference.fix(
      source,
      diagnostic("#{name}.__struct__/1 is undefined, cannot expand struct #{name}")
    )
  end

  defp compiles?(source), do: match?({:ok, _diagnostics}, RuleHelpers.compile_and_capture(source))

  describe "hoists a struct-defining nested module above its first use" do
    test "the bare-alias spelling" do
      input = """
      defmodule NestedBare do
        def build, do: %NestedU{name: "x"}

        defmodule NestedU do
          defstruct [:name]
        end
      end
      """

      fixed = fix(input)

      refute compiles?(input)
      assert compiles?(fixed)
      assert valid_syntax?(fixed)

      # The definition now precedes the use.
      assert :binary.match(fixed, "defmodule NestedU") < :binary.match(fixed, "%NestedU{")
    end

    # `%Outer.U{}` names the same module as `%U{}` once the definition is in scope, so a
    # reference must match a nested definition by either spelling — the qualified form is
    # what `body_deps/2` needs the outer name for.
    test "the outer-qualified spelling" do
      input = """
      defmodule NestedQual do
        def build, do: %NestedQual.NestedQU{name: "x"}

        defmodule NestedQU do
          defstruct [:name]
        end
      end
      """

      fixed = fix(input, "NestedQual.NestedQU")

      refute compiles?(input)
      assert compiles?(fixed)

      assert :binary.match(fixed, "defmodule NestedQU") <
               :binary.match(fixed, "%NestedQual.NestedQU{")
    end

    test "other statements in the body keep their order" do
      input = """
      defmodule NestedOrder do
        @answer 42

        def build, do: %NestedOrderU{name: "x"}

        defmodule NestedOrderU do
          defstruct [:name]
        end

        def answer, do: @answer
      end
      """

      fixed = fix(input, "NestedOrderU")

      expected = """
      defmodule NestedOrder do
        @answer 42

        defmodule NestedOrderU do
          defstruct [:name]
        end

        def build, do: %NestedOrderU{name: "x"}

        def answer, do: @answer
      end
      """

      assert compiles?(fixed)
      confirm_fix(fixed, expected)
      assert :binary.match(fixed, "@answer 42") < :binary.match(fixed, "defmodule NestedOrderU")

      assert :binary.match(fixed, "defmodule NestedOrderU") <
               :binary.match(fixed, "%NestedOrderU{")
    end

    test "does not move a later module attribute before the blocked function" do
      input = """
      defmodule NestedAttributeOrder do
        @x 1
        def build, do: %NestedAttributeOrder.U{x: @x}
        defmodule U, do: defstruct([:x])
        @x 2
      end
      """

      fixed = fix(input, "NestedAttributeOrder.U")
      assert Process.register(self(), :csr_nested_attribute_receiver)

      probe =
        fixed <>
          "\nsend(:csr_nested_attribute_receiver, {:nested_attribute_result, NestedAttributeOrder.build()})\n"

      assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(probe)
      assert_receive {:nested_attribute_result, %{__struct__: NestedAttributeOrder.U, x: 1}}

      expected = """
      defmodule NestedAttributeOrder do
        @x 1

        defmodule U, do: defstruct([:x])

        def build, do: %NestedAttributeOrder.U{x: @x}

        @x 2
      end
      """

      confirm_fix(fixed, expected)
    end
  end

  describe "the top-level scope still works" do
    test "the original fixture is unaffected by the nested path" do
      input = """
      defmodule NestedTopFactory do
        def build, do: %NestedTopUser{name: "test"}
      end

      defmodule NestedTopUser do
        defstruct [:name]
      end
      """

      fixed = fix(input, "NestedTopUser")

      refute compiles?(input)
      assert compiles?(fixed)

      assert :binary.match(fixed, "defmodule NestedTopUser") <
               :binary.match(fixed, "defmodule NestedTopFactory")
    end
  end

  describe "declines, byte for byte" do
    # A reorder rebuilds the body from statement line ranges, so anything between two
    # statements that is not part of one would be dropped. A comment is exactly that.
    test "a comment between the body's statements" do
      input = """
      defmodule NestedComment do
        def build, do: %NestedCommentU{name: "x"}

        # this comment would be dropped by a naive rebuild
        defmodule NestedCommentU do
          defstruct [:name]
        end
      end
      """

      confirm_fix(fix(input, "NestedCommentU"), input)
    end

    test "a nested module already defined before its use" do
      input = """
      defmodule NestedFine do
        defmodule NestedFineU do
          defstruct [:name]
        end

        def build, do: %NestedFineU{name: "x"}
      end
      """

      confirm_fix(fix(input, "NestedFineU"), input)
    end

    test "a nested module that defines no struct" do
      input = """
      defmodule NestedNoStruct do
        def build, do: %NestedNoStructU{name: "x"}

        defmodule NestedNoStructU do
          def hello, do: :world
        end
      end
      """

      confirm_fix(fix(input, "NestedNoStructU"), input)
    end

    test "source that does not parse" do
      input = """
      defmodule NestedBroken do
        def f(, do: 1
      """

      confirm_fix(fix(input, "Whatever"), input)
    end
  end

  # `should_report?` is not defined on this rule, so `analyze` reports whenever the
  # diagnostic matches. With the nested scope covered, the shape it used to report and
  # decline now round-trips: reported, then actually repaired.
  describe "end to end, the report is now backed by a repair" do
    test "analyze reports it and fix repairs it" do
      source = """
      defmodule NestedE2E do
        def build, do: %NestedE2EU{name: "x"}

        defmodule NestedE2EU do
          defstruct [:name]
        end
      end
      """

      analysis = Credence.analyze(source)
      assert :fix_cyclic_struct_reference in Enum.map(analysis.issues, & &1.rule)

      result = Credence.fix(source, analyze_after: false)

      assert {FixCyclicStructReference, 1} in result.applied_rules
      assert compiles?(result.code)
    end
  end
end
