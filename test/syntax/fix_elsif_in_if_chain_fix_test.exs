defmodule Credence.Syntax.FixElsifInIfChainFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixElsifInIfChain

  defp analyze(code), do: FixElsifInIfChain.analyze(code)
  defp fix(code), do: FixElsifInIfChain.fix(code)

  test "fixes the syntax error" do
    input = ~S"""
    defmodule FixElsifInIfChain do
      def check(data, now) do
        if data.valid_from && DateTime.compare(now, data.valid_from) == :lt do
          {:error, :not_yet_valid}
        elsif data.valid_until && DateTime.compare(now, data.valid_until) == :gt do
          {:error, :expired}
        else
          :ok
        end
      end
    end
    """

    expected = ~S"""
    defmodule FixElsifInIfChain do
      def check(data, now) do
        cond do
          data.valid_from && DateTime.compare(now, data.valid_from) == :lt -> {:error, :not_yet_valid}
          data.valid_until && DateTime.compare(now, data.valid_until) == :gt -> {:error, :expired}
          true -> :ok
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = ~S"""
    defmodule FixElsifInIfChain do
      def check(data, now) do
        if data.valid_from && DateTime.compare(now, data.valid_from) == :lt do
          {:error, :not_yet_valid}
        elsif data.valid_until && DateTime.compare(now, data.valid_until) == :gt do
          {:error, :expired}
        else
          :ok
        end
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule FixElsifInIfChain do
      def check(data, now) do
        if data.valid_from && DateTime.compare(now, data.valid_from) == :lt do
          {:error, :not_yet_valid}
        elsif data.valid_until && DateTime.compare(now, data.valid_until) == :gt do
          {:error, :expired}
        else
          :ok
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
