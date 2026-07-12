defmodule Credence.Syntax.FixInlineKeywordIfInWithClauseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixInlineKeywordIfInWithClause

  defp analyze(code), do: FixInlineKeywordIfInWithClause.analyze(code)
  defp fix(code), do: FixInlineKeywordIfInWithClause.fix(code)

  test "fixes the syntax error" do
    input = """
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

    expected = """
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

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
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

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
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

    assert valid_syntax?(fix(input))
  end
end
