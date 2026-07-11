defmodule Credence.Semantic.FixInvalidCaptureWithLiteralFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixInvalidCaptureWithLiteral

  @real_message "invalid args for &, expected one of:\n\n  * &Mod.fun/arity to capture a remote function, such as &Enum.map/2\n  * &fun/arity to capture a local or imported function, such as &is_atom/1\n  * &some_code(&1, ...) containing at least one argument as &1, such as &List.flatten(&1)\n\nGot: true"

  defp fix(source, message \\ @real_message, line \\ 1) do
    FixInvalidCaptureWithLiteral.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  describe "fix/2" do
    test "fixes &true to fn _ -> true end" do
      input = """
      defmodule M do
        def f, do: List.update_at([1, 2, 3], 0, &true)
      end
      """

      expected = """
      defmodule M do
        def f, do: List.update_at([1, 2, 3], 0, fn _ -> true end)
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "fixes &false to fn _ -> false end" do
      input = """
      defmodule M do
        def f, do: Enum.map([1, 2], &false)
      end
      """

      expected = """
      defmodule M do
        def f, do: Enum.map([1, 2], fn _ -> false end)
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "fixes &:atom to fn _ -> :atom end" do
      input = """
      defmodule M do
        def f, do: Enum.map([1, 2], &:atom)
      end
      """

      expected = """
      defmodule M do
        def f, do: Enum.map([1, 2], fn _ -> :atom end)
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "fixes &nil to fn _ -> nil end" do
      input = """
      defmodule M do
        def f, do: Enum.map([1, 2], &nil)
      end
      """

      expected = """
      defmodule M do
        def f, do: Enum.map([1, 2], fn _ -> nil end)
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "leaves valid capture &Mod.fun/arity unchanged" do
      input = """
      defmodule M do
        def f, do: Enum.map([1, 2], &Integer.to_string/1)
      end
      """

      confirm_fix(fix(input), input)
    end

    test "leaves valid capture &(&1 + 1) unchanged" do
      input = """
      defmodule M do
        def f, do: Enum.map([1, 2], &(&1 + 1))
      end
      """

      confirm_fix(fix(input), input)
    end

    test "leaves valid capture &is_atom/1 unchanged" do
      input = """
      defmodule M do
        def f, do: Enum.map([1, 2], &is_atom/1)
      end
      """

      confirm_fix(fix(input), input)
    end

    test "fixes &System.os_time(:second/0) to fn -> System.os_time(:second) end" do
      input = """
      defmodule CaptureBug do
        def get_clock(opts) do
          Keyword.get(opts, :clock, &System.os_time(:second/0))
        end
      end
      """

      expected = """
      defmodule CaptureBug do
        def get_clock(opts) do
          Keyword.get(opts, :clock, fn -> System.os_time(:second) end)
        end
      end
      """

      confirm_fix(fix(input), expected)
    end
  end

  describe "fix output is well-formed" do
    test "fixed output parses" do
      input = """
      defmodule M do
        def f, do: List.update_at([1, 2, 3], 0, &true)
      end
      """

      assert valid_syntax?(fix(input))
    end

    test "fixed output parses for &false" do
      input = """
      defmodule M do
        def f, do: Enum.map([1, 2], &false)
      end
      """

      assert valid_syntax?(fix(input))
    end

    test "fixed output parses for &System.os_time(:second/0)" do
      input = """
      defmodule CaptureBug do
        def get_clock(opts) do
          Keyword.get(opts, :clock, &System.os_time(:second/0))
        end
      end
      """

      assert valid_syntax?(fix(input))
    end
  end

  describe "no-ops" do
    test "returns source unchanged when no capture pattern present" do
      input = """
      defmodule M do
        def f, do: :ok
      end
      """

      confirm_fix(fix(input), input)
    end
  end
end
