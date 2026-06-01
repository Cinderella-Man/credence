defmodule Credence.Semantic.FixRangeStepFixTest do
  use ExUnit.Case

  alias Credence.Semantic.FixRangeStep

  defp diag(line, col \\ 1, range \\ "0..-2") do
    %{
      severity: :warning,
      message: "#{range} has a default step of -1, please write #{range}//-1 instead",
      position: {line, col}
    }
  end

  describe "match?/1" do
    test "matches the range step diagnostic" do
      assert FixRangeStep.match?(diag(5))
    end

    test "does not match unrelated warning" do
      other = %{severity: :warning, message: "undefined function foo/0", position: {1, 1}}
      refute FixRangeStep.match?(other)
    end

    test "does not match error severity" do
      err = %{severity: :error, message: "0..-2 has a default step of -1, please write 0..-2//-1 instead", position: {1, 1}}
      refute FixRangeStep.match?(err)
    end
  end

  describe "fix/2" do
    test "replaces 0..-2 with 0..-2//-1 on the flagged line" do
      source = ~S'''
      def decode(word) do
        word_without_ay = String.slice(word, 0..-2)
        last_char = String.last(word_without_ay)
        rest = String.slice(word_without_ay, 0..-2)
        last_char <> rest
      end
      '''

      expected = ~S'''
      def decode(word) do
        word_without_ay = String.slice(word, 0..-2//-1)
        last_char = String.last(word_without_ay)
        rest = String.slice(word_without_ay, 0..-2)
        last_char <> rest
      end
      '''

      assert FixRangeStep.fix(source, diag(2)) == expected
    end

    test "fixes the correct line when diagnostic points to a different line" do
      source = ~S'''
      def decode(word) do
        word_without_ay = String.slice(word, 0..-2)
        rest = String.slice(word_without_ay, 0..-2)
        rest
      end
      '''

      expected = ~S'''
      def decode(word) do
        word_without_ay = String.slice(word, 0..-2)
        rest = String.slice(word_without_ay, 0..-2//-1)
        rest
      end
      '''

      assert FixRangeStep.fix(source, diag(3)) == expected
    end

    test "does not touch line that already has explicit step" do
      source = ~S'''
      def foo(x) do
        String.slice(x, 0..-2//-1)
      end
      '''

      assert FixRangeStep.fix(source, diag(2)) == source
    end

    test "handles range with variable start" do
      source = ~S'''
      def slice(word, n) do
        String.slice(word, n..-1)
      end
      '''

      expected = ~S'''
      def slice(word, n) do
        String.slice(word, n..-1//-1)
      end
      '''

      diag_n = %{severity: :warning, message: "n..-1 has a default step of -1, please write n..-1//-1 instead", position: {2, 1}}
      assert FixRangeStep.fix(source, diag_n) == expected
    end

    test "returns source unchanged when position is nil" do
      source = "String.slice(word, 0..-2)\n"
      bad_diag = %{severity: :warning, message: "0..-2 has a default step of -1, please write 0..-2//-1 instead", position: nil}
      assert FixRangeStep.fix(source, bad_diag) == source
    end

    test "returns source unchanged when line is out of bounds" do
      source = "String.slice(word, 0..-2)\n"
      assert FixRangeStep.fix(source, diag(99)) == source
    end
  end

end
