defmodule Credence.Syntax.NoKeywordInsideTupleBraceAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoKeywordInsideTupleBrace

  defp analyze(code), do: NoKeywordInsideTupleBrace.analyze(code)

  describe "flags a keyword list written inside tuple braces" do
    test "as a list element, reporting the line the parser blamed" do
      code = """
      defmodule TupleKeywordTest do
        def build_step(name, compensation) do
          [{step_name: name, compensation: compensation}]
        end
      end
      """

      assert [%Issue{rule: :no_keyword_inside_tuple_brace, meta: %{line: 3}}] = analyze(code)
    end

    test "as a map value" do
      code = """
      defmodule TupleKeywordTest do
        def build_step(name, compensation) do
          %{name: name, data: [{step_name: name, compensation: compensation}]}
        end
      end
      """

      assert [%Issue{rule: :no_keyword_inside_tuple_brace, meta: %{line: 3}}] = analyze(code)
    end

    test "with a single pair" do
      code = "x = {a: 1}"

      assert [%Issue{rule: :no_keyword_inside_tuple_brace, meta: %{line: 1}}] = analyze(code)
    end

    test "whose pairs continue on a later line" do
      code = """
      x = {a: 1,
        b: 2}
      """

      assert [%Issue{rule: :no_keyword_inside_tuple_brace, meta: %{line: 1}}] = analyze(code)
    end

    test "only once, at the brace the parser reveals first" do
      code = """
      a = {x: 1}
      b = {y: 2}
      """

      assert [%Issue{meta: %{line: 1}}] = analyze(code)
    end
  end

  describe "leaves valid code alone" do
    test "a map literal" do
      code = """
      defmodule GoodCode do
        def build_map do
          %{step_name: "test", compensation: 42}
        end
      end
      """

      assert analyze(code) == []
    end

    test "a tuple" do
      code = """
      defmodule GoodCode do
        def build_tuple do
          {:ok, "result"}
        end
      end
      """

      assert analyze(code) == []
    end

    test "a tuple whose last element is a keyword list" do
      code = """
      defmodule GoodCode do
        def build_tuple(n) do
          {:ok, count: n, total: 2}
        end
      end
      """

      assert analyze(code) == []
    end

    test "a struct pattern with a nested map" do
      code = """
      defmodule PlugTest do
        def extract_user(%Plug.Conn{assigns: %{user_id: user_id}}) do
          user_id
        end
      end
      """

      assert analyze(code) == []
    end
  end

  describe "stays silent on broken code it cannot repair" do
    test "a positional entry after the keyword list (a different parser error)" do
      code = "x = {a: 1, b}"

      assert analyze(code) == []
    end

    test "a keyword list starting on the brace's second line" do
      code = """
      x = {
        a: 1
      }
      """

      assert analyze(code) == []
    end

    test "a brace shape living inside a string, with the real error elsewhere" do
      code = """
      defmodule M do
        def describe do
          "{a: 1}"
        end
      """

      assert analyze(code) == []
    end

    test "a brace shape inside a comment, with the real error elsewhere" do
      code = """
      defmodule M do
        # returns {a: 1}
        def describe do
          :ok
        end
      """

      assert analyze(code) == []
    end

    test "a closing brace beyond the search window" do
      pairs = Enum.map_join(1..30, ",\n  ", fn n -> "k#{n}: #{n}" end)

      code = """
      x = {a: 1,
        #{pairs}}
      """

      assert analyze(code) == []
    end
  end
end
