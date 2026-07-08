defmodule Credence.Syntax.NoAfterOrRescueInCaseAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoAfterOrRescueInCase

  defp analyze(code), do: NoAfterOrRescueInCase.analyze(code)

  test "flags case with after and rescue" do
    assert [%Issue{rule: :no_after_or_rescue_in_case}] =
             analyze("""
             defmodule TestModule do
               def run do
                 case Map.get(%{}, :key) do
                   nil ->
                     :not_found

                   value ->
                     {:ok, value}

                   # trailing comment
                 after
                   :cleanup
                 rescue
                   _ -> :error
                 end
               end
             end
             """)
  end

  test "flags case with only after" do
    assert [%Issue{rule: :no_after_or_rescue_in_case}] =
             analyze("""
             defmodule TestModule do
               def run do
                 case Map.get(%{}, :key) do
                   nil -> :not_found
                   value -> {:ok, value}
                 after
                   :cleanup
                 end
               end
             end
             """)
  end

  test "leaves normal case alone" do
    assert analyze("""
           defmodule TestModule do
             def run do
               case Map.get(%{}, :key) do
                 nil -> :not_found
                 value -> {:ok, value}
               end
             end
           end
           """) == []
  end

  test "leaves try-rescue alone" do
    assert analyze("""
           defmodule TestModule do
             def run do
               try do
                 case Map.get(%{}, :key) do
                   nil -> :not_found
                   value -> {:ok, value}
                 end
               after
                 :cleanup
               rescue
                 _ -> :error
               end
             end
           end
           """) == []
  end
end
