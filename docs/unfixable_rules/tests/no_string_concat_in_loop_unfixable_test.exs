defmodule Credence.Pattern.NoStringConcatInLoopComplexTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoStringConcatInLoopComplex.check(ast, [])
  end

  describe "positive cases — should flag" do
    test "flags <> inside Enum.reduce_while" do
      code = """
      defmodule Example do
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
      assert hd(issues).rule == :no_string_concat_in_loop_complex
      assert hd(issues).message =~ "iodata"
      assert hd(issues).meta.line != nil
    end

    test "flags <> inside for comprehension" do
      code = """
      defmodule Example do
        def build(chars) do
          for char <- chars, reduce: "" do
            acc -> acc <> char
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
      assert hd(issues).rule == :no_string_concat_in_loop_complex
    end

    test "flags <> inside recursive function" do
      code = """
      defmodule Example do
        def build("", acc), do: acc
        def build(<<char::utf8, rest::binary>>, acc) do
          build(rest, acc <> <<char::utf8>>)
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
      assert hd(issues).rule == :no_string_concat_in_loop_complex
    end

    test "flags Enum.reduce with non-empty initial acc" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "prefix", fn char, acc -> acc <> char end)
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
      assert hd(issues).rule == :no_string_concat_in_loop_complex
    end

    test "flags Enum.reduce with block body" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc ->
            IO.puts(char)
            acc <> char
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
      assert hd(issues).rule == :no_string_concat_in_loop_complex
    end

    test "flags Enum.reduce with complex <> body" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc -> acc <> (char <> acc) end)
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
      assert hd(issues).rule == :no_string_concat_in_loop_complex
    end

    test "flags multiple <> in same loop" do
      code = """
      defmodule Example do
        def build(chars) do
          Enum.reduce_while(chars, "", fn char, acc ->
            candidate = acc <> char
            if valid?(candidate), do: {:cont, candidate <> "!"}, else: {:halt, acc}
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 2
    end

    test "flags Enum.reduce_while in pipeline" do
      code = """
      defmodule Example do
        def build(list) do
          list |> Enum.reduce_while("", fn char, acc ->
            {:cont, acc <> char}
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
      assert hd(issues).rule == :no_string_concat_in_loop_complex
    end
  end

  describe "negative cases — should NOT flag" do
    test "does not flag simple Enum.reduce with empty acc (fixable)" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc -> acc <> char end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag simple Enum.reduce in pipeline (fixable)" do
      code = """
      defmodule Example do
        def build(list) do
          list |> Enum.reduce("", fn char, acc -> acc <> char end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag simple Enum.reduce with transform (fixable)" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc -> acc <> to_string(char) end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag <> outside of loops" do
      code = """
      defmodule Safe do
        def greet(name) do
          "Hello, " <> name <> "!"
        end
      end
      """

      assert check(code) == []
    end

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

    test "ignores non-recursive function with Enum.reduce with empty acc" do
      code = """
      defmodule Safe do
        def prefix(list) do
          Enum.reduce(list, "", fn x, acc -> acc <> x end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
