defmodule Credence.Rule.NoStringConcatInLoopTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoStringConcatInLoop.check(ast, [])
  end

  describe "NoStringConcatInLoop" do
    test "passes code using iodata accumulation" do
      code = """
      defmodule Good do
        def build(graphemes) do
          graphemes
          |> Enum.reduce([], fn char, acc -> [char | acc] end)
          |> Enum.reverse()
          |> IO.iodata_to_binary()
        end
      end
      """

      assert check(code) == []
    end

    test "passes code using Enum.join" do
      code = """
      defmodule Good do
        def build(graphemes) do
          Enum.join(graphemes)
        end
      end
      """

      assert check(code) == []
    end

    test "passes <> outside of loops" do
      code = """
      defmodule Safe do
        def greet(name) do
          "Hello, " <> name <> "!"
        end
      end
      """

      assert check(code) == []
    end

    test "detects <> inside Enum.reduce" do
      code = """
      defmodule Bad do
        def build(list) do
          Enum.reduce(list, "", fn char, acc ->
            acc <> char
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) >= 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_string_concat_in_loop
      assert issue.severity == :warning
      assert issue.message =~ "iodata"
      assert issue.meta.line != nil
    end

    test "detects <> inside Enum.reduce_while" do
      code = """
      defmodule Bad do
        def build_prefix(chars, strs) do
          Enum.reduce_while(chars, "", fn char, prefix ->
            candidate = prefix <> char
            if Enum.all?(strs, &String.starts_with?(&1, candidate)) do
              {:cont, candidate}
            else
              {:halt, prefix}
            end
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) >= 1
      assert hd(issues).rule == :no_string_concat_in_loop
    end

    test "detects <> inside for comprehension" do
      code = """
      defmodule Bad do
        def build(chars) do
          for char <- chars, reduce: "" do
            acc -> acc <> char
          end
        end
      end
      """

      issues = check(code)

      assert length(issues) >= 1
      assert hd(issues).rule == :no_string_concat_in_loop
    end

    test "detects <> inside recursive function" do
      code = """
      defmodule Bad do
        def build("", acc), do: acc
        def build(<<char::utf8, rest::binary>>, acc) do
          build(rest, acc <> <<char::utf8>>)
        end
      end
      """

      issues = check(code)

      assert length(issues) >= 1
      assert hd(issues).rule == :no_string_concat_in_loop
    end

    test "ignores <> in non-recursive function" do
      code = """
      defmodule Safe do
        def prefix(base, suffix) do
          base <> "_" <> suffix
        end
      end
      """

      assert check(code) == []
    end
  end
end
