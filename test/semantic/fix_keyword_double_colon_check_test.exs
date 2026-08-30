defmodule Credence.Semantic.FixKeywordDoubleColonCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixKeywordDoubleColon

  @message "misplaced operator ::/2"

  test "matches the diagnostic" do
    diag = %{severity: :error, message: @message, position: {5, 47}}
    assert FixKeywordDoubleColon.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute FixKeywordDoubleColon.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: @message, position: {5, 47}}
    assert FixKeywordDoubleColon.to_issue(diag).rule == :fix_keyword_double_colon
  end

  test "should_report? is true when the fix applies" do
    code = """
    defmodule M do
      use GenServer

      def start do
        GenServer.start_link(__MODULE__, :ok, name::MyServer)
      end

      def init(state), do: {:ok, state}
    end
    """

    diag = %{severity: :error, message: @message, position: {5, 47}}
    assert FixKeywordDoubleColon.should_report?(diag, code)
  end

  test "should_report? is false for a non-keyword misplaced :: the fix skips" do
    code = """
    defmodule A do
      def f(x) do
        y = x::integer
        y
      end
    end
    """

    diag = %{severity: :error, message: @message, position: {3, 10}}
    refute FixKeywordDoubleColon.should_report?(diag, code)
  end

  test "analyze attributes a real keyword :: typo to this rule" do
    code = """
    defmodule CredenceKwDoubleColonAnalyzeFixture do
      use GenServer

      def start do
        GenServer.start_link(__MODULE__, :ok, name::CredenceKwDoubleColonName)
      end

      def init(state), do: {:ok, state}
    end
    """

    assert [%Credence.Issue{rule: :fix_keyword_double_colon, meta: %{line: 5}}] =
             Credence.Semantic.analyze(code)
  end

  test "analyze reports nothing for a non-keyword misplaced ::" do
    code = """
    defmodule CredenceKwDoubleColonSkipFixture do
      def f(x) do
        y = x::integer
        y
      end
    end
    """

    assert Credence.Semantic.analyze(code) == []
  end
end
