defmodule Credence.Semantic.FixMixedAritiesInAnonFnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.RuleHelpers
  alias Credence.Semantic
  alias Credence.Semantic.FixMixedAritiesInAnonFn

  @real_diag_msg "cannot mix clauses with different arities in anonymous functions"

  defp fix(source, message \\ @real_diag_msg, line \\ 1) do
    FixMixedAritiesInAnonFn.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "pads shorter fn clause to max arity, reusing the variable its body needs" do
    input = ~S"""
    defmodule MixedArityFn do
      def process(items) do
        Enum.reduce(items, [], fn {name, val}, acc -> [{name, val} | acc] ; _ -> acc end)
      end
    end
    """

    expected = ~S"""
    defmodule MixedArityFn do
      def process(items) do
        Enum.reduce(items, [], fn
          {name, val}, acc -> [{name, val} | acc]
          _, acc -> acc
        end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule MixedArityFn do
      def process(items) do
        Enum.reduce(items, [], fn {name, val}, acc -> [{name, val} | acc] ; _ -> acc end)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "pads with _ when the shorter clause's body does not use the candidate name" do
    input = ~S"""
    f = fn x, y -> x + y; _ -> 0 end
    """

    expected = ~S"""
    f = fn
      x, y -> x + y
      _, _ -> 0
    end
    """

    confirm_fix(fix(input), expected)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(fix(input))
  end

  test "does not reuse a padding candidate already bound by the shorter clause" do
    input = "f = fn x, y -> x; y -> y end"

    expected = ~S"""
    f = fn
      x, y -> x
      y, _ -> y
    end
    """

    fixed = fix(input)
    confirm_fix(fixed, expected)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(fixed)
  end

  test "reuses a padding candidate referenced by the shorter clause's guard" do
    input = "f = fn x, y -> x; x when y > 0 -> x end"

    expected = ~S"""
    f = fn
      x, y -> x
      x, y when y > 0 -> x
    end
    """

    fixed = fix(input)
    confirm_fix(fixed, expected)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(fixed)
  end

  test "counts a guarded clause's real arity through its when node" do
    input = ~S"""
    f = fn a, b when a > 0 -> a + b; x -> x end
    """

    expected = ~S"""
    f = fn
      a, b when a > 0 -> a + b
      x, _ -> x
    end
    """

    confirm_fix(fix(input), expected)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(fix(input))
  end

  test "pads a guarded shorter clause before its guard" do
    input = ~S"""
    f = fn a, b, c -> a; x when x > 0 -> x end
    """

    expected = ~S"""
    f = fn
      a, b, c -> a
      x, _, _ when x > 0 -> x
    end
    """

    confirm_fix(fix(input), expected)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(fix(input))
  end

  test "pads a zero-arity clause" do
    input = ~S"""
    f = fn -> :a; x -> x + 1 end
    """

    expected = ~S"""
    f = fn
      _ -> :a
      x -> x + 1
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes a mixed-arity fn nested inside a uniform multi-clause fn" do
    input = ~S"""
    g = fn
      :a -> fn x, y -> x + y; _ -> 0 end
      :b -> nil
    end
    """

    expected = ~S"""
    g = fn
      :a ->
        fn
          x, y -> x + y
          _, _ -> 0
        end

      :b ->
        nil
    end
    """

    confirm_fix(fix(input), expected)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(fix(input))
  end

  test "does not alter fn clauses that already have equal arity" do
    input = ~S"""
    fn x -> x + 1; y -> y * 2 end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves a clause with a misplaced when between parameters alone" do
    input = ~S"""
    f = fn {k, v} when k > 0, acc -> acc + v; x -> x end
    """

    confirm_fix(fix(input), input)
  end

  test "should_report? is false when the fix would not rewrite the source" do
    input = ~S"""
    f = fn {k, v} when k > 0, acc -> acc + v; x -> x end
    """

    diag = %{severity: :error, message: @real_diag_msg, position: {1, 1}}

    refute FixMixedAritiesInAnonFn.should_report?(diag, input)
  end

  test "should_report? is true when the fix rewrites the source" do
    input = ~S"""
    f = fn x, y -> x + y; _ -> 0 end
    """

    diag = %{severity: :error, message: @real_diag_msg, position: {1, 1}}

    assert FixMixedAritiesInAnonFn.should_report?(diag, input)
  end

  test "the Semantic dispatcher repairs the compiler's mixed-arity diagnostic" do
    input = ~S"""
    defmodule MixedArityFnDispatcherFixture do
      def build do
        fn x, y -> x + y; _ -> 0 end
      end
    end
    """

    expected = ~S"""
    defmodule MixedArityFnDispatcherFixture do
      def build do
        fn
          x, y -> x + y
          _, _ -> 0
        end
      end
    end
    """

    assert {:error, diagnostics} = RuleHelpers.compile_and_capture(input)

    assert Enum.any?(diagnostics, fn diagnostic ->
             diagnostic.severity == :error and diagnostic.message == @real_diag_msg
           end)

    assert {fixed, [{FixMixedAritiesInAnonFn, 1}]} = Semantic.fix_with_trace(input)

    confirm_fix(fixed, expected)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(fixed)
  end
end
