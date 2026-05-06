defmodule Credence.Pattern.NoStringConcatInLoopTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoStringConcatInLoop.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoStringConcatInLoop.fix(code, [])
  end

  defp normalize(code) do
    code
    |> Sourceror.parse_string!()
    |> Sourceror.to_string()
  end

  describe "check/2 — positive cases" do
    test "flags Enum.reduce with simple <> concatenation" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc -> acc <> char end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_string_concat_in_loop
    end

    test "flags Enum.reduce with <> and transform" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc -> acc <> to_string(char) end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_string_concat_in_loop
    end

    test "flags Enum.reduce in pipeline" do
      code = """
      defmodule Example do
        def build(list) do
          list |> Enum.reduce("", fn char, acc -> acc <> char end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_string_concat_in_loop
    end

    test "flags Enum.reduce in longer pipeline" do
      code = """
      defmodule Example do
        def build(list) do
          list
          |> Enum.filter(&(&1 != " "))
          |> Enum.reduce("", fn char, acc -> acc <> char end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_string_concat_in_loop
    end

    test "flags with different parameter names" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn x, y -> y <> x end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "flags inline do: form" do
      code = """
      defmodule Example do
        def build(list), do: Enum.reduce(list, "", fn c, a -> a <> c end)
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "flags inside Enum.map" do
      code = """
      Enum.map(list, fn x ->
        Enum.reduce(x, "", fn char, acc -> acc <> char end)
      end)
      """

      assert length(check(code)) == 1
    end
  end

  describe "check/2 — negative cases" do
    test "does not flag acc on right side" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc -> char <> acc end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag non-empty initial acc" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "prefix", fn char, acc -> acc <> char end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.reduce_while" do
      code = """
      defmodule Example do
        def build(chars) do
          Enum.reduce_while(chars, "", fn char, acc ->
            {:cont, acc <> char}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag for comprehension" do
      code = """
      defmodule Example do
        def build(chars) do
          for char <- chars, reduce: "" do
            acc -> acc <> char
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag recursive function" do
      code = """
      defmodule Example do
        def build("", acc), do: acc
        def build(<<char::utf8, rest::binary>>, acc) do
          build(rest, acc <> <<char::utf8>>)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag block body in Enum.reduce" do
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

      assert check(code) == []
    end

    test "does not flag Enum.join" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.join(list)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag <> outside loops" do
      code = """
      defmodule Example do
        def greet(name) do
          "Hello, " <> name <> "!"
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when acc referenced in right of <>" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc -> acc <> (char <> acc) end)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix/2 — transformations" do
    test "fixes simple Enum.reduce to Enum.join" do
      input = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc -> acc <> char end)
        end
      end
      """

      expected = """
      defmodule Example do
        def build(list) do
          Enum.join(list)
        end
      end
      """

      assert normalize(fix(input)) == normalize(expected)
    end

    test "fixes Enum.reduce with transform to Enum.map_join" do
      input = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc -> acc <> to_string(char) end)
        end
      end
      """

      expected = """
      defmodule Example do
        def build(list) do
          Enum.map_join(list, fn char -> to_string(char) end)
        end
      end
      """

      assert normalize(fix(input)) == normalize(expected)
    end

    test "fixes pipeline Enum.reduce to Enum.join" do
      input = """
      defmodule Example do
        def build(list) do
          list |> Enum.reduce("", fn char, acc -> acc <> char end)
        end
      end
      """

      expected = """
      defmodule Example do
        def build(list) do
          list |> Enum.join()
        end
      end
      """

      assert normalize(fix(input)) == normalize(expected)
    end

    test "fixes Enum.reduce in longer pipeline" do
      input = """
      defmodule Example do
        def build(list) do
          list
          |> Enum.filter(&(&1 != " "))
          |> Enum.reduce("", fn char, acc -> acc <> char end)
        end
      end
      """

      expected = """
      defmodule Example do
        def build(list) do
          list
          |> Enum.filter(&(&1 != " "))
          |> Enum.join()
        end
      end
      """

      assert normalize(fix(input)) == normalize(expected)
    end

    test "fixes multiple Enum.reduce calls independently" do
      input = """
      defmodule Example do
        def build(l1, l2) do
          a = Enum.reduce(l1, "", fn c, acc -> acc <> c end)
          b = Enum.reduce(l2, "", fn c, acc -> acc <> to_string(c) end)
          {a, b}
        end
      end
      """

      expected = """
      defmodule Example do
        def build(l1, l2) do
          a = Enum.join(l1)
          b = Enum.map_join(l2, fn c -> to_string(c) end)
          {a, b}
        end
      end
      """

      assert normalize(fix(input)) == normalize(expected)
    end

    test "fixes inline do: form" do
      input = """
      defmodule Example do
        def build(list), do: Enum.reduce(list, "", fn c, a -> a <> c end)
      end
      """

      expected = """
      defmodule Example do
        def build(list), do: Enum.join(list)
      end
      """

      assert normalize(fix(input)) == normalize(expected)
    end

    test "does not change code without issues" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.join(list)
        end
      end
      """

      assert normalize(fix(code)) == normalize(code)
    end

    test "does not change unfixable patterns" do
      code = """
      defmodule Example do
        def build(chars) do
          Enum.reduce_while(chars, "", fn char, acc ->
            {:cont, acc <> char}
          end)
        end
      end
      """

      assert normalize(fix(code)) == normalize(code)
    end

    test "does not change Enum.reduce with non-empty initial acc" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "prefix", fn char, acc -> acc <> char end)
        end
      end
      """

      assert normalize(fix(code)) == normalize(code)
    end

    test "does not change Enum.reduce with block body" do
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

      assert normalize(fix(code)) == normalize(code)
    end
  end
end
