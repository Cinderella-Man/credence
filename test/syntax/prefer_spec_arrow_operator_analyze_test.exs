defmodule Credence.Syntax.PreferSpecArrowOperatorAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.PreferSpecArrowOperator

  defp analyze(code), do: PreferSpecArrowOperator.analyze(code)

  # ── flags missing arrow ──────────────────────────────────────────

  describe "flags specs missing :: before return type" do
    test "the LLM pattern from the rationale" do
      assert [%Issue{rule: :prefer_spec_arrow_operator}] =
               analyze("@spec get_days_between_dates(String.t(), String.t()) integer()")
    end

    test "single param" do
      assert [%Issue{}] = analyze("@spec foo(integer()) string()")
    end

    test "module return type" do
      assert [%Issue{}] = analyze("@spec bar(String.t()) Map.t()")
    end

    test "tuple return type" do
      assert [%Issue{}] = analyze("@spec baz(integer()) {:ok, term()}")
    end

    test "atom literal return" do
      assert [%Issue{}] = analyze("@spec qux(string()) :ok")
    end

    test "function name with ?" do
      assert [%Issue{}] = analyze("@spec valid?(string()) boolean()")
    end

    test "function name with !" do
      assert [%Issue{}] = analyze("@spec save!(map()) :ok")
    end

    test "with leading indentation" do
      assert [%Issue{}] = analyze("  @spec foo(integer()) string()")
    end

    test "multiple missing-arrow specs in same source" do
      code = """
      @spec foo(integer()) string()
      @spec bar(list()) map()
      """

      assert length(analyze(code)) == 2
    end
  end

  # ── does NOT flag ────────────────────────────────────────────────

  describe "does NOT flag" do
    test "correct spec with ::" do
      assert analyze("@spec foo(integer()) :: string()") == []
    end

    test "correct spec with multiple params" do
      assert analyze("@spec add(integer(), integer()) :: integer()") == []
    end

    test "spec with no return type" do
      assert analyze("@spec foo(integer())") == []
    end

    test "spec with guard clause" do
      assert analyze("@spec foo(integer()) when is_integer(x) :: string()") == []
    end

    test "not a spec" do
      assert analyze("def foo(x), do: x") == []
    end

    test "type definition" do
      assert analyze("@type t :: %{name: String.t()}") == []
    end

    test "regular code with parens" do
      assert analyze("foo(bar)") == []
    end
  end

  # ── metadata ─────────────────────────────────────────────────────

  describe "metadata" do
    test "reports the correct line number" do
      code = """
      def foo, do: :ok
      @spec bar(integer()) string()
      def bar(x), do: x
      """

      [issue] = analyze(code)
      assert issue.meta.line == 2
    end
  end
end
