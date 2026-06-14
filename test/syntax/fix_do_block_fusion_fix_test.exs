defmodule Credence.Syntax.FixDoBlockFusionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixDoBlockFusion

  defp fix(code), do: FixDoBlockFusion.fix(code)
  defp analyze(code), do: FixDoBlockFusion.analyze(code)

  test "comma-do at end of line becomes a do block" do
    confirm_fix(
      fix("""
      defmodule Solution do
        def push(stack, value), do
          [value | stack]
        end
      end
      """),
      """
      defmodule Solution do
        def push(stack, value) do
          [value | stack]
        end
      end
      """
    )
  end

  test "doubled do opener collapses to one" do
    confirm_fix(
      fix("""
      defmodule Solution do
        def double(n) do do
          n * 2
        end
      end
      """),
      """
      defmodule Solution do
        def double(n) do
          n * 2
        end
      end
      """
    )
  end

  test "do: fused after paren with trailing end becomes a comma one-liner" do
    confirm_fix(
      fix("""
      defmodule Solution do
        def double(n) do: n * 2 end
      end
      """),
      """
      defmodule Solution do
        def double(n), do: n * 2
      end
      """
    )
  end

  test "midline comma-do gains its colon" do
    confirm_fix(
      fix("""
      defmodule Solution do
        def inc(x), do x + 1
      end
      """),
      """
      defmodule Solution do
        def inc(x), do: x + 1
      end
      """
    )
  end

  test "fix output is well-formed and analyze reaches a fixpoint" do
    code = """
    defmodule Solution do
      def double(n) do: n * 2 end
    end
    """

    assert valid_syntax?(fix(code))
    assert analyze(fix(code)) == []
  end
end
