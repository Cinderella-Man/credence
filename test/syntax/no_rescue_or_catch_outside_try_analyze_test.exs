defmodule Credence.Syntax.NoRescueOrCatchOutsideTryAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoRescueOrCatchOutsideTry

  defp analyze(code), do: NoRescueOrCatchOutsideTry.analyze(code)

  test "flags def with rescue" do
    code = """
    defmodule M do
      def verify(x) do
        x
      rescue
        _ -> :error
      end
    end
    """

    assert [%Issue{rule: :no_rescue_or_catch_outside_try}] = analyze(code)
  end

  test "flags def with catch" do
    code = """
    defmodule M do
      def verify(x) do
        x
      catch
        _ -> :error
      end
    end
    """

    assert [%Issue{rule: :no_rescue_or_catch_outside_try}] = analyze(code)
  end

  test "flags def with else" do
    code = """
    defmodule M do
      def verify(x) do
        x
      else
        val -> val
      end
    end
    """

    assert [%Issue{rule: :no_rescue_or_catch_outside_try}] = analyze(code)
  end

  test "flags def with rescue and catch" do
    code = """
    defmodule M do
      def verify(x) do
        x
      rescue
        _ -> :error
      catch
        _ -> :caught
      end
    end
    """

    assert [%Issue{rule: :no_rescue_or_catch_outside_try}] = analyze(code)
  end

  test "leaves well-formed try/rescue alone" do
    code = """
    defmodule M do
      def verify(x) do
        try do
          x
        rescue
          _ -> :error
        end
      end
    end
    """

    assert analyze(code) == []
  end

  test "leaves plain def alone" do
    code = """
    defmodule M do
      def verify(x) do
        x
      end
    end
    """

    assert analyze(code) == []
  end

  test "leaves rescue in try alone" do
    code = """
    defmodule M do
      def verify(x) do
        try do
          x
        rescue
          _ -> :error
        end
      end
    end
    """

    assert analyze(code) == []
  end
end
