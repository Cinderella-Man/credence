defmodule Credence.Pattern.PreferNoQuestionMarkForNonBooleanFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferNoQuestionMarkForNonBoolean

  test "rewrites private function with ? suffix and non-boolean return type" do
    input = """
    defmodule Solution do
      @spec find_max_integer?([any()]) :: integer() | nil
      defp find_max_integer?([]), do: nil

      defp find_max_integer?(list) when is_list(list) do
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
      defp find_max_integer([]), do: nil

      defp find_max_integer(list) when is_list(list) do
        if Enum.any?(list, fn element -> not is_integer(element) end) do
          nil
        else
          Enum.max(list)
        end
      end
    end
    """

    confirm_fix(fix(PreferNoQuestionMarkForNonBoolean, input), expected)
  end

  test "rewrites private function with ? suffix returning String.t()" do
    input = """
    defmodule Example do
      @spec get_name?(atom()) :: String.t() | nil
      defp get_name?(:foo), do: "bar"
      defp get_name?(_), do: nil
    end
    """

    expected = """
    defmodule Example do
      @spec get_name(atom()) :: String.t() | nil
      defp get_name(:foo), do: "bar"
      defp get_name(_), do: nil
    end
    """

    confirm_fix(fix(PreferNoQuestionMarkForNonBoolean, input), expected)
  end

  test "does not rename variables that share the private function name" do
    input = """
    defmodule VariableNameWitness do
      @spec count?() :: integer()
      defp count?, do: 9

      def value do
        count = 1
        count? = 2
        count + count? + count?()
      end
    end
    """

    expected = """
    defmodule VariableNameWitness do
      @spec count() :: integer()
      defp count, do: 9

      def value do
        count = 1
        count? = 2
        count + count? + count()
      end
    end
    """

    confirm_fix(fix(PreferNoQuestionMarkForNonBoolean, input), expected)
  end

  test "no-op on a public def with ? suffix (breaking API rename)" do
    code = """
    defmodule Example do
      @spec get_name?(atom()) :: String.t() | nil
      def get_name?(:foo), do: "bar"
      def get_name?(_), do: nil
    end
    """

    confirm_fix(fix(PreferNoQuestionMarkForNonBoolean, code), code)
  end

  test "no-op on boolean predicate" do
    code = """
    defmodule Example do
      @spec empty?([any()]) :: boolean()
      def empty?([]), do: true
      def empty?(_), do: false
    end
    """

    confirm_fix(fix(PreferNoQuestionMarkForNonBoolean, code), code)
  end

  test "no-op when the de-suffixed name already names a function (collision)" do
    code = """
    defmodule Example do
      @spec count?() :: integer()
      defp count?, do: 1
      defp count, do: 2
      def a, do: count?()
      def b, do: count()
    end
    """

    confirm_fix(fix(PreferNoQuestionMarkForNonBoolean, code), code)
  end

  test "no-op on function without ? suffix" do
    code = """
    defmodule Example do
      @spec find_max([any()]) :: integer() | nil
      def find_max([]), do: nil
      def find_max(list), do: Enum.max(list)
    end
    """

    confirm_fix(fix(PreferNoQuestionMarkForNonBoolean, code), code)
  end
end
