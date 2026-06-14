defmodule Credence.Syntax.NoDocWithDoBlockAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoDocWithDoBlock

  defp analyze(code), do: NoDocWithDoBlock.analyze(code)

  test "flags @doc with a stray do" do
    assert [%Issue{rule: :no_doc_with_do_block, meta: %{line: 2}}] =
             analyze("""
             defmodule Solution do
               @doc "top_n_items/2" do
               def find(map, n), do: Enum.take(map, n)
             end
             """)
  end

  test "flags @moduledoc with a stray do" do
    assert [%Issue{rule: :no_doc_with_do_block, meta: %{line: 1}}] =
             analyze("""
             @moduledoc "the module" do
             """)
  end

  test "does not flag a proper @doc" do
    assert analyze("""
           @doc "top_n_items/2"
           """) == []
  end

  test "does not flag a real do block on a def" do
    assert analyze("""
           def find(map, n) do
             Enum.take(map, n)
           end
           """) == []
  end

  test "does not flag a @doc whose string ends in the word do" do
    assert analyze("""
           @doc "explains what to do"
           """) == []
  end
end
