defmodule Credence.Pattern.NoStringConcatInLoopFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoStringConcatInLoop

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoStringConcatInLoop, code, [])
  end

  defp normalize(code) do
    code
    |> Sourceror.parse_string!()
    |> Sourceror.to_string()
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

    test "does not change Enum.reduce with block body when acc used in preceding stmts" do
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

      assert normalize(fix(code)) == normalize(code)
    end

    test "fixes block body Enum.reduce to Enum.map_join" do
      input = """
      defmodule Example do
        def build(list) do
          Enum.reduce(list, "", fn char, acc ->
            count = :erlang.byte_size(char)
            acc <> String.duplicate(char, count)
          end)
        end
      end
      """

      expected = """
      defmodule Example do
        def build(list) do
          Enum.map_join(list, fn char ->
            count = :erlang.byte_size(char)
            String.duplicate(char, count)
          end)
        end
      end
      """

      assert normalize(fix(input)) == normalize(expected)
    end

    test "fixes pipeline block body Enum.reduce to Enum.map_join" do
      input = """
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

      expected = """
      defmodule Example do
        def build(list) do
          list
          |> Enum.map_join(fn char ->
            upcased = String.upcase(char)
            upcased
          end)
        end
      end
      """

      assert normalize(fix(input)) == normalize(expected)
    end
  end
end
