defmodule Credence.Pattern.NoListDuplicateJoinFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoListDuplicateJoin

  test "rewrites piped form with variable count" do
    code = """
    defmodule M do
      def line(n) do
        "="
        |> List.duplicate(n)
        |> Enum.join()
      end
    end
    """

    expected = """
    defmodule M do
      def line(n) do
        String.duplicate("=", n)
      end
    end
    """

    confirm_fix(fix(NoListDuplicateJoin, code), expected)
  end

  test "rewrites piped form with integer literal count" do
    code = """
    defmodule M do
      def rule do
        "-"
        |> List.duplicate(80)
        |> Enum.join()
      end
    end
    """

    expected = """
    defmodule M do
      def rule do
        String.duplicate("-", 80)
      end
    end
    """

    confirm_fix(fix(NoListDuplicateJoin, code), expected)
  end

  test "rewrites nested form with variable count" do
    code = """
    defmodule M do
      def line(n) do
        Enum.join(List.duplicate("=", n))
      end
    end
    """

    expected = """
    defmodule M do
      def line(n) do
        String.duplicate("=", n)
      end
    end
    """

    confirm_fix(fix(NoListDuplicateJoin, code), expected)
  end

  test "rewrites nested form with integer literal count" do
    code = """
    defmodule M do
      def rule do
        Enum.join(List.duplicate("-", 80))
      end
    end
    """

    expected = """
    defmodule M do
      def rule do
        String.duplicate("-", 80)
      end
    end
    """

    confirm_fix(fix(NoListDuplicateJoin, code), expected)
  end

  test "leaves a non-literal first argument untouched" do
    code = """
    defmodule M do
      def repeat(str, n) do
        Enum.join(List.duplicate(str, n))
      end
    end
    """

    confirm_fix(fix(NoListDuplicateJoin, code), code)
  end

  test "leaves an integer first argument untouched" do
    code = """
    defmodule M do
      def digits(n) do
        Enum.join(List.duplicate(7, n))
      end
    end
    """

    confirm_fix(fix(NoListDuplicateJoin, code), code)
  end

  test "leaves Enum.join with a separator untouched" do
    code = """
    defmodule M do
      def repeat(n) do
        "="
        |> List.duplicate(n)
        |> Enum.join(", ")
      end
    end
    """

    confirm_fix(fix(NoListDuplicateJoin, code), code)
  end
end
