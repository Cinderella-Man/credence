defmodule Credence.Syntax.FixElsifInIfChainAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixElsifInIfChain

  defp analyze(code), do: FixElsifInIfChain.analyze(code)

  test "flags the unparseable code" do
    code = ~S"""
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

    assert [%Issue{rule: :fix_elsif_in_if_chain}] = analyze(code)
  end

  test "leaves good code alone" do
    code = ~S"""
    defmodule Foo do
      def check(x) do
        cond do
          x > 0 -> :positive
          true -> :non_positive
        end
      end
    end
    """

    assert analyze(code) == []
  end
end
