defmodule Credence.Pattern.NoIfBooleanResultFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoIfBooleanResult

  # ═══════════════════════════════════════════════════════════════════
  # OR REWRITES — if...true...else...expr → cond or expr
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites if with true in do to or" do
    test "function call condition and function call else" do
      input = """
      if valid_ipv4?(host) do
        true
      else
        valid_domain?(host)
      end
      """

      expected = "valid_ipv4?(host) or valid_domain?(host)"

      confirm_fix(fix(NoIfBooleanResult, input), expected)
    end

    test "comparison condition and function call else" do
      input = """
      if x > 0 do
        true
      else
        some_check(x)
      end
      """

      expected = "x > 0 or some_check(x)"

      confirm_fix(fix(NoIfBooleanResult, input), expected)
    end

    test "inside a module" do
      input = """
      defmodule Example do
        def check(host) do
          if valid_ipv4?(host) do
            true
          else
            valid_domain?(host)
          end
        end
      end
      """

      expected = """
      defmodule Example do
        def check(host) do
          valid_ipv4?(host) or valid_domain?(host)
        end
      end
      """

      confirm_fix(fix(NoIfBooleanResult, input), expected)
    end

    test "inline form" do
      input = "if valid_ipv4?(host), do: true, else: valid_domain?(host)"

      expected = "valid_ipv4?(host) or valid_domain?(host)"

      confirm_fix(fix(NoIfBooleanResult, input), expected)
    end

    test "preserves surrounding code" do
      input = """
      def check(host) do
        addr = resolve(host)
        if valid_ipv4?(host) do
          true
        else
          valid_domain?(host)
        end
      end
      """

      expected = """
      def check(host) do
        addr = resolve(host)
        valid_ipv4?(host) or valid_domain?(host)
      end
      """

      confirm_fix(fix(NoIfBooleanResult, input), expected)
    end

    test "used as expression assignment" do
      input = """
      def check(host) do
        result = if valid_ipv4?(host) do
          true
        else
          valid_domain?(host)
        end
        result
      end
      """

      expected = """
      def check(host) do
        result = valid_ipv4?(host) or valid_domain?(host)
        result
      end
      """

      confirm_fix(fix(NoIfBooleanResult, input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # AND REWRITES — if...expr...else...false → cond and expr
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites if with false in else to and" do
    test "function call in do with false in else" do
      input = """
      if x > 0 do
        some_check(x)
      else
        false
      end
      """

      expected = "x > 0 and some_check(x)"

      confirm_fix(fix(NoIfBooleanResult, input), expected)
    end

    test "comparison in do with false in else" do
      input = """
      if x > 0 do
        y == 1
      else
        false
      end
      """

      expected = "x > 0 and y == 1"

      confirm_fix(fix(NoIfBooleanResult, input), expected)
    end

    test "inline form with false else" do
      input = "if x > 0, do: some_check(x), else: false"

      expected = "x > 0 and some_check(x)"

      confirm_fix(fix(NoIfBooleanResult, input), expected)
    end

    test "inside a module" do
      input = """
      defmodule Example do
        def check(x) do
          if x > 0 do
            some_check(x)
          else
            false
          end
        end
      end
      """

      expected = """
      defmodule Example do
        def check(x) do
          x > 0 and some_check(x)
        end
      end
      """

      confirm_fix(fix(NoIfBooleanResult, input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLE OCCURRENCES
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes multiple occurrences" do
    test "two matching ifs in same function" do
      input = """
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

      expected = """
      def run(a, b, c, d) do
        x = a > 0 or b
        y = c > 0 and d
        {x, y}
      end
      """

      confirm_fix(fix(NoIfBooleanResult, input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must NOT modify
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify if with both boolean literals" do
    test "true in do and false in else" do
      input = """
      if x > 0 do
        true
      else
        false
      end
      """

      confirm_fix(fix(NoIfBooleanResult, input), input)
    end

    test "false in do and true in else" do
      input = """
      if x > 0 do
        false
      else
        true
      end
      """

      confirm_fix(fix(NoIfBooleanResult, input), input)
    end
  end

  describe "does not modify if without boolean literals" do
    test "non-boolean values in both branches" do
      input = """
      if x > 0 do
        :positive
      else
        :negative
      end
      """

      confirm_fix(fix(NoIfBooleanResult, input), input)
    end

    test "computed values in both branches" do
      input = """
      if x > 0 do
        x * 2
      else
        0
      end
      """

      confirm_fix(fix(NoIfBooleanResult, input), input)
    end
  end

  describe "does not modify other boolean-literal placements" do
    test "false in do with non-boolean in else" do
      input = """
      if x > 0 do
        false
      else
        some_value
      end
      """

      confirm_fix(fix(NoIfBooleanResult, input), input)
    end

    test "non-boolean in do with true in else" do
      input = """
      if x > 0 do
        some_value
      else
        true
      end
      """

      confirm_fix(fix(NoIfBooleanResult, input), input)
    end
  end

  describe "does not modify if without else" do
    test "bare if block" do
      input = """
      if x > 0 do
        IO.puts("positive")
      end
      """

      confirm_fix(fix(NoIfBooleanResult, input), input)
    end
  end

  describe "does not modify code without if" do
    test "plain function" do
      input = """
      defmodule M do
        def run(x), do: x * 2
      end
      """

      confirm_fix(fix(NoIfBooleanResult, input), input)
    end

    test "boolean expression" do
      input = "valid_ipv4?(host) or valid_domain?(host)"

      confirm_fix(fix(NoIfBooleanResult, input), input)
    end
  end
end
