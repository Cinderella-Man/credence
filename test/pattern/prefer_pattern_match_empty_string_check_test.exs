defmodule Credence.Pattern.PreferPatternMatchEmptyStringCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPatternMatchEmptyString

  describe "PreferPatternMatchEmptyString check" do
    # --- POSITIVE CASES (should flag) ---

    test "flags byte_size(var) == 0 in a guard" do
      code = """
      defmodule Bad do
        def reverse_left_words(str, _count) when byte_size(str) == 0, do: str
      end
      """

      issues = check(PreferPatternMatchEmptyString, code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :prefer_pattern_match_empty_string
      assert issue.message =~ "byte_size"
      assert issue.message =~ "\"\""
    end

    test "flags byte_size(var) == 0 in a defp guard" do
      code = """
      defmodule Bad do
        defp empty?(str) when byte_size(str) == 0, do: true
      end
      """

      issues = check(PreferPatternMatchEmptyString, code)
      assert length(issues) == 1
      assert hd(issues).rule == :prefer_pattern_match_empty_string
    end

    test "flags byte_size check inside compound guard" do
      code = """
      defmodule Bad do
        def process(str, x) when byte_size(str) == 0 and is_binary(x) do
          :ok
        end
      end
      """

      issues = check(PreferPatternMatchEmptyString, code)
      assert length(issues) == 1
      assert hd(issues).rule == :prefer_pattern_match_empty_string
    end

    # --- NEGATIVE CASES (should NOT flag) ---

    test "does not flag byte_size(var) == N for N != 0" do
      code = """
      defmodule Safe do
        def check(str) when byte_size(str) == 5, do: :ok
      end
      """

      assert check(PreferPatternMatchEmptyString, code) == []
    end

    test "does not flag byte_size(var) != 0" do
      code = """
      defmodule Safe do
        def check(str) when byte_size(str) != 0, do: :ok
      end
      """

      assert check(PreferPatternMatchEmptyString, code) == []
    end

    test "does not flag byte_size(expr) == 0 where expr is not a simple variable" do
      code = """
      defmodule Safe do
        def check(map) when byte_size(map.name) == 0, do: :ok
      end
      """

      assert check(PreferPatternMatchEmptyString, code) == []
    end

    test "does not flag byte_size in function body" do
      code = """
      defmodule Safe do
        def check(str) do
          byte_size(str) == 0
        end
      end
      """

      assert check(PreferPatternMatchEmptyString, code) == []
    end

    test "does not flag code without guards" do
      code = """
      defmodule Safe do
        def process(""), do: :empty
        def process(_), do: :not_empty
      end
      """

      assert check(PreferPatternMatchEmptyString, code) == []
    end
  end
end
