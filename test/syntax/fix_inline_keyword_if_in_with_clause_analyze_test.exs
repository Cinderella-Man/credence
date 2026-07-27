defmodule Credence.Syntax.FixInlineKeywordIfInWithClauseAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixInlineKeywordIfInWithClause

  defp analyze(code), do: FixInlineKeywordIfInWithClause.analyze(code)

  test "flags the unparseable code" do
    code = """
    defmodule M do
      def run(list, opts) do
        with {:ok, items} <- parse(list),
             ref <- if item_ref(opts), do: item_ref(opts), else: nil,
             parent <- if parent_ref(opts), do: parent_ref(opts), else: nil do
          {:ok, ref, parent}
        else
          _ -> {:error, :invalid}
        end
      end

      defp parse(list), do: {:ok, list}
      defp item_ref(_), do: "a"
      defp parent_ref(_), do: "b"
    end
    """

    assert [%Issue{rule: :fix_inline_keyword_if_in_with_clause}] = analyze(code)
  end

  test "leaves good code alone" do
    code = """
    defmodule M do
      def run(list, opts) do
        with {:ok, items} <- parse(list) do
          ref = if item_ref(opts), do: item_ref(opts), else: nil
          parent = if parent_ref(opts), do: parent_ref(opts), else: nil
          {:ok, ref, parent}
        else
          _ -> {:error, :invalid}
        end
      end

      defp parse(list), do: {:ok, list}
      defp item_ref(_), do: "a"
      defp parent_ref(_), do: "b"
    end
    """

    assert analyze(code) == []
  end
end
