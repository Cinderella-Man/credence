defmodule Credence.Syntax.PreferSingleDocAttributeAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.PreferSingleDocAttribute

  defp analyze(code), do: PreferSingleDocAttribute.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :prefer_single_doc_attribute, meta: %{line: 2}}] =
             analyze("""
             defmodule Solution do
               @doc """
               @doc "Returns the length of the longest contiguous subarray."
               def longest_equal_zero_one(list) do
                 :ok
               end
             end
             """)
  end

  test "leaves good code alone" do
    assert analyze("""
           defmodule Solution do
             @doc "Returns the length of the longest contiguous subarray."
             def longest_equal_zero_one(list) do
               :ok
             end
           end
           """) == []
  end

  test "leaves proper heredoc alone" do
    assert analyze("""
           defmodule Solution do
             @doc \"\"\"
             Returns the length of the longest contiguous subarray.
             \"\"\"
             def longest_equal_zero_one(list) do
               :ok
             end
           end
           """) == []
  end
end
