defmodule Credence.Pattern.NoWithAsBooleanChainCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoWithAsBooleanChain

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoWithAsBooleanChain.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags with true <- as boolean chain" do
    test "two predicates" do
      assert flagged?("""
             def check(x) do
               with true <- valid?(x),
                    true <- allowed?(x) do
                 true
               else
                 _ -> false
               end
             end
             """)
    end

    test "five predicates — password validation" do
      assert flagged?("""
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
             """)
    end

    test "single predicate" do
      assert flagged?("""
             def check(x) do
               with true <- valid?(x) do
                 true
               else
                 _ -> false
               end
             end
             """)
    end

    test "with function calls as predicates" do
      assert flagged?("""
             def check(list) do
               with true <- Enum.all?(list, &valid?/1),
                    true <- length(list) > 0 do
                 true
               else
                 _ -> false
               end
             end
             """)
    end

    test "inside a module" do
      assert flagged?("""
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
             """)
    end

    test "nested in another expression" do
      assert flagged?("""
             def check(x) do
               result = with true <- valid?(x), true <- active?(x) do
                 true
               else
                 _ -> false
               end
               result
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag legitimate with usage" do
    test "with ok/error tuple pattern" do
      assert clean?("""
             def run(x) do
               with {:ok, a} <- fetch(x),
                    {:ok, b} <- process(a) do
                 {:ok, b}
               else
                 {:error, reason} -> {:error, reason}
               end
             end
             """)
    end

    test "with mixed patterns" do
      assert clean?("""
             def run(x) do
               with true <- valid?(x),
                    {:ok, result} <- compute(x) do
                 {:ok, result}
               else
                 _ -> {:error, :invalid}
               end
             end
             """)
    end

    test "with non-true do body" do
      assert clean?("""
             def run(x) do
               with true <- valid?(x),
                    true <- active?(x) do
                 :ok
               else
                 _ -> :error
               end
             end
             """)
    end

    test "with non-wildcard else pattern" do
      assert clean?("""
             def run(x) do
               with true <- valid?(x) do
                 true
               else
                 false -> false
               end
             end
             """)
    end

    test "with non-false else body" do
      assert clean?("""
             def run(x) do
               with true <- valid?(x) do
                 true
               else
                 _ -> nil
               end
             end
             """)
    end

    test "with no else clause" do
      assert clean?("""
             def run(x) do
               with true <- valid?(x) do
                 :ok
               end
             end
             """)
    end

    test "with value binding pattern" do
      assert clean?("""
             def run(x) do
               with result when is_boolean(result) <- check(x) do
                 result
               else
                 _ -> false
               end
             end
             """)
    end
  end

  describe "does not flag code without with" do
    test "plain function" do
      assert clean?("""
             defmodule M do
               def run(x), do: x * 2
             end
             """)
    end

    test "and chain" do
      assert clean?("""
             def check(x) do
               valid?(x) and active?(x)
             end
             """)
    end
  end
end
