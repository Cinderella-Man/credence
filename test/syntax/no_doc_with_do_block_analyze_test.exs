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
             analyze(~S'@moduledoc "the module" do')
  end

  test "does not flag a proper @doc" do
    assert analyze(~S'@doc "top_n_items/2"') == []
  end

  test "does not flag a real do block on a def" do
    assert analyze("""
           def find(map, n) do
             Enum.take(map, n)
           end
           """) == []
  end

  test "does not flag a @doc whose string ends in the word do" do
    assert analyze(~S'@doc "explains what to do"') == []
  end

  test "does not flag an expression-valued @doc whose first line ends in do" do
    # `@doc (if .. do .. end)` is valid, compiling code; the value is an
    # expression, not a string literal, so the narrowed rule leaves it alone.
    assert analyze("""
           @doc (if prod? do
                   "prod"
                 else
                   "dev"
                 end)
           """) == []
  end
end
