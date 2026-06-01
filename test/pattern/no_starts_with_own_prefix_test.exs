defmodule Credence.Pattern.NoStartsWithOwnPrefixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoStartsWithOwnPrefix

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoStartsWithOwnPrefix.check(ast, [])
  end

  describe "NoStartsWithOwnPrefix" do
    # ── Positive cases (should flag) ────────────────────────────

    test "flags String.starts_with? with String.slice of same variable from 0" do
      code = """
      defmodule Bad do
        def check(str, idx) do
          String.starts_with?(str, String.slice(str, 0, idx + 1))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_starts_with_own_prefix
      assert hd(issues).message =~ "always true"
    end

    test "flags when used in a boolean and expression" do
      code = """
      defmodule Bad do
        def check(common, string, idx) do
          if String.starts_with?(common, String.slice(common, 0, idx + 1)) &&
               String.starts_with?(string, String.slice(common, 0, idx + 1)) do
            :ok
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_starts_with_own_prefix
    end

    test "flags with literal zero start" do
      code = """
      defmodule Bad do
        def check(prefix) do
          String.starts_with?(prefix, String.slice(prefix, 0, 5))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    # ── Negative cases (should NOT flag) ────────────────────────

    test "does not flag String.starts_with? with different variables" do
      code = """
      defmodule Good do
        def check(str1, str2, idx) do
          String.starts_with?(str1, String.slice(str2, 0, idx + 1))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag String.starts_with? with non-slice prefix" do
      code = """
      defmodule Good do
        def check(str, prefix) do
          String.starts_with?(str, prefix)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag String.starts_with? with slice not starting from 0" do
      code = """
      defmodule Good do
        def check(str, start, len) do
          String.starts_with?(str, String.slice(str, start, len))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag String.starts_with? with slice using variable start" do
      code = """
      defmodule Good do
        def check(str, offset) do
          String.starts_with?(str, String.slice(str, offset, 3))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag a plain String.starts_with? call" do
      code = """
      defmodule Good do
        def check(str) do
          String.starts_with?(str, "hello")
        end
      end
      """

      assert check(code) == []
    end
  end
end
