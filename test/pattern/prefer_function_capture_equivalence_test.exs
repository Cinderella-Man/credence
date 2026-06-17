defmodule Credence.Pattern.PreferFunctionCaptureEquivalenceTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferFunctionCapture

  test "fix preserves behaviour" do
    before = """
    defmodule TestFnCapture do
      def find_min_in_sublists(list_of_lists) do
        list_of_lists
        |> Enum.map(fn sublist -> Enum.min(sublist) end)
      end
    end
    """

    assert_equivalent_module(before,
      rule: PreferFunctionCapture,
      call: {:find_min_in_sublists, 1},
      inputs: [[[1, 2, 3], [4, 5, 6]], [[-1, 0, 1], [10, 20]], [[5]]]
    )
  end

  test "fix preserves behaviour for local function" do
    before = """
    defmodule TestLocalCapture do
      def convert_all(items) do
        items
        |> Enum.map(fn x -> to_string(x) end)
      end
    end
    """

    assert_equivalent_module(before,
      rule: PreferFunctionCapture,
      call: {:convert_all, 1},
      inputs: [[[1, 2, 3], [:a, :b], ["hello"]], [[42]], [[]]]
    )
  end

  test "fix preserves behaviour for Kernel function" do
    before = """
    defmodule TestKernelCapture do
      def get_lengths(lists) do
        lists
        |> Enum.map(fn x -> length(x) end)
      end
    end
    """

    assert_equivalent_module(before,
      rule: PreferFunctionCapture,
      call: {:get_lengths, 1},
      inputs: [[[1, 2, 3], [4, 5]], [[1]], [[]]]
    )
  end
end
