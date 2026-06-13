defmodule Credence.Syntax.NoMarkdownCodeFencesAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoMarkdownCodeFences

  defp analyze(code), do: NoMarkdownCodeFences.analyze(code)

  test "flags a code-fence line with language tag" do
    assert [%Issue{rule: :no_markdown_code_fences, meta: %{line: 1}},
            %Issue{rule: :no_markdown_code_fences, meta: %{line: 5}}] =
             analyze("""
             ```elixir
             defmodule Solution do
               def hello, do: :world
             end
             ```
             """)
  end

  test "flags multiple code-fence lines" do
    issues =
      analyze("""
      ```elixir
      defmodule Solution do
        def hello, do: :world
      end
      ```
      """)

    assert length(issues) == 2
    assert Enum.all?(issues, &(&1.rule == :no_markdown_code_fences))
  end

  test "flags a bare triple-backtick line (no language tag)" do
    assert [%Issue{rule: :no_markdown_code_fences}] =
             analyze("""
             ```
             def hello, do: :world
             end
             """)
  end

  test "leaves good code alone" do
    assert analyze("""
           defmodule Solution do
             def hello, do: :world
           end
           """) == []
  end
end
