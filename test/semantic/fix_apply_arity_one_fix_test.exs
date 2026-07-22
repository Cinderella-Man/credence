defmodule Credence.Semantic.FixApplyArityOneFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixApplyArityOne

  @msg "undefined function apply/1 (expected FixApplyArityOneExample to define such a function or for it to be imported, but none are available)"

  defp fix(source, line) do
    FixApplyArityOne.fix(source, %{severity: :error, message: @msg, position: {line, 1}})
  end

  test "fixes apply(func) to apply(func, [])" do
    input = """
    defmodule FixApplyArityOneExample do
      def call_clock(state) do
        current_time = apply(state.clock)
        current_time
      end
    end
    """

    expected = """
    defmodule FixApplyArityOneExample do
      def call_clock(state) do
        current_time = apply(state.clock, [])
        current_time
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "fixes nested apply(apply(f)) on the diagnostic line" do
    input = """
    defmodule FixApplyArityOneExample do
      def run(f) do
        apply(apply(f))
      end
    end
    """

    expected = """
    defmodule FixApplyArityOneExample do
      def run(f) do
        apply(apply(f, []), [])
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "fixes the piped form x |> apply() into x |> apply([])" do
    input = """
    defmodule FixApplyArityOneExample do
      def run(g) do
        g |> apply()
      end
    end
    """

    expected = """
    defmodule FixApplyArityOneExample do
      def run(g) do
        g |> apply([])
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "fixes the parenless piped form x |> apply" do
    input = """
    defmodule FixApplyArityOneExample do
      def run(g) do
        g |> apply
      end
    end
    """

    expected = """
    defmodule FixApplyArityOneExample do
      def run(g) do
        g |> apply([])
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "never adds an argument to a valid x |> apply(f) on the same line" do
    input = """
    defmodule FixApplyArityOneExample do
      def run(x, f) do
        {x |> apply(f), apply(x)}
      end
    end
    """

    expected = """
    defmodule FixApplyArityOneExample do
      def run(x, f) do
        {x |> apply(f), apply(x, [])}
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "only rewrites the diagnostic line, not other apply/1 calls" do
    input = """
    defmodule FixApplyArityOneExample do
      def a(f), do: apply(f)
      def b(g), do: apply(g)
    end
    """

    expected = """
    defmodule FixApplyArityOneExample do
      def a(f), do: apply(f, [])
      def b(g), do: apply(g)
    end
    """

    confirm_fix(fix(input, 2), expected)
  end

  test "leaves apply inside a quote block on another line untouched" do
    input = """
    defmodule FixApplyArityOneExample do
      defmacro gen(f) do
        quote do: apply(unquote(f))
      end

      def run(g), do: apply(g)
    end
    """

    expected = """
    defmodule FixApplyArityOneExample do
      defmacro gen(f) do
        quote do: apply(unquote(f))
      end

      def run(g), do: apply(g, [])
    end
    """

    confirm_fix(fix(input, 6), expected)
  end

  test "no issue: bails entirely when the file defines apply itself" do
    input = """
    defmodule ApplyOwner do
      def apply(x), do: x
    end

    defmodule FixApplyArityOneExample do
      def run(g), do: apply(g)
    end
    """

    confirm_fix(fix(input, 6), input)
  end

  test "no issue: bails entirely when the file defdelegates apply" do
    input = """
    defmodule ApplyOwner do
      defdelegate apply(x), to: Kernel, as: :to_string
    end

    defmodule FixApplyArityOneExample do
      def run(g), do: apply(g)
    end
    """

    confirm_fix(fix(input, 6), input)
  end

  test "no issue: leaves the capture &apply/1 alone" do
    input = """
    defmodule FixApplyArityOneExample do
      def run(_), do: &apply/1
    end
    """

    confirm_fix(fix(input, 2), input)
  end

  test "no issue: leaves an apply do-block call alone" do
    input = """
    defmodule FixApplyArityOneExample do
      def run(x) do
        apply do
          x
        end
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule FixApplyArityOneExample do
      def call_clock(state) do
        current_time = apply(state.clock)
        current_time
      end
    end
    """

    assert valid_syntax?(fix(input, 3))
  end
end
