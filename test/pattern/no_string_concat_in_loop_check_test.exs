defmodule Credence.Pattern.NoStringConcatInLoopCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoStringConcatInLoop

  describe "check/2 — positive cases" do
    test "flags Enum.reduce with simple <> concatenation" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc -> acc <> char end)
        end
      end
      """

      issues = check(NoStringConcatInLoop, code)
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

      issues = check(NoStringConcatInLoop, code)
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

      issues = check(NoStringConcatInLoop, code)
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

      issues = check(NoStringConcatInLoop, code)
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

      issues = check(NoStringConcatInLoop, code)
      assert length(issues) == 1
    end

    test "flags inline do: form" do
      code = """
      defmodule Example do
        def build(list), do: Enum.reduce(list, "", fn c, a -> a <> c end)
      end
      """

      issues = check(NoStringConcatInLoop, code)
      assert length(issues) == 1
    end

    test "flags inside Enum.map" do
      code = """
      Enum.map(list, fn x ->
        Enum.reduce(x, "", fn char, acc -> acc <> char end)
      end)
      """

      assert length(check(NoStringConcatInLoop, code)) == 1
    end

    test "flags block body where acc only appears in final <>" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc ->
            count = :erlang.byte_size(char)
            acc <> String.duplicate(char, count)
          end)
        end
      end
      """

      assert length(check(NoStringConcatInLoop, code)) == 1
    end

    test "flags block body in pipeline" do
      code = """
      defmodule Example do
        def build(list) do
          list
          |> Enum.reduce("", fn char, acc ->
            upcased = String.upcase(char)
            acc <> upcased
          end)
        end
      end
      """

      assert length(check(NoStringConcatInLoop, code)) == 1
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

      assert check(NoStringConcatInLoop, code) == []
    end

    test "does not flag non-empty initial acc" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "prefix", fn char, acc -> acc <> char end)
        end
      end
      """

      assert check(NoStringConcatInLoop, code) == []
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

      assert check(NoStringConcatInLoop, code) == []
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

      assert check(NoStringConcatInLoop, code) == []
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

      assert check(NoStringConcatInLoop, code) == []
    end

    test "does not flag block body when acc referenced in preceding statements" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc ->
            prefix = if acc == "", do: "", else: ", "
            acc <> prefix <> char
          end)
        end
      end
      """

      assert check(NoStringConcatInLoop, code) == []
    end

    test "does not flag Enum.join" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.join(list)
        end
      end
      """

      assert check(NoStringConcatInLoop, code) == []
    end

    test "does not flag <> outside loops" do
      code = """
      defmodule Example do
        def greet(name) do
          "Hello, " <> name <> "!"
        end
      end
      """

      assert check(NoStringConcatInLoop, code) == []
    end

    test "does not flag when acc referenced in right of <>" do
      code = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc -> acc <> (char <> acc) end)
        end
      end
      """

      assert check(NoStringConcatInLoop, code) == []
    end
  end
end
