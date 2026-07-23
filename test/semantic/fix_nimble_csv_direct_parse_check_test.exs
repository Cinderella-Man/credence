defmodule Credence.Semantic.FixNimbleCsvDirectParseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixNimbleCsvDirectParse

  @match_msg "NimbleCSV.parse_string/2 is undefined or private"

  test "matches the diagnostic" do
    diag = %{severity: :warning, message: @match_msg, position: {7, 21}}
    assert FixNimbleCsvDirectParse.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixNimbleCsvDirectParse.match?(diag)
  end

  test "ignores NimbleCSV diagnostic without undefined or private" do
    diag = %{severity: :warning, message: "NimbleCSV.parse_string deprecated", position: {1, 1}}
    refute FixNimbleCsvDirectParse.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @match_msg, position: {7, 21}}
    refute FixNimbleCsvDirectParse.match?(diag)
  end

  test "matches arity 1" do
    diag = %{
      severity: :warning,
      message: "NimbleCSV.parse_string/1 is undefined or private",
      position: {7, 21}
    }

    assert FixNimbleCsvDirectParse.match?(diag)
  end

  test "ignores arities a defined parser does not export" do
    diag = %{
      severity: :warning,
      message: "NimbleCSV.parse_string/3 is undefined or private",
      position: {7, 21}
    }

    refute FixNimbleCsvDirectParse.match?(diag)
  end

  test "ignores a different module whose name ends in NimbleCSV" do
    diag = %{
      severity: :warning,
      message: "Foo.NimbleCSV.parse_string/2 is undefined or private",
      position: {7, 21}
    }

    refute FixNimbleCsvDirectParse.match?(diag)
  end

  test "should_report? is true when the fix would rewrite the source" do
    source = """
    defmodule CsvLoader do
      NimbleCSV.define(CsvLoader.Parser, separator: ",", escape: "\\"")

      def load(csv) do
        NimbleCSV.parse_string(csv, skip_headers: false)
      end
    end
    """

    diag = %{severity: :warning, message: @match_msg, position: {5, 5}}
    assert FixNimbleCsvDirectParse.should_report?(diag, source)
  end

  test "should_report? is false when no NimbleCSV.define exists" do
    source = """
    defmodule CsvLoader do
      def load(csv) do
        NimbleCSV.parse_string(csv, skip_headers: false)
      end
    end
    """

    diag = %{severity: :warning, message: @match_msg, position: {3, 5}}
    refute FixNimbleCsvDirectParse.should_report?(diag, source)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @match_msg, position: {7, 21}}
    assert FixNimbleCsvDirectParse.to_issue(diag).rule == :fix_nimble_csv_direct_parse
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @match_msg, position: {42, 5}}
    assert FixNimbleCsvDirectParse.to_issue(diag).meta.line == 42
  end
end
