defmodule Credence.Semantic.NoDefineMatchFnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoDefineMatchFn

  @real_message "imported Kernel.match?/2 conflicts with local function"

  defp fix(source, message, line \\ 1) do
    NoDefineMatchFn.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "renames match?/2 to match_pattern?/2 in full module" do
    input = """
    defmodule Example do
      def check(a, b) do
        match?(a, b)
      end

      defp match?(a, b) do
        a == b
      end
    end
    """

    expected = """
    defmodule Example do
      def check(a, b) do
        match_pattern?(a, b)
      end

      defp match_pattern?(a, b) do
        a == b
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "renames match?/2 to match_pattern?/2 in single-clause module" do
    input = """
    defmodule Example do
      def check(a, b), do: match?(a, b)
      defp match?(a, b), do: a == b
    end
    """

    expected = """
    defmodule Example do
      def check(a, b), do: match_pattern?(a, b)
      defp match_pattern?(a, b), do: a == b
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "renames the &match?/N capture along with the definition" do
    input = """
    defmodule Example do
      defp match?(a, b), do: a == b
      def f(l), do: Enum.filter(l, &match?/2)
    end
    """

    expected = """
    defmodule Example do
      defp match_pattern?(a, b), do: a == b
      def f(l), do: Enum.filter(l, &match_pattern?/2)
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "renames a guarded local match? clause and its call sites" do
    input = """
    defmodule Example do
      def check(a, b), do: match?(a, b)
      defp match?(a, b) when is_integer(a), do: a == b
      defp match?(_a, _b), do: false
    end
    """

    expected = """
    defmodule Example do
      def check(a, b), do: match_pattern?(a, b)
      defp match_pattern?(a, b) when is_integer(a), do: a == b
      defp match_pattern?(_a, _b), do: false
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def check(a, b), do: match?(a, b)
      defp match?(a, b), do: a == b
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  # --- safety: only the conflicting module is rewritten ---

  test "leaves a sibling module's legitimate Kernel.match?/2 untouched" do
    # Only module A defines a local match? and has the conflict. Module B uses
    # the auto-imported Kernel.match?/2 and compiles fine — renaming its call
    # would break otherwise-valid code, so it must be left alone.
    input = """
    defmodule A do
      defp match?(a, b), do: a == b
      def f(x), do: match?(x, 1)
    end

    defmodule B do
      def g(x), do: match?({:ok, _}, x)
    end
    """

    expected = """
    defmodule A do
      defp match_pattern?(a, b), do: a == b
      def f(x), do: match_pattern?(x, 1)
    end

    defmodule B do
      def g(x), do: match?({:ok, _}, x)
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "leaves an unqualified Kernel.match?/2 call untouched when no local match? is defined" do
    # Valid, conflict-free code: `match?/2` here is Kernel.match?/2. There is no
    # local definition, so nothing must be renamed.
    input = """
    defmodule Valid do
      def check(x), do: match?({:ok, _}, x)
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged when the conflict is qualified Kernel.match?" do
    input = """
    defmodule CleanExample do
      def hello, do: Kernel.match?(:ok, :ok)
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "leaves a public match?/2 definition unchanged" do
    input = """
    defmodule PublicMatchApi do
      def match?(a, b), do: a == b
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "a nested match?/2 definition does not rewrite its enclosing module" do
    input = """
    defmodule MatchOuter do
      def check(x), do: match?({:ok, _}, x)

      defmodule MatchInner do
        defp match?(a, b), do: a == b
      end
    end
    """

    expected = """
    defmodule MatchOuter do
      def check(x), do: match?({:ok, _}, x)

      defmodule MatchInner do
        defp match_pattern?(a, b), do: a == b
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "leaves match? definitions and references at other arities unchanged" do
    input = """
    defmodule MatchArityApi do
      def match?(x), do: {:one, x}
      defp match?(a, b), do: a == b
      def one(x), do: match?(x)
      def two(a, b), do: match?(a, b)
    end
    """

    expected = """
    defmodule MatchArityApi do
      def match?(x), do: {:one, x}
      defp match_pattern?(a, b), do: a == b
      def one(x), do: match?(x)
      def two(a, b), do: match_pattern?(a, b)
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end
end
