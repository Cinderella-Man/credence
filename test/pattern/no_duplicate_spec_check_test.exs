defmodule Credence.Pattern.NoDuplicateSpecCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoDuplicateSpec

  describe "does not flag" do
    test "single @spec before a single-clause function" do
      assert clean?(NoDuplicateSpec, """
             defmodule Good do
               @spec add(integer(), integer()) :: integer()
               def add(a, b), do: a + b
             end
             """)
    end

    test "single @spec before multi-clause function" do
      assert clean?(NoDuplicateSpec, """
             defmodule Good do
               @spec largest_square_number(non_neg_integer()) :: non_neg_integer()
               def largest_square_number(0), do: 0

               def largest_square_number(number) when is_integer(number) and number >= 0 do
                 root = floor(:math.sqrt(number))
                 root * root
               end
             end
             """)
    end

    test "@spec for different functions" do
      assert clean?(NoDuplicateSpec, """
             defmodule Good do
               @spec add(integer(), integer()) :: integer()
               def add(a, b), do: a + b

               @spec sub(integer(), integer()) :: integer()
               def sub(a, b), do: a - b
             end
             """)
    end

    test "no @spec at all" do
      assert clean?(NoDuplicateSpec, """
             defmodule Good do
               def add(a, b), do: a + b
             end
             """)
    end
  end

  describe "flags" do
    test "duplicate @spec before multi-clause function" do
      issues =
        check(NoDuplicateSpec, """
        defmodule Bad do
          @spec largest_square_number(non_neg_integer()) :: non_neg_integer()
          def largest_square_number(0), do: 0

          @spec largest_square_number(non_neg_integer()) :: non_neg_integer()
          def largest_square_number(number) when is_integer(number) and number >= 0 do
            root = floor(:math.sqrt(number))
            root * root
          end
        end
        """)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_duplicate_spec
      assert issue.message =~ "Duplicate"
      assert issue.message =~ "largest_square_number"
      assert issue.meta.line != nil
    end

    test "multiple duplicate @spec annotations" do
      issues =
        check(NoDuplicateSpec, """
        defmodule Bad do
          @spec foo(integer()) :: integer()
          def foo(0), do: 0

          @spec foo(integer()) :: integer()
          def foo(n), do: n

          @spec foo(integer()) :: integer()
          def foo(n) when n > 0, do: n + 1
        end
        """)

      assert length(issues) == 2
    end

    test "duplicate @spec with guard" do
      issues =
        check(NoDuplicateSpec, """
        defmodule Bad do
          @spec process(integer()) :: integer()
          def process(0), do: 0

          @spec process(integer()) :: integer()
          def process(n) when is_integer(n), do: n * 2
        end
        """)

      assert length(issues) == 1
    end
  end
end
