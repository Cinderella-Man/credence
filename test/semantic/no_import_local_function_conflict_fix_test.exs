defmodule Credence.Semantic.NoImportLocalFunctionConflictFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoImportLocalFunctionConflict

  @real_message "imported StreamData.date/1 conflicts with local function"

  defp fix(source, message, line \\ 1) do
    NoImportLocalFunctionConflict.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "renames defp and call sites to generate_ prefix" do
    input = """
    defmodule Example do
      import StreamData

      def make do
        date(42)
      end

      defp date(x), do: x
    end
    """

    expected = """
    defmodule Example do
      import StreamData

      def make do
        generate_date(42)
      end

      defp generate_date(x), do: x
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "renames multiple call sites and defp with do block" do
    input = """
    defmodule Generators do
      import StreamData

      def date_range do
        a = date(1)
        b = date(2)
        {a, b}
      end

      defp date(n) do
        n + 1
      end
    end
    """

    expected = """
    defmodule Generators do
      import StreamData

      def date_range do
        a = generate_date(1)
        b = generate_date(2)
        {a, b}
      end

      defp generate_date(n) do
        n + 1
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      import StreamData

      def make do
        date(42)
      end

      defp date(x), do: x
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no defp conflict" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
