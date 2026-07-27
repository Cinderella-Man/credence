defmodule Credence.Syntax.NoKeywordIfBareInTupleFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [compiles?: 1, confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoKeywordIfBareInTuple

  defp analyze(code), do: NoKeywordIfBareInTuple.analyze(code)
  defp fix(code), do: NoKeywordIfBareInTuple.fix(code)

  describe "wraps the conditional in parentheses" do
    test "in a tuple" do
      code = "{:ok, if num < 1, do: 1, else: num}"

      expected = "{:ok, (if num < 1, do: 1, else: num)}"

      confirm_fix(fix(code), expected)
    end

    test "with only a do: branch" do
      code = "{:ok, if a, do: 1}"

      expected = "{:ok, (if a, do: 1)}"

      confirm_fix(fix(code), expected)
    end

    test "written as unless" do
      code = "{:ok, unless a, do: 1, else: 2}"

      expected = "{:ok, (unless a, do: 1, else: 2)}"

      confirm_fix(fix(code), expected)
    end

    test "in a list" do
      code = "[1, if a, do: 2, else: 3]"

      expected = "[1, (if a, do: 2, else: 3)]"

      confirm_fix(fix(code), expected)
    end

    test "as a map value" do
      code = "%{k: 1, v: if a, do: 2, else: 3}"

      expected = "%{k: 1, v: (if a, do: 2, else: 3)}"

      confirm_fix(fix(code), expected)
    end

    test "spread over several lines" do
      code = """
      x = {:ok,
        if a,
          do: 1,
          else: 2}
      """

      expected = """
      x = {:ok,
        (if a,
          do: 1,
          else: 2)}
      """

      confirm_fix(fix(code), expected)
    end

    test "whose branch value continues on the next line" do
      code = """
      {:ok, if a,
        do: x
           |> f(),
        else: 2}
      """

      expected = """
      {:ok, (if a,
        do: x
           |> f(),
        else: 2)}
      """

      confirm_fix(fix(code), expected)
    end

    test "in a real module, leaving every other line byte-identical" do
      code = """
      defmodule M do
        def parse_page(params) do
          case params do
            %{"page" => page_val} when is_binary(page_val) ->
              case Integer.parse(page_val) do
                {num, _} -> {:ok, if num < 1, do: 1, else: num}
                :error -> {:ok, 1}
              end

            %{"page" => page_val} when is_integer(page_val) ->
              {:ok, if page_val < 1, do: 1, else: page_val}

            _ ->
              {:ok, 1}
          end
        end
      end
      """

      expected = """
      defmodule M do
        def parse_page(params) do
          case params do
            %{"page" => page_val} when is_binary(page_val) ->
              case Integer.parse(page_val) do
                {num, _} -> {:ok, (if num < 1, do: 1, else: num)}
                :error -> {:ok, 1}
              end

            %{"page" => page_val} when is_integer(page_val) ->
              {:ok, (if page_val < 1, do: 1, else: page_val)}

            _ ->
              {:ok, 1}
          end
        end
      end
      """

      confirm_fix(fix(code), expected)
    end
  end

  describe "the closing paren never lands inside a literal" do
    test "a brace inside a string does not end the span" do
      code = ~S'{:ok, if a, do: 1, else: "}"}'

      expected = ~S'{:ok, (if a, do: 1, else: "}")}'

      confirm_fix(fix(code), expected)
    end

    test "a comma inside a string does not end the span" do
      code = ~S'{:ok, if a, do: "x, y", else: "z"}'

      expected = ~S'{:ok, (if a, do: "x, y", else: "z")}'

      confirm_fix(fix(code), expected)
    end

    test "?, and ?} char literals do not end the span" do
      code = "[:a, if a, do: ?,, else: ?}]"

      expected = "[:a, (if a, do: ?,, else: ?})]"

      confirm_fix(fix(code), expected)
    end

    test "multi-codepoint text earlier on the line does not shift the columns" do
      code = ~S'{"café 👨‍👩‍👧 🇫🇷", if a, do: 1, else: 2}'

      expected = ~S'{"café 👨‍👩‍👧 🇫🇷", (if a, do: 1, else: 2)}'

      confirm_fix(fix(code), expected)
    end
  end

  describe "stops at the conditional, not at the container" do
    test "a foreign keyword pair after the else: stays in the container" do
      code = "{:ok, if a, do: 1, else: 2, k: [do: 5]}"

      expected = "{:ok, (if a, do: 1, else: 2), k: [do: 5]}"

      confirm_fix(fix(code), expected)
    end

    test "two do:-only conditionals on one line are wrapped separately" do
      code = "%{a: if x, do: 1, b: if y, do: 2}"

      expected = "%{a: (if x, do: 1), b: (if y, do: 2)}"

      confirm_fix(fix(code), expected)
    end

    test "two do:/else: conditionals on one line are wrapped separately" do
      code = "%{a: if x, do: 1, else: 2, b: if y, do: 3, else: 4}"

      expected = "%{a: (if x, do: 1, else: 2), b: (if y, do: 3, else: 4)}"

      confirm_fix(fix(code), expected)
    end

    test "a conditional nested in the do: branch is wrapped as one span" do
      code = "{:ok, if a, do: (if b, do: 1, else: 2), else: 3}"

      expected = "{:ok, (if a, do: (if b, do: 1, else: 2), else: 3)}"

      confirm_fix(fix(code), expected)
    end

    test "several occurrences across a file are all repaired" do
      code = """
      a = {1, if p, do: 2, else: 3}
      b = [if q, do: 4]
      c = %{k: if r, do: 5, else: 6}
      """

      expected = """
      a = {1, (if p, do: 2, else: 3)}
      b = [(if q, do: 4)]
      c = %{k: (if r, do: 5, else: 6)}
      """

      confirm_fix(fix(code), expected)
    end
  end

  describe "leaves the source byte-identical" do
    test "when it already parses" do
      code = "{:ok, (if a, do: 1, else: 2)}"

      confirm_fix(fix(code), code)
    end

    test "when the ambiguity is blamed on a plain call" do
      code = "{:ok, foo a, b: 1}"

      confirm_fix(fix(code), code)
    end

    test "when the container value is a bare for comprehension" do
      code = "%{foo: for x <- xs, into: %{}, do: {x, x}}"

      confirm_fix(fix(code), code)
    end

    test "when the container value is a bare with" do
      code = "{:ok, with {:ok, x} <- f(), do: x}"

      confirm_fix(fix(code), code)
    end

    test "when the conditional is a nested call argument" do
      code = "f(1, if a, do: 2, else: 3)"

      confirm_fix(fix(code), code)
    end

    test "when the blamed column holds an identifier that starts with if" do
      code = "{:ok, iffy a, b: 1}"

      confirm_fix(fix(code), code)
    end

    test "when a comment separates the do: value from the else:" do
      code = """
      {:ok, if a, do: 1, else: 2 # note
      }
      """

      confirm_fix(fix(code), code)
    end

    test "when the conditional ends beyond the search window" do
      filler = String.duplicate("    # filler\n", 25)

      code = "x = {:ok,\n  if a,\n" <> filler <> "    do: 1,\n    else: 2}\n"

      confirm_fix(fix(code), code)
    end

    test "when the parse error is something else entirely" do
      code = """
      defmodule M do
        def f do
      end
      """

      confirm_fix(fix(code), code)
    end
  end

  describe "the repaired source" do
    test "parses and no longer flags" do
      code = """
      defmodule M do
        def parse_page(params) do
          case Integer.parse(params) do
            {num, _} -> {:ok, if num < 1, do: 1, else: num}
            :error -> {:ok, 1}
          end
        end
      end
      """

      assert valid_syntax?(fix(code))
      assert analyze(fix(code)) == []
    end

    test "compiles, with both branches still belonging to the conditional" do
      code = """
      defmodule Credence.NoKeywordIfBareInTupleFixture do
        def page(n), do: {:ok, if n < 1, do: 1, else: n}
      end
      """

      expected = """
      defmodule Credence.NoKeywordIfBareInTupleFixture do
        def page(n), do: {:ok, (if n < 1, do: 1, else: n)}
      end
      """

      confirm_fix(fix(code), expected)
      assert compiles?(fix(code))
    end
  end
end
