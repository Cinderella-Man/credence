defmodule Credence.Pattern.NoStringLengthForCharCheckFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoStringLengthForCharCheck

  describe "fix: String.length(x) == 1" do
    test "replaces == with match?" do
      input = """
      defmodule Example do
        def single_char?(s) do
          String.length(s) == 1
        end
      end
      """

      expected = """
      defmodule Example do
        def single_char?(s) do
          match?([_], String.graphemes(s))
        end
      end
      """

      assert fix(NoStringLengthForCharCheck, input) == expected
    end

    test "replaces reversed form 1 == String.length(x)" do
      input = """
      defmodule Example do
        def single_char?(s) do
          1 == String.length(s)
        end
      end
      """

      expected = """
      defmodule Example do
        def single_char?(s) do
          match?([_], String.graphemes(s))
        end
      end
      """

      assert fix(NoStringLengthForCharCheck, input) == expected
    end

    test "replaces != with not match?" do
      input = """
      defmodule Example do
        def validate!(s) do
          if String.length(s) != 1 do
            raise ArgumentError, "expected a single character"
          end
        end
      end
      """

      expected = """
      defmodule Example do
        def validate!(s) do
          if not match?([_], String.graphemes(s)) do
            raise ArgumentError, "expected a single character"
          end
        end
      end
      """

      assert fix(NoStringLengthForCharCheck, input) == expected
    end

    test "replaces reversed form 1 != String.length(x)" do
      input = """
      defmodule Example do
        def validate!(s) do
          if 1 != String.length(s) do
            raise ArgumentError, "expected a single character"
          end
        end
      end
      """

      expected = """
      defmodule Example do
        def validate!(s) do
          if not match?([_], String.graphemes(s)) do
            raise ArgumentError, "expected a single character"
          end
        end
      end
      """

      assert fix(NoStringLengthForCharCheck, input) == expected
    end

    test "replaces === the same as ==" do
      input = """
      defmodule Example do
        def single_char?(s) do
          String.length(s) === 1
        end
      end
      """

      expected = """
      defmodule Example do
        def single_char?(s) do
          match?([_], String.graphemes(s))
        end
      end
      """

      assert fix(NoStringLengthForCharCheck, input) == expected
    end

    test "replaces !== the same as !=" do
      input = """
      defmodule Example do
        def validate!(s) do
          if String.length(s) !== 1 do
            raise ArgumentError, "bad"
          end
        end
      end
      """

      expected = """
      defmodule Example do
        def validate!(s) do
          if not match?([_], String.graphemes(s)) do
            raise ArgumentError, "bad"
          end
        end
      end
      """

      assert fix(NoStringLengthForCharCheck, input) == expected
    end

    test "does not alter String.length compared to other numbers" do
      code = """
      defmodule Example do
        def long_enough?(s) do
          String.length(s) >= 8
        end
      end
      """

      assert fix(NoStringLengthForCharCheck, code) == code
    end

    test "does not alter plain length/1 == 1" do
      code = """
      defmodule Example do
        def single?(list) do
          length(list) == 1
        end
      end
      """

      assert fix(NoStringLengthForCharCheck, code) == code
    end

    test "fixes multiple occurrences in the same module" do
      input = """
      defmodule Example do
        def validate(s) do
          if String.length(s) != 1 do
            raise "bad"
          end
          String.length(s) == 1
        end
      end
      """

      expected = """
      defmodule Example do
        def validate(s) do
          if not match?([_], String.graphemes(s)) do
            raise "bad"
          end
          match?([_], String.graphemes(s))
        end
      end
      """

      assert fix(NoStringLengthForCharCheck, input) == expected
    end

    test "preserves surrounding code" do
      input = """
      defmodule Example do
        @doc "checks char"
        def single_char?(s) do
          x = String.upcase(s)
          String.length(x) == 1
        end
      end
      """

      expected = """
      defmodule Example do
        @doc "checks char"
        def single_char?(s) do
          x = String.upcase(s)
          match?([_], String.graphemes(x))
        end
      end
      """

      assert fix(NoStringLengthForCharCheck, input) == expected
    end
  end
end
