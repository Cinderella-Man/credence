defmodule Credence.Syntax.NoRescueOrCatchOutsideTryFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoRescueOrCatchOutsideTry

  defp analyze(code), do: NoRescueOrCatchOutsideTry.analyze(code)
  defp fix(code), do: NoRescueOrCatchOutsideTry.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule M do
      def verify(payload, secret) when is_binary(payload) and is_binary(secret) do
        expected = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
        if payload == "ok" do
          :ok
        else
          :error
        end
      rescue
        _ -> :error
      end
    end
    """

    expected = """
    defmodule M do
      def verify(payload, secret) when is_binary(payload) and is_binary(secret) do
        try do
          expected = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
          if payload == "ok" do
            :ok
          else
            :error
          end
        rescue
          _ -> :error
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    defmodule M do
      def verify(x) do
        x
      rescue
        _ -> :error
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def verify(x) do
        x
      rescue
        _ -> :error
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
