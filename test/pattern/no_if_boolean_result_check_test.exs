defmodule Credence.Pattern.NoIfBooleanResultCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoIfBooleanResult

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags if with true in do and non-boolean in else" do
    test "function call condition and function call else" do
      assert flagged?(NoIfBooleanResult, """
             if valid_ipv4?(host) do
               true
             else
               valid_domain?(host)
             end
             """)
    end

    test "comparison condition and function call else" do
      assert flagged?(NoIfBooleanResult, """
             if x > 0 do
               true
             else
               some_check(x)
             end
             """)
    end

    test "inside a module" do
      assert flagged?(NoIfBooleanResult, """
             defmodule Example do
               def check(host) do
                 if valid_ipv4?(host) do
                   true
                 else
                   valid_domain?(host)
                 end
               end
             end
             """)
    end

    test "inline form" do
      assert flagged?(
               NoIfBooleanResult,
               "if valid_ipv4?(host), do: true, else: valid_domain?(host)"
             )
    end

    test "true in do with integer in else" do
      assert flagged?(NoIfBooleanResult, """
             if x > 0 do
               true
             else
               0
             end
             """)
    end

    test "true in do with string in else" do
      assert flagged?(NoIfBooleanResult, """
             if x > 0 do
               true
             else
               "no"
             end
             """)
    end

    test "flags multiple occurrences" do
      code = """
      def run(a, b, c, d) do
        x = if a > 0 do
          true
        else
          b
        end
        y = if c > 0 do
          d
        else
          false
        end
        {x, y}
      end
      """

      assert length(check(NoIfBooleanResult, code)) == 2
    end
  end

  describe "flags if with non-boolean in do and false in else" do
    test "function call in do with false in else" do
      assert flagged?(NoIfBooleanResult, """
             if x > 0 do
               some_check(x)
             else
               false
             end
             """)
    end

    test "comparison in do with false in else" do
      assert flagged?(NoIfBooleanResult, """
             if x > 0 do
               y == 1
             else
               false
             end
             """)
    end

    test "inline form with false else" do
      assert flagged?(NoIfBooleanResult, "if x > 0, do: some_check(x), else: false")
    end

    test "string in do with false in else" do
      assert flagged?(NoIfBooleanResult, """
             if x > 0 do
               "yes"
             else
               false
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag if with both boolean literals" do
    test "true in do and false in else" do
      assert clean?(NoIfBooleanResult, """
             if x > 0 do
               true
             else
               false
             end
             """)
    end

    test "false in do and true in else" do
      assert clean?(NoIfBooleanResult, """
             if x > 0 do
               false
             else
               true
             end
             """)
    end
  end

  describe "does not flag if without boolean literals" do
    test "non-boolean values in both branches" do
      assert clean?(NoIfBooleanResult, """
             if x > 0 do
               :positive
             else
               :negative
             end
             """)
    end

    test "computed values in both branches" do
      assert clean?(NoIfBooleanResult, """
             if x > 0 do
               x * 2
             else
               0
             end
             """)
    end

    test "strings in both branches" do
      assert clean?(NoIfBooleanResult, """
             if x > 0 do
               "yes"
             else
               "no"
             end
             """)
    end
  end

  describe "does not flag other boolean-literal placements" do
    test "false in do with non-boolean in else" do
      assert clean?(NoIfBooleanResult, """
             if x > 0 do
               false
             else
               some_value
             end
             """)
    end

    test "non-boolean in do with true in else" do
      assert clean?(NoIfBooleanResult, """
             if x > 0 do
               some_value
             else
               true
             end
             """)
    end
  end

  describe "does not flag if without else" do
    test "bare if block" do
      assert clean?(NoIfBooleanResult, """
             if x > 0 do
               IO.puts("positive")
             end
             """)
    end
  end

  describe "does not flag code without if" do
    test "plain function" do
      assert clean?(NoIfBooleanResult, """
             defmodule M do
               def run(x), do: x * 2
             end
             """)
    end

    test "boolean expression" do
      assert clean?(NoIfBooleanResult, "valid_ipv4?(host) or valid_domain?(host)")
    end

    test "case expression" do
      assert clean?(NoIfBooleanResult, """
             case x do
               :ok -> true
               _ -> false
             end
             """)
    end
  end
end
