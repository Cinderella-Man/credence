defmodule Credence.Pattern.NoListDuplicateJoinCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoListDuplicateJoin

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag (string-literal first argument, the safe core)
  # ═══════════════════════════════════════════════════════════════════

  describe "flags List.duplicate(\"literal\", n) |> Enum.join() in pipe" do
    test "piped form with variable count" do
      assert flagged?(NoListDuplicateJoin, """
             def line(n) do
               "="
               |> List.duplicate(n)
               |> Enum.join()
             end
             """)
    end

    test "piped form with integer literal count" do
      assert flagged?(NoListDuplicateJoin, """
             def rule do
               "-"
               |> List.duplicate(80)
               |> Enum.join()
             end
             """)
    end

    test "piped form preceded by other pipeline steps" do
      assert flagged?(NoListDuplicateJoin, """
             def line(n) do
               "="
               |> List.duplicate(n)
               |> Enum.join()
               |> String.trim()
             end
             """)
    end
  end

  describe "flags Enum.join(List.duplicate(\"literal\", n)) nested form" do
    test "nested with variable count" do
      assert flagged?(NoListDuplicateJoin, """
             def line(n) do
               Enum.join(List.duplicate("=", n))
             end
             """)
    end

    test "nested with integer literal count" do
      assert flagged?(NoListDuplicateJoin, """
             def rule do
               Enum.join(List.duplicate("-", 80))
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  # The rewrite to String.duplicate/2 is only behaviour-preserving when the
  # duplicated value is a binary. Enum.join calls to_string/1 on each element,
  # so a non-string value joins fine (Enum.join(List.duplicate(7, 3)) == "777")
  # while String.duplicate(7, 3) raises. A non-literal first argument cannot be
  # proven to be a binary syntactically, so it is deliberately left unflagged.
  describe "does not flag a non-literal first argument (unsafe to rewrite)" do
    test "piped form with a variable string source" do
      assert clean?(NoListDuplicateJoin, """
             def repeat(str, n) do
               str
               |> List.duplicate(n)
               |> Enum.join()
             end
             """)
    end

    test "nested form with a variable string source" do
      assert clean?(NoListDuplicateJoin, """
             def repeat(str, n) do
               Enum.join(List.duplicate(str, n))
             end
             """)
    end

    test "first argument is an integer literal" do
      assert clean?(NoListDuplicateJoin, """
             def digits(n) do
               Enum.join(List.duplicate(7, n))
             end
             """)
    end

    test "first argument is an atom literal" do
      assert clean?(NoListDuplicateJoin, """
             def repeat(n) do
               Enum.join(List.duplicate(:a, n))
             end
             """)
    end

    test "first argument is a function call result" do
      assert clean?(NoListDuplicateJoin, """
             def repeat(n) do
               Enum.join(List.duplicate(to_string(n), n))
             end
             """)
    end
  end

  describe "does not flag List.duplicate without Enum.join" do
    test "standalone List.duplicate" do
      assert clean?(NoListDuplicateJoin, """
             def dup(str, n) do
               List.duplicate(str, n)
             end
             """)
    end

    test "List.duplicate piped to something else" do
      assert clean?(NoListDuplicateJoin, """
             def dup(n) do
               "="
               |> List.duplicate(n)
               |> List.last()
             end
             """)
    end
  end

  describe "does not flag Enum.join without List.duplicate" do
    test "standalone Enum.join" do
      assert clean?(NoListDuplicateJoin, """
             def join(list) do
               Enum.join(list)
             end
             """)
    end

    test "Enum.join of a map operation" do
      assert clean?(NoListDuplicateJoin, """
             def join(list) do
               Enum.join(Enum.map(list, &to_string/1))
             end
             """)
    end
  end

  describe "does not flag Enum.join with separator" do
    test "Enum.join with a non-empty separator is not equivalent" do
      assert clean?(NoListDuplicateJoin, """
             def repeat(n) do
               "="
               |> List.duplicate(n)
               |> Enum.join(", ")
             end
             """)
    end
  end

  describe "does not flag String.duplicate" do
    test "already idiomatic" do
      assert clean?(NoListDuplicateJoin, """
             def repeat(str, n) do
               String.duplicate(str, n)
             end
             """)
    end
  end
end
