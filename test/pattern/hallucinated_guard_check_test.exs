defmodule Credence.Pattern.HallucinatedGuardCheckTest do
  use ExUnit.Case

  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.HallucinatedGuard.check(ast, [])
  end

  describe "flags hallucinated guards" do
    test "is_pos_integer" do
      code = "defmodule M do\n  def f(x) when is_pos_integer(x), do: x\nend"
      assert [%Issue{rule: :hallucinated_guard}] = check(code)
    end

    test "is_non_neg_integer" do
      code = "defmodule M do\n  def f(x) when is_non_neg_integer(x), do: x\nend"
      assert [%Issue{rule: :hallucinated_guard}] = check(code)
    end

    test "is_neg_integer" do
      code = "defmodule M do\n  def f(x) when is_neg_integer(x), do: x\nend"
      assert [%Issue{rule: :hallucinated_guard}] = check(code)
    end

    test "is_non_pos_integer" do
      code = "defmodule M do\n  def f(x) when is_non_pos_integer(x), do: x\nend"
      assert [%Issue{rule: :hallucinated_guard}] = check(code)
    end

    test "outside guard context" do
      code = "defmodule M do\n  def valid?(x), do: is_pos_integer(x)\nend"
      assert [%Issue{rule: :hallucinated_guard}] = check(code)
    end
  end

  describe "does NOT flag valid guards" do
    test "is_integer" do
      assert check("defmodule M do\n  def f(x) when is_integer(x), do: x\nend") == []
    end

    test "is_binary" do
      assert check("defmodule M do\n  def f(x) when is_binary(x), do: x\nend") == []
    end

    test "is_atom" do
      assert check("defmodule M do\n  def f(x) when is_atom(x), do: x\nend") == []
    end
  end
end
