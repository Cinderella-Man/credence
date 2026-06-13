defmodule Credence.Syntax.NoSpecDoBlockAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoSpecDoBlock

  defp analyze(code), do: NoSpecDoBlock.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :no_spec_do_block, meta: %{line: 2}}] =
             analyze("""
             defmodule Solution do
               @spec do
                 def my_sqrt(number) when number >= 0 do
                   guess = number / 2.0
                   sqrt_iterate(number, guess)
                 end
               end
             end
             """)
  end

  test "flags @spec do with nested do/end" do
    assert [%Issue{rule: :no_spec_do_block, meta: %{line: 2}}] =
             analyze("""
             defmodule Solution do
             @spec do
               def my_fun do
                 if true do
                   :ok
                 end
               end
             end
             end
             """)
  end

  test "leaves valid @spec alone" do
    assert analyze("""
           defmodule Solution do
             @spec my_sqrt(number) :: float()
             def my_sqrt(number) when number >= 0 do
               number
             end
           end
           """) == []
  end

  test "leaves good code alone" do
    assert analyze("""
           defmodule Solution do
             def hello, do: :world
           end
           """) == []
  end
end
