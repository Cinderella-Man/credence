defmodule Credence.Syntax.NoMarkdownCodeFencesFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

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

    confirm_fix(fix(input), expected)
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

    confirm_fix(fix(input), input)
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

  test "handles a bare leading triple-backtick line" do
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

  test "leaves docstring-embedded fences intact when the file is broken elsewhere" do
    input = """
    defmodule Solution do
      @moduledoc \"\"\"
      ```elixir
      foo()
      ```
      \"\"\"
      def f(x ->
    end
    """

    confirm_fix(fix(input), input)
  end

  test "strips only the wrapping fences, keeping interior docstring fences" do
    input = """
    ```elixir
    defmodule Solution do
      @moduledoc \"\"\"
      ```
      x
      ```
      \"\"\"
      def f, do: 1
    end
    ```
    """

    expected = """
    defmodule Solution do
      @moduledoc \"\"\"
      ```
      x
      ```
      \"\"\"
      def f, do: 1
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  test "reverts when stripping the wrapping fences still does not parse" do
    input = """
    ```elixir
    defmodule Solution do
      def f(x ->
    end
    ```
    """

    confirm_fix(fix(input), input)
  end
end
