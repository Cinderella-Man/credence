defmodule Credence.Pattern.NoWithAsBooleanChainFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoWithAsBooleanChain

  defp fix(code) do
    result = Credence.RuleHelpers.apply_rule_fix(NoWithAsBooleanChain, code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIXES — with true <- ... → and chain
  # ═══════════════════════════════════════════════════════════════════

  describe "rewrites with true chain to and chain" do
    test "two predicates" do
      input = """
      def check(x) do
        with true <- valid?(x),
             true <- allowed?(x) do
          true
        else
          _ -> false
        end
      end
      """

      expected = """
      def check(x) do
        valid?(x) and allowed?(x)
      end
      """

      assert fix(input) == expected
    end

    test "five predicates — password validation" do
      input = """
      def validate_password(password) do
        with true <- valid_length?(password),
             true <- has_lowercase?(password),
             true <- has_uppercase?(password),
             true <- has_digit?(password),
             true <- has_special_char?(password) do
          true
        else
          _ -> false
        end
      end
      """

      expected = """
      def validate_password(password) do
        valid_length?(password) and has_lowercase?(password) and has_uppercase?(password) and
          has_digit?(password) and has_special_char?(password)
      end
      """

      assert fix(input) == expected
    end

    test "single predicate" do
      input = """
      def check(x) do
        with true <- valid?(x) do
          true
        else
          _ -> false
        end
      end
      """

      expected = """
      def check(x) do
        valid?(x)
      end
      """

      assert fix(input) == expected
    end

    test "inside a module" do
      input = """
      defmodule Validator do
        def valid?(items) do
          with true <- is_list(items),
               true <- length(items) == 4 do
            true
          else
            _ -> false
          end
        end
      end
      """

      expected = """
      defmodule Validator do
        def valid?(items) do
          is_list(items) and length(items) == 4
        end
      end
      """

      assert fix(input) == expected
    end
  end
end
