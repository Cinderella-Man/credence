defmodule Credence.Syntax.PreferCondDoKeywordFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.PreferCondDoKeyword

  defp analyze(code), do: PreferCondDoKeyword.analyze(code)
  defp fix(code), do: PreferCondDoKeyword.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule Solution do
      def find_min(list) do
        cond ->
          list == [] -> nil
          true -> Enum.min(list)
        end
      end
    end
    """

    expected = """
    defmodule Solution do
      def find_min(list) do
        cond do
          list == [] -> nil
          true -> Enum.min(list)
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes two real `cond ->` errors in one pass" do
    input = """
    defmodule Credence.PreferCondDoKeywordTwoErrorsFixture do
      def first(x) do
        cond ->
          x -> :x
          true -> :no
        end
      end

      def second(y) do
        cond ->
          y -> :y
          true -> :no
        end
      end
    end
    """

    expected = """
    defmodule Credence.PreferCondDoKeywordTwoErrorsFixture do
      def first(x) do
        cond do
          x -> :x
          true -> :no
        end
      end

      def second(y) do
        cond do
          y -> :y
          true -> :no
        end
      end
    end
    """

    emitted = fix(input)

    confirm_fix(emitted, expected)

    assert Credence.RuleHelpers.compile_and_capture(emitted) ==
             Credence.RuleHelpers.compile_and_capture(expected)
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             defmodule Solution do
               def find_min(list) do
                 cond ->
                   list == [] -> nil
                   true -> Enum.min(list)
                 end
               end
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               def find_min(list) do
                 cond ->
                   list == [] -> nil
                   true -> Enum.min(list)
                 end
               end
             end
             """)
           )
  end

  test "leaves a `cond ->` inside a docstring untouched when the file is broken elsewhere" do
    input = """
    defmodule Solution do
      @moduledoc \"\"\"
      Example: cond -> in other languages.
      \"\"\"
      def f(list) do
        Enum.map(list
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixes the real `cond ->` while preserving a `cond ->` in a docstring" do
    input = """
    defmodule Solution do
      @moduledoc \"\"\"
      Like cond -> in other languages.
      \"\"\"
      def find_min(list) do
        cond ->
          list == [] -> nil
          true -> Enum.min(list)
        end
      end
    end
    """

    expected = """
    defmodule Solution do
      @moduledoc \"\"\"
      Like cond -> in other languages.
      \"\"\"
      def find_min(list) do
        cond do
          list == [] -> nil
          true -> Enum.min(list)
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  # ═══════════════════════════════════════════════════════════════════
  # ALREADY-PARSING SOURCE — there is nothing to repair
  #
  # The parse gate proves the RESULT parses, not that the replacement
  # repaired anything. On source that already parsed, every candidate
  # satisfied it, so the first occurrence won wherever it sat — including
  # inside a literal, where the moduledoc promises it is safe. The Syntax
  # phase never runs on parsing source, so declining costs nothing.
  # Found by running the rule over its own source file.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — source that already parses is declined" do
    test "leaves `cond ->` inside a string alone" do
      code = ~S'IO.puts("write cond -> here")'

      confirm_fix(fix(code), code)
      assert valid_syntax?(code)
    end

    test "does not report `cond ->` inside a string" do
      assert analyze(~S'IO.puts("write cond -> here")') == []
    end

    test "leaves a heredoc body alone when the file parses" do
      code = ~S'''
      defmodule M do
        @moduledoc """
        Like cond -> in other languages.
        """
        def f(x), do: x
      end
      '''

      confirm_fix(fix(code), code)
    end

    test "the rule does not rewrite its own source file" do
      source = File.read!("lib/syntax/prefer_cond_do_keyword.ex")

      confirm_fix(fix(source), source)
    end

    test "the pipeline path is unaffected — a non-parsing file is still repaired" do
      input = """
      defmodule M do
        def f(x) do
          cond ->
            x > 0 -> :pos
            true -> :neg
          end
        end
      end
      """

      refute valid_syntax?(input)
      assert valid_syntax?(fix(input))
      assert analyze(input) != []
    end
  end
end
