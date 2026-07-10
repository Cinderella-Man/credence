defmodule Credence.Syntax.NoCatchInReceiveAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoCatchInReceive

  defp analyze(code), do: NoCatchInReceive.analyze(code)

  test "flags receive with catch" do
    assert [%Issue{rule: :no_catch_in_receive}] =
             analyze("""
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
             """)
  end

  test "flags receive with catch only (no after)" do
    assert [%Issue{rule: :no_catch_in_receive}] =
             analyze("""
             defmodule Example do
               def await_result do
                 receive do
                   {:ok, result} -> {:ok, result}
                 catch
                   :exit, _ -> {:error, :timeout}
                 end
               end
             end
             """)
  end

  test "leaves valid receive with after alone" do
    assert analyze("""
           defmodule Example do
             def await_result do
               receive do
                 {:ok, result} -> {:ok, result}
               after
                 5_000 -> {:error, :timeout}
               end
             end
           end
           """) == []
  end

  test "leaves try-catch alone" do
    assert analyze("""
           defmodule Example do
             def safe_call do
               try do
                 raise "boom"
               catch
                 :exit, _ -> {:error, :exit}
               end
             end
           end
           """) == []
  end
end
