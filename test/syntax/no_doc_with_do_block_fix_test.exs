defmodule Credence.Syntax.NoDocWithDoBlockFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoDocWithDoBlock

  defp fix(code), do: NoDocWithDoBlock.fix(code)
  defp analyze(code), do: NoDocWithDoBlock.analyze(code)

  test "removes the stray do from @doc, rebalancing the module" do
    input = """
    defmodule Solution do
      @doc "top_n_items/2" do
      def find_top_n_items(map_data, n_items) do
        Enum.map(map_data, fn {key, value} -> {key, value} end)
      end
    end
    """

    expected = """
    defmodule Solution do
      @doc "top_n_items/2"
      def find_top_n_items(map_data, n_items) do
        Enum.map(map_data, fn {key, value} -> {key, value} end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "removes the stray do from @moduledoc" do
    input = ~S'@moduledoc "the module" do'

    expected = ~S'@moduledoc "the module"'

    confirm_fix(fix(input), expected)
  end

  test "leaves a proper @doc untouched" do
    source = ~S'@doc "top_n_items/2"'

    confirm_fix(fix(source), source)
  end

  test "leaves a real do block on a def untouched" do
    source = """
    def find(map, n) do
      Enum.take(map, n)
    end
    """

    confirm_fix(fix(source), source)
  end

  test "leaves a @doc string ending in the word do untouched" do
    source = ~S'@doc "explains what to do"'

    confirm_fix(fix(source), source)
  end

  test "leaves an expression-valued @doc (conditional doc) untouched" do
    source = """
    @doc (if prod? do
            "prod"
          else
            "dev"
          end)
    """

    confirm_fix(fix(source), source)
  end

  test "repairs more than one stray-do attribute in the same source" do
    input = """
    defmodule Solution do
      @moduledoc "m" do
      @doc "f/1" do
      def f(x), do: x
    end
    """

    expected = """
    defmodule Solution do
      @moduledoc "m"
      @doc "f/1"
      def f(x), do: x
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fix clears the analyze flag (fixpoint)" do
    assert analyze(
             fix("""
             defmodule Solution do
               @doc "top_n_items/2" do
               def find(map, n), do: Enum.take(map, n)
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               @doc "top_n_items/2" do
               def find_top_n_items(map_data, n_items) do
                 Enum.map(map_data, fn {key, value} -> {key, value} end)
               end
             end
             """)
           )
  end

  # ═══════════════════════════════════════════════════════════════════
  # HEREDOC BODIES — a documented example of the bug is not the bug
  #
  # The pattern is anchored to a whole line, so a trailing comment and a
  # mid-line string were never reachable. A heredoc body line IS a whole
  # line, and this rule rewrote the `## Bad` example in its own moduledoc.
  # Found by running the rule over its own source file.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — heredoc bodies are not code" do
    test "leaves a documented example of the bug alone" do
      code = ~S'''
      defmodule Doc do
        @moduledoc """
        ## Bad

            @doc "top_n_items/2" do
        """
        def f(x), do: x
      end
      '''

      confirm_fix(fix(code), code)
    end

    test "does not report a documented example of the bug" do
      code = ~S'''
      defmodule Doc do
        @moduledoc """
            @doc "top_n_items/2" do
        """
        def f(x), do: x
      end
      '''

      assert analyze(code) == []
    end

    test "still repairs the real bug below a heredoc that documents it" do
      input = ~S'''
      defmodule Doc do
        @moduledoc """
            @doc "top_n_items/2" do
        """
        @doc "find/2" do
        def f(x), do: x
      end
      '''

      expected = ~S'''
      defmodule Doc do
        @moduledoc """
            @doc "top_n_items/2" do
        """
        @doc "find/2"
        def f(x), do: x
      end
      '''

      confirm_fix(fix(input), expected)
    end

    test "the rule does not rewrite its own source file" do
      source = File.read!("lib/syntax/no_doc_with_do_block.ex")

      confirm_fix(fix(source), source)
    end
  end
end
