defmodule Credence.Syntax.NoCatchInReceiveFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoCatchInReceive

  defp analyze(code), do: NoCatchInReceive.analyze(code)
  defp fix(code), do: NoCatchInReceive.fix(code)

  test "fixes receive with catch and after" do
    input = """
    defmodule Example do
      def await_result do
        receive do
          {:ok, result} -> {:ok, result}
        catch
          :exit, _ -> {:error, :timeout}
        after
          5_000 -> {:error, :timeout}
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def await_result do
        receive do
          {:ok, result} -> {:ok, result}
        after
          5_000 -> {:error, :timeout}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes receive with catch only (no after)" do
    input = """
    defmodule Example do
      def await_result do
        receive do
          {:ok, result} -> {:ok, result}
        catch
          :exit, _ -> {:error, :timeout}
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def await_result do
        receive do
          {:ok, result} -> {:ok, result}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("""
           defmodule Example do
             def await_result do
               receive do
                 {:ok, result} -> {:ok, result}
               catch
                 :exit, _ -> {:error, :timeout}
               after
                 5_000 -> {:error, :timeout}
               end
             end
           end
           """)) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("""
           defmodule Example do
             def await_result do
               receive do
                 {:ok, result} -> {:ok, result}
               catch
                 :exit, _ -> {:error, :timeout}
               after
                 5_000 -> {:error, :timeout}
               end
             end
           end
           """))
  end

  test "leaves already-clean source unchanged" do
    input = """
    defmodule Example do
      def await_result do
        receive do
          {:ok, result} -> {:ok, result}
        after
          5_000 -> {:error, :timeout}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves try-catch unchanged" do
    input = """
    defmodule Example do
      def safe_call do
        try do
          raise "boom"
        catch
          :exit, _ -> {:error, :exit}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
