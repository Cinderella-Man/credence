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

  test "reorders a three-module chain transitively" do
    input = """
    defmodule CsrChainBuilder do
      def build, do: %CsrChainWrap{core: nil}
    end

    defmodule CsrChainWrap do
      defstruct [:core]
      def with_core, do: %CsrChainWrap{core: %CsrChainCore{}}
    end

    defmodule CsrChainCore do
      defstruct [:id]
    end
    """

    expected = """
    defmodule CsrChainCore do
      defstruct [:id]
    end

    defmodule CsrChainWrap do
      defstruct [:core]
      def with_core, do: %CsrChainWrap{core: %CsrChainCore{}}
    end

    defmodule CsrChainBuilder do
      def build, do: %CsrChainWrap{core: nil}
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "self-reference inside the struct module does not block reordering" do
    input = """
    defmodule CsrSelfFactory do
      def build, do: %CsrSelfUser{id: 1}
    end

    defmodule CsrSelfUser do
      defstruct [:id]
      def new, do: %CsrSelfUser{id: 0}
    end
    """

    expected = """
    defmodule CsrSelfUser do
      defstruct [:id]
      def new, do: %CsrSelfUser{id: 0}
    end

    defmodule CsrSelfFactory do
      def build, do: %CsrSelfUser{id: 1}
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "no-op when a comment sits between modules (reorder would drop it)" do
    input = """
    defmodule CsrCommentFactory do
      def build, do: %CsrCommentUser{}
    end

    # documents the user module
    defmodule CsrCommentUser do
      defstruct [:id]
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "no-op (and no crash) when the file contains an atom-named defmodule" do
    input = """
    defmodule CsrAtomFactory do
      def build, do: %CsrAtomUser{}
    end

    defmodule :csr_legacy do
      def x, do: 1
    end

    defmodule CsrAtomUser do
      defstruct [:id]
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "no-op when reordering would break a compile-time dependency (import)" do
    input = """
    defmodule CsrImpFactory do
      def build, do: %CsrImpUser{}
    end

    defmodule CsrImpUser do
      import CsrImpFactory
      defstruct [:id]
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "no-op when the referenced module defines no struct" do
    input = """
    defmodule CsrPlainFactory do
      def build, do: %CsrPlainOther{}
    end

    defmodule CsrPlainOther do
      def x, do: 1
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "no-op on a single top-level module (nested forward struct ref)" do
    input = """
    defmodule CsrNested do
      def f, do: %CsrNested.Inner{}

      defmodule Inner do
        defstruct [:x]
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "no-op on a genuine cycle of struct references" do
    input = """
    defmodule CsrCycleA do
      defstruct [:b]
      def f, do: %CsrCycleB{}
    end

    defmodule CsrCycleB do
      defstruct [:a]
      def g, do: %CsrCycleA{}
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "end-to-end: the semantic phase dispatches the real diagnostic to this rule" do
    input = """
    defmodule CsrE2eFactory do
      def build, do: %CsrE2eUser{name: "test"}
    end

    defmodule CsrE2eUser do
      defstruct [:name]
    end
    """

    expected = """
    defmodule CsrE2eUser do
      defstruct [:name]
    end

    defmodule CsrE2eFactory do
      def build, do: %CsrE2eUser{name: "test"}
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
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
