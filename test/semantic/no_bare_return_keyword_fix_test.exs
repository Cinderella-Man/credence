defmodule Credence.Semantic.NoBareReturnKeywordFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoBareReturnKeyword

  @message "undefined variable \"return\""

  defp fix(source, line) do
    NoBareReturnKeyword.fix(source, %{severity: :error, message: @message, position: {line, 1}})
  end

  @input ~S'''
  defmodule Example do
    def check(value) do
      unless value == :ok do
        IO.puts("error")
        halt()
        return
      end
      IO.puts("proceeding")
    end

    defp halt, do: :halted
  end
  '''

  @expected ~S'''
  defmodule Example do
    def check(value) do
      unless value == :ok do
        IO.puts("error")
        halt()
      end
      IO.puts("proceeding")
    end

    defp halt, do: :halted
  end
  '''

  test "removes a bare return from a block" do
    confirm_fix(fix(@input, 6), @expected)
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix(@input, 6))
  end

  test "ignores a line that is not a bare return" do
    source = ~S'IO.puts("return")'
    confirm_fix(fix(source, 1), source)
  end

  test "ignores return with arguments" do
    source = "return(:ok)"
    confirm_fix(fix(source, 1), source)
  end

  test "handles return with leading whitespace" do
    input = "  return"
    confirm_fix(fix(input, 1), "")
  end
end
