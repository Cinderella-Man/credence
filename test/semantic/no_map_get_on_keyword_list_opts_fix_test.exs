defmodule Credence.Semantic.NoMapGetOnKeywordListOptsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoMapGetOnKeywordListOpts

  @match_msg "Map.get/2 called on keyword list opts"

  defp fix(source, message, line \\ 1) do
    NoMapGetOnKeywordListOpts.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes the source" do
    input = ~S"""
    defmodule M do
      def f(opts \\ []) do
        Map.get(opts, :key, nil)
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def f(opts \\ []) do
        Keyword.get(opts, :key, nil)
      end
    end
    """

    confirm_fix(fix(input, @match_msg), expected)
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix(~S"""
    defmodule M do
      def f(opts \\ []) do
        Map.get(opts, :key, nil)
      end
    end
    """, @match_msg))
  end
end
