defmodule Credence.Semantic.FixCyclicStructReferenceFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixCyclicStructReference

  @message "MyApp.User.__struct__/1 is undefined, cannot expand struct MyApp.User. Make sure the struct name is correct. If the struct name exists and is correct but it still cannot be found, you likely have cyclic module usage in your code"

  defp fix(source, message, line \\ 1) do
    FixCyclicStructReference.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "reorders modules so struct definition comes first" do
    input = """
    defmodule Factory do
      def build(:user) do
        %MyApp.User{name: "test"}
      end
    end

    defmodule MyApp.User do
      defstruct [:id, :name]
    end
    """

    expected = """
    defmodule MyApp.User do
      defstruct [:id, :name]
    end

    defmodule Factory do
      def build(:user) do
        %MyApp.User{name: "test"}
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Factory do
      def build(:user) do
        %MyApp.User{name: "test"}
      end
    end

    defmodule MyApp.User do
      defstruct [:id, :name]
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when modules already in correct order" do
    input = """
    defmodule MyApp.User do
      defstruct [:id, :name]
    end

    defmodule Factory do
      def build(:user) do
        %MyApp.User{name: "test"}
      end
    end
    """

    result = fix(input, @message)
    confirm_fix(result, input)
  end

  test "returns source unchanged for unrelated error message" do
    input = """
    defmodule Example do
      def test do
        x + 1
      end
    end
    """

    result = fix(input, "unrelated error")
    confirm_fix(result, input)
  end
end
