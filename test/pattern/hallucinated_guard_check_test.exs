defmodule Credence.Pattern.HallucinatedGuardCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.HallucinatedGuard

  describe "flags hallucinated guards" do
    test "is_pos_integer" do
      code = """
      defmodule M do
        def f(x) when is_pos_integer(x), do: x
      end
      """

      assert [%Issue{rule: :hallucinated_guard}] = check(HallucinatedGuard, code)
    end

    test "is_non_neg_integer" do
      code = """
      defmodule M do
        def f(x) when is_non_neg_integer(x), do: x
      end
      """

      assert [%Issue{rule: :hallucinated_guard}] = check(HallucinatedGuard, code)
    end

    test "is_neg_integer" do
      code = """
      defmodule M do
        def f(x) when is_neg_integer(x), do: x
      end
      """

      assert [%Issue{rule: :hallucinated_guard}] = check(HallucinatedGuard, code)
    end

    test "is_non_pos_integer" do
      code = """
      defmodule M do
        def f(x) when is_non_pos_integer(x), do: x
      end
      """

      assert [%Issue{rule: :hallucinated_guard}] = check(HallucinatedGuard, code)
    end

    test "outside guard context" do
      code = """
      defmodule M do
        def valid?(x), do: is_pos_integer(x)
      end
      """

      assert [%Issue{rule: :hallucinated_guard}] = check(HallucinatedGuard, code)
    end
  end

  describe "does NOT flag valid guards" do
    test "is_integer" do
      assert check(HallucinatedGuard, """
             defmodule M do
               def f(x) when is_integer(x), do: x
             end
             """) ==
               []
    end

    test "is_binary" do
      assert check(HallucinatedGuard, """
             defmodule M do
               def f(x) when is_binary(x), do: x
             end
             """) ==
               []
    end

    test "is_atom" do
      assert check(HallucinatedGuard, """
             defmodule M do
               def f(x) when is_atom(x), do: x
             end
             """) ==
               []
    end
  end

  # A name the module DEFINES via `defguard`/`defguardp` is a real guard, not a
  # hallucination — it must not be flagged anywhere (definition or call sites).
  describe "does NOT flag a guard the module defines" do
    test "defguardp definition alone" do
      assert check(HallucinatedGuard, """
             defmodule M do
               defguardp is_pos_integer(n) when is_integer(n) and n > 0
             end
             """) ==
               []
    end

    test "public defguard definition alone" do
      assert check(HallucinatedGuard, """
             defmodule M do
               defguard is_pos_integer(n) when is_integer(n) and n > 0
             end
             """) ==
               []
    end

    test "definition plus a call site of the defined guard" do
      assert check(HallucinatedGuard, """
             defmodule M do
               defguardp is_pos_integer(n) when is_integer(n) and n > 0
               def f(x) when is_pos_integer(x), do: x
             end
             """) ==
               []
    end

    test "multiple defined guards (the pfx shape)" do
      assert check(HallucinatedGuard, """
             defmodule M do
               defguardp is_non_neg_integer(n) when is_integer(n) and n >= 0
               defguardp is_pos_integer(n) when is_integer(n) and n > 0
               def f(x) when is_non_neg_integer(x) and is_pos_integer(x), do: x
             end
             """) ==
               []
    end
  end

  describe "still flags genuinely-hallucinated guards alongside defined ones" do
    test "only the undefined guard is flagged" do
      # is_pos_integer is defined (real); is_neg_integer is not (hallucinated).
      issues =
        check(HallucinatedGuard, """
        defmodule M do
          defguardp is_pos_integer(n) when is_integer(n) and n > 0
          def f(x) when is_pos_integer(x), do: x
          def g(x) when is_neg_integer(x), do: x
        end
        """)

      assert [%Issue{rule: :hallucinated_guard, message: msg}] = issues
      assert msg =~ "is_neg_integer"
    end

    test "a defguard at a different arity does not protect the /1 call" do
      # defines is_pos_integer/2 (pathological); the hallucinated is_pos_integer/1
      # call is still flagged.
      assert [%Issue{rule: :hallucinated_guard}] =
               check(HallucinatedGuard, """
               defmodule M do
                 defguardp is_pos_integer(a, b) when a > 0 and b > 0
                 def f(x) when is_pos_integer(x), do: x
               end
               """)
    end
  end
end
