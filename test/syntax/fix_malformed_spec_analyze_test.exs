defmodule Credence.Syntax.FixMalformedSpecAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue

  defp analyze(code) do
    Credence.Syntax.FixMalformedSpec.analyze(code)
  end

  # ── flags malformed specs ──────────────────────────────────────

  describe "flags specs where :: is inside the argument parens" do
    test "simple types" do
      assert [%Issue{rule: :malformed_spec}] = analyze("@spec foo(integer() :: string())")
    end

    test "the actual LLM pattern from the log" do
      assert [%Issue{}] = analyze("@spec max_product(list(integer()) :: integer())")
    end

    test "multiple params" do
      assert [%Issue{}] = analyze("@spec add(integer(), integer() :: integer())")
    end

    test "function name with ?" do
      assert [%Issue{}] = analyze("@spec valid?(string() :: boolean())")
    end

    test "function name with !" do
      assert [%Issue{}] = analyze("@spec save!(map() :: {:ok, map()} | {:error, term()})")
    end

    test "nested parameterized types" do
      assert [%Issue{}] = analyze("@spec process(list(list(integer())) :: list(integer()))")
    end

    test "with leading indentation" do
      assert [%Issue{}] = analyze("  @spec foo(integer() :: string())")
    end

    test "multiple malformed specs in same source" do
      code = """
      @spec foo(integer() :: string())
      @spec bar(list() :: map())
      """

      assert length(analyze(code)) == 2
    end
  end

  # ── does NOT flag ──────────────────────────────────────────────

  describe "does NOT flag" do
    test "correct spec" do
      assert analyze("@spec foo(integer()) :: string()") == []
    end

    test "correct spec with multiple params" do
      assert analyze("@spec add(integer(), integer()) :: integer()") == []
    end

    test "named parameter (valid :: inside parens)" do
      assert analyze("@spec foo(name :: integer()) :: string()") == []
    end

    test "multiple named parameters" do
      assert analyze("@spec foo(x :: integer(), y :: string()) :: atom()") == []
    end

    test "not a spec" do
      assert analyze("def foo(x), do: x") == []
    end

    test "type definition" do
      assert analyze("@type t :: %{name: String.t()}") == []
    end

    test "spec with no :: at all" do
      assert analyze("@spec foo(integer())") == []
    end

    test "regular code with :: in a pattern" do
      assert analyze("<<head::binary-size(4), rest::binary>> = data") == []
    end
  end

  # ── metadata ───────────────────────────────────────────────────

  describe "metadata" do
    test "reports the correct line number" do
      code = "def foo, do: :ok\n@spec bar(integer() :: string())\ndef bar(x), do: x"
      [issue] = analyze(code)
      assert issue.meta.line == 2
    end
  end
end
