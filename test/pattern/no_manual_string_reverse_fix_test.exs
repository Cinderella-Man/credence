defmodule Credence.Pattern.NoManualStringReverseFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoManualStringReverse

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoManualStringReverse, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "NoManualStringReverse - fix" do
    test "fixes simple pipeline" do
      input = """
      defmodule Example do
        def reverse(str), do: str |> String.graphemes() |> Enum.reverse() |> Enum.join()
      end
      """

      expected = """
      defmodule Example do
        def reverse(str), do: String.reverse(str)
      end
      """

      assert fix(input) == expected
    end

    test "fixes nested call form" do
      input = """
      defmodule Example do
        def reverse(str), do: Enum.join(Enum.reverse(String.graphemes(str)))
      end
      """

      expected = """
      defmodule Example do
        def reverse(str), do: String.reverse(str)
      end
      """

      assert fix(input) == expected
    end

    test "fixes pipeline with preceding steps" do
      input = """
      defmodule Example do
        def reverse(str) do
          str
          |> String.trim()
          |> String.graphemes()
          |> Enum.reverse()
          |> Enum.join()
        end
      end
      """

      expected = """
      defmodule Example do
        def reverse(str) do
          str
          |> String.trim()
          |> String.reverse()
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes direct graphemes call in pipeline" do
      input = """
      defmodule Example do
        def reverse(str), do: String.graphemes(str) |> Enum.reverse() |> Enum.join()
      end
      """

      expected = """
      defmodule Example do
        def reverse(str), do: String.reverse(str)
      end
      """

      assert fix(input) == expected
    end

    test "fixes multiple occurrences" do
      input = """
      defmodule Example do
        def reverse_both(a, b) do
          r1 = a |> String.graphemes() |> Enum.reverse() |> Enum.join()
          r2 = Enum.join(Enum.reverse(String.graphemes(b)))
          {r1, r2}
        end
      end
      """

      expected = """
      defmodule Example do
        def reverse_both(a, b) do
          r1 = String.reverse(a)
          r2 = String.reverse(b)
          {r1, r2}
        end
      end
      """

      assert fix(input) == expected
    end

    test "preserves pipeline steps after Enum.join" do
      input = """
      defmodule Example do
        def reverse(str), do: str |> String.graphemes() |> Enum.reverse() |> Enum.join() |> String.trim()
      end
      """

      expected = """
      defmodule Example do
        def reverse(str), do: String.reverse(str) |> String.trim()
      end
      """

      assert fix(input) == expected
    end

    test "preserves pipeline steps before graphemes" do
      input = """
      defmodule Example do
        def reverse(str) do
          str
          |> String.downcase()
          |> String.trim()
          |> String.graphemes()
          |> Enum.reverse()
          |> Enum.join()
        end
      end
      """

      expected = """
      defmodule Example do
        def reverse(str) do
          str
          |> String.downcase()
          |> String.trim()
          |> String.reverse()
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes inside fn body" do
      input = """
      Enum.map(list, fn x ->
        x |> String.graphemes() |> Enum.reverse() |> Enum.join()
      end)
      """

      expected = """
      Enum.map(list, fn x ->
        String.reverse(x)
      end)
      """

      assert fix(input) == expected
    end

    test "does not modify code already using String.reverse/1" do
      code = """
      defmodule GoodPalindrome do
        def is_palindrome(s) do
          cleaned = String.downcase(s)
          cleaned == String.reverse(cleaned)
        end
      end
      """

      assert fix(code) == code
    end

    test "does not modify Enum.join with separator" do
      code = """
      defmodule Example do
        def reverse(str), do: str |> String.graphemes() |> Enum.reverse() |> Enum.join("-")
      end
      """

      assert fix(code) == code
    end

    test "does not modify unrelated pipelines" do
      code = """
      defmodule Example do
        def process(list), do: list |> Enum.reverse() |> Enum.join()
      end
      """

      assert fix(code) == code
    end
  end

  describe "graphemes + IO.iodata_to_binary reassemble (always-safe, no promise)" do
    test "fixes graphemes |> reverse |> IO.iodata_to_binary pipeline" do
      input = """
      def reverse(str), do: str |> String.graphemes() |> Enum.reverse() |> IO.iodata_to_binary()
      """

      expected = """
      def reverse(str), do: String.reverse(str)
      """

      assert fix(input) == expected
    end

    test "does NOT touch codepoints (handled by NoCodepointStringReverse)" do
      code = """
      def reverse(str), do: str |> String.codepoints() |> Enum.reverse() |> Enum.join()
      """

      assert fix(code) == code
    end
  end
end
