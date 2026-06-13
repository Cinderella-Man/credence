defmodule Credence.Syntax.NoMarkdownCodeFencesFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.NoMarkdownCodeFences

  defp analyze(code), do: NoMarkdownCodeFences.analyze(code)
  defp fix(code), do: NoMarkdownCodeFences.fix(code)

  test "fixes code-fenced source" do
    input = """
    ```elixir
    defmodule Solution do
      def hello, do: :world
    end
    ```
    """

    expected = """
    defmodule Solution do
      def hello, do: :world
    end
    """

    assert fix(input) == expected
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             ```elixir
             defmodule Solution do
               def hello, do: :world
             end
             ```
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             ```elixir
             defmodule Solution do
               def hello, do: :world
             end
             ```
             """)
           )
  end

  test "leaves already-clean source unchanged" do
    input = """
    defmodule Solution do
      def hello, do: :world
    end
    """

    assert fix(input) == input
  end

  test "handles indented code fences" do
    input = """
      ```elixir
      defmodule T do
      end
      ```
    """

    fixed = fix(input)
    refute String.contains?(fixed, "```")
    assert valid_syntax?(fixed)
  end

  test "handles bare triple-backtick lines" do
    input = """
    ```
    defmodule Solution do
      def hello, do: :world
    end
    """

    fixed = fix(input)
    refute String.contains?(fixed, "```")
    assert valid_syntax?(fixed)
  end
end
