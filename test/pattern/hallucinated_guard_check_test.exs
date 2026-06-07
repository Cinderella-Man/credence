defmodule Credence.Pattern.HallucinatedGuardCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.HallucinatedGuard

  describe "flags hallucinated guards" do
    test "is_pos_integer" do
      code = "defmodule M do\n  def f(x) when is_pos_integer(x), do: x\nend"
      assert [%Issue{rule: :hallucinated_guard}] = check(HallucinatedGuard, code)
    end

    test "is_non_neg_integer" do
      code = "defmodule M do\n  def f(x) when is_non_neg_integer(x), do: x\nend"
      assert [%Issue{rule: :hallucinated_guard}] = check(HallucinatedGuard, code)
    end

    test "is_neg_integer" do
      code = "defmodule M do\n  def f(x) when is_neg_integer(x), do: x\nend"
      assert [%Issue{rule: :hallucinated_guard}] = check(HallucinatedGuard, code)
    end

    test "is_non_pos_integer" do
      code = "defmodule M do\n  def f(x) when is_non_pos_integer(x), do: x\nend"
      assert [%Issue{rule: :hallucinated_guard}] = check(HallucinatedGuard, code)
    end

    test "outside guard context" do
      code = "defmodule M do\n  def valid?(x), do: is_pos_integer(x)\nend"
      assert [%Issue{rule: :hallucinated_guard}] = check(HallucinatedGuard, code)
    end
  end

  describe "does NOT flag valid guards" do
    test "is_integer" do
      assert check(HallucinatedGuard, "defmodule M do\n  def f(x) when is_integer(x), do: x\nend") ==
               []
    end

    test "is_binary" do
      assert check(HallucinatedGuard, "defmodule M do\n  def f(x) when is_binary(x), do: x\nend") ==
               []
    end

    test "is_atom" do
      assert check(HallucinatedGuard, "defmodule M do\n  def f(x) when is_atom(x), do: x\nend") ==
               []
    end
  end
end
