defmodule Credence.Semantic.FixUnderscoredFnParamBindingForBodyUseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixUnderscoredFnParamBindingForBodyUse

  @message "undefined variable \"tv\""

  defp fix(source, message, line) do
    FixUnderscoredFnParamBindingForBodyUse.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "removes underscore from function parameter used in body" do
    input = """
    defmodule M do
      defp resolve_field(_field, ov, _bv, _tv) when ov == _bv do
        {:ok, tv}
      end
    end
    """

    expected = """
    defmodule M do
      defp resolve_field(_field, ov, _bv, tv) when ov == _bv do
        {:ok, tv}
      end
    end
    """

    confirm_fix(fix(input, @message, 3), expected)
  end

  test "removes underscore only in the enclosing clause" do
    input = """
    defmodule M do
      defp resolve_field(_field, ov, _bv, _tv) when ov == _bv do
        {:ok, tv}
      end

      defp other_clause(_tv) do
        _tv
      end
    end
    """

    expected = """
    defmodule M do
      defp resolve_field(_field, ov, _bv, tv) when ov == _bv do
        {:ok, tv}
      end

      defp other_clause(_tv) do
        _tv
      end
    end
    """

    confirm_fix(fix(input, @message, 3), expected)
  end

  test "handles one-liner function" do
    input = """
    defmodule M do
      defp foo(_x, y), do: {y, x}
    end
    """

    expected = """
    defmodule M do
      defp foo(x, y), do: {y, x}
    end
    """

    confirm_fix(fix(input, "undefined variable \"x\"", 2), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      defp resolve_field(_field, ov, _bv, _tv) when ov == _bv do
        {:ok, tv}
      end
    end
    """

    assert valid_syntax?(fix(input, @message, 3))
  end

  test "returns source unchanged when no underscore param found" do
    input = """
    defmodule NoMatch do
      def test do
        x + 1
      end
    end
    """

    result = fix(input, @message, 3)
    confirm_fix(result, input)
  end

  test "returns source unchanged for unrelated undefined variable" do
    input = """
    defmodule NoMatch do
      def test do
        IO.puts(y)
      end
    end
    """

    result = fix(input, "undefined variable \"y\"", 3)
    confirm_fix(result, input)
  end
end
