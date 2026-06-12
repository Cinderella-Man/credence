defmodule Credence.Pattern.PreferNoQuestionMarkForNonBooleanFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferNoQuestionMarkForNonBoolean

  test "rewrites function with ? suffix and non-boolean return type" do
    input = """
    defmodule Solution do
      @spec find_max_integer?([any()]) :: integer() | nil
      def find_max_integer?([]), do: nil

      def find_max_integer?(list) when is_list(list) do
        if Enum.any?(list, fn element -> not is_integer(element) end) do
          nil
        else
          Enum.max(list)
        end
      end
    end
    """

    expected = """
    defmodule Solution do
      @spec find_max_integer([any()]) :: integer() | nil
      def find_max_integer([]), do: nil

      def find_max_integer(list) when is_list(list) do
        if Enum.any?(list, fn element -> not is_integer(element) end) do
          nil
        else
          Enum.max(list)
        end
      end
    end
    """

    assert fix(PreferNoQuestionMarkForNonBoolean, input) == expected
  end

  test "rewrites function with ? suffix returning String.t()" do
    input = """
    defmodule Example do
      @spec get_name?(atom()) :: String.t() | nil
      def get_name?(:foo), do: "bar"
      def get_name?(_), do: nil
    end
    """

    expected = """
    defmodule Example do
      @spec get_name(atom()) :: String.t() | nil
      def get_name(:foo), do: "bar"
      def get_name(_), do: nil
    end
    """

    assert fix(PreferNoQuestionMarkForNonBoolean, input) == expected
  end

  test "no-op on boolean predicate" do
    code = """
    defmodule Example do
      @spec empty?([any()]) :: boolean()
      def empty?([]), do: true
      def empty?(_), do: false
    end
    """

    assert fix(PreferNoQuestionMarkForNonBoolean, code) == code
  end

  test "no-op on function without ? suffix" do
    code = """
    defmodule Example do
      @spec find_max([any()]) :: integer() | nil
      def find_max([]), do: nil
      def find_max(list), do: Enum.max(list)
    end
    """

    assert fix(PreferNoQuestionMarkForNonBoolean, code) == code
  end
end
