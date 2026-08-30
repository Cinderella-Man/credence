defmodule Credence.Semantic.FixNimbleCsvDirectParseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixNimbleCsvDirectParse
  alias Credence.RuleHelpers

  @match_msg "NimbleCSV.parse_string/2 is undefined or private"

  defp fix(source, message \\ @match_msg, line \\ 7) do
    FixNimbleCsvDirectParse.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces NimbleCSV.parse_string with defined parser module" do
    input = """
    defmodule CsvLoader do
      NimbleCSV.define(CsvLoader.Parser, separator: ",", escape: "\\"")

      def load_string(csv_string, schema) do
        parsed =
          csv_string
          |> NimbleCSV.parse_string(skip_headers: false)

        case parsed do
          [] -> {:ok, [], []}
          [header | rows] -> {:ok, header, rows}
        end
      end
    end
    """

    expected = """
    defmodule CsvLoader do
      NimbleCSV.define(CsvLoader.Parser, separator: ",", escape: "\\"")

      def load_string(csv_string, schema) do
        parsed =
          csv_string
          |> CsvLoader.Parser.parse_string(skip_headers: false)

        case parsed do
          [] -> {:ok, [], []}
          [header | rows] -> {:ok, header, rows}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule CsvLoader do
      NimbleCSV.define(CsvLoader.Parser, separator: ",", escape: "\\"")

      def load_string(csv_string, schema) do
        parsed =
          csv_string
          |> NimbleCSV.parse_string(skip_headers: false)

        case parsed do
          [] -> {:ok, [], []}
          [header | rows] -> {:ok, header, rows}
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no NimbleCSV.define found" do
    input = """
    defmodule CsvLoader do
      def load_string(csv_string, _schema) do
        NimbleCSV.parse_string(csv_string, skip_headers: false)
      end
    end
    """

    confirm_fix(fix(input, @match_msg, 3), input)
  end

  test "fixes direct call (not piped)" do
    input = """
    defmodule CsvLoader do
      NimbleCSV.define(MyParser, separator: ",", escape: "\\"")

      def load(csv) do
        NimbleCSV.parse_string(csv, skip_headers: false)
      end
    end
    """

    expected = """
    defmodule CsvLoader do
      NimbleCSV.define(MyParser, separator: ",", escape: "\\"")

      def load(csv) do
        MyParser.parse_string(csv, skip_headers: false)
      end
    end
    """

    confirm_fix(fix(input, @match_msg, 5), expected)
  end

  test "only replaces on the reported line" do
    input = """
    defmodule CsvLoader do
      NimbleCSV.define(CsvLoader.Parser, separator: ",", escape: "\\"")

      def load_a(csv) do
        NimbleCSV.parse_string(csv, skip_headers: false)
      end

      def load_b(csv) do
        NimbleCSV.parse_string(csv, skip_headers: false)
      end
    end
    """

    expected = """
    defmodule CsvLoader do
      NimbleCSV.define(CsvLoader.Parser, separator: ",", escape: "\\"")

      def load_a(csv) do
        CsvLoader.Parser.parse_string(csv, skip_headers: false)
      end

      def load_b(csv) do
        NimbleCSV.parse_string(csv, skip_headers: false)
      end
    end
    """

    confirm_fix(fix(input, @match_msg, 5), expected)
  end

  test "returns source unchanged when several distinct parsers are defined" do
    input = """
    defmodule CsvLoader do
      NimbleCSV.define(CommaParser, separator: ",", escape: "\\"")
      NimbleCSV.define(TabParser, separator: "\\t", escape: "\\"")

      def load(csv) do
        NimbleCSV.parse_string(csv, skip_headers: false)
      end
    end
    """

    confirm_fix(fix(input, @match_msg, 6), input)
  end

  test "returns source unchanged when the define target is not a literal alias" do
    input = """
    defmodule CsvLoader do
      NimbleCSV.define(__MODULE__.Parser, separator: ",", escape: "\\"")

      def load(csv) do
        NimbleCSV.parse_string(csv, skip_headers: false)
      end
    end
    """

    confirm_fix(fix(input, @match_msg, 5), input)
  end

  test "does not rewrite inside a longer module path on the same line" do
    input = """
    defmodule CsvLoader do
      NimbleCSV.define(MyParser, separator: ",", escape: "\\"")

      def load(csv) do
        Foo.NimbleCSV.parse_string(csv) || NimbleCSV.parse_string(csv, skip_headers: false)
      end
    end
    """

    expected = """
    defmodule CsvLoader do
      NimbleCSV.define(MyParser, separator: ",", escape: "\\"")

      def load(csv) do
        Foo.NimbleCSV.parse_string(csv) || MyParser.parse_string(csv, skip_headers: false)
      end
    end
    """

    confirm_fix(fix(input, @match_msg, 5), expected)
  end

  test "handles nested module name in define" do
    input = """
    defmodule CsvLoader do
      NimbleCSV.define(CsvLoader.Csv.Parser, separator: ",", escape: "\\"")

      def load(csv) do
        NimbleCSV.parse_string(csv, skip_headers: false)
      end
    end
    """

    expected = """
    defmodule CsvLoader do
      NimbleCSV.define(CsvLoader.Csv.Parser, separator: ",", escape: "\\"")

      def load(csv) do
        CsvLoader.Csv.Parser.parse_string(csv, skip_headers: false)
      end
    end
    """

    confirm_fix(fix(input, @match_msg, 5), expected)
  end

  test "skips a same-named reference in a string before the diagnosed call" do
    input = """
    defmodule CsvLoader do
      NimbleCSV.define(MyParser, separator: ",", escape: "\\\"")

      def load(csv) do
        IO.puts("NimbleCSV.parse_string"); NimbleCSV.parse_string(csv)
      end
    end
    """

    expected = """
    defmodule CsvLoader do
      NimbleCSV.define(MyParser, separator: ",", escape: "\\\"")

      def load(csv) do
        IO.puts("NimbleCSV.parse_string"); MyParser.parse_string(csv)
      end
    end
    """

    confirm_fix(fix(input, @match_msg, 5), expected)
  end

  test "qualifies a parser defined at top level when the call is in a module" do
    input = """
    NimbleCSV.define(MyParser, separator: ",", escape: "\\\"")

    defmodule Loader do
      def load(csv), do: NimbleCSV.parse_string(csv)
    end
    """

    expected = """
    NimbleCSV.define(MyParser, separator: ",", escape: "\\\"")

    defmodule Loader do
      def load(csv), do: Elixir.MyParser.parse_string(csv)
    end
    """

    actual = fix(input, @match_msg, 4)
    confirm_fix(actual, expected)

    control = """
    NimbleCSV.define(MyParserControlFNCDP, separator: ",", escape: "\\\"")

    defmodule LoaderControlFNCDP do
      def load(csv), do: Elixir.MyParserControlFNCDP.parse_string(csv)
    end
    """

    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(actual)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(control)
  end
end
