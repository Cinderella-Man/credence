defmodule Credence.Semantic.NoUnusedTypeDeclarationFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUnusedTypeDeclaration

  defp fix(source, message, line) do
    NoUnusedTypeDeclaration.fix(source, %{
      severity: :warning,
      message: message,
      position: line
    })
  end

  # Compiler messages for `source`, through the same capture the semantic phase
  # itself uses (it purges the fixture module, so compiling before and after the
  # rewrite earns no "redefining module" noise).
  defp diagnostics(source) do
    {_status, diagnostics} = Credence.RuleHelpers.compile_and_capture(source)
    Enum.map(diagnostics, & &1.message)
  end

  test "removes a multi-line declaration" do
    code = """
    defmodule Saga do
      @typep step :: %{
               name: atom(),
               action_fn: function()
             }

      defstruct steps: []

      def new, do: %Saga{steps: []}
    end
    """

    expected = """
    defmodule Saga do
      defstruct steps: []

      def new, do: %Saga{steps: []}
    end
    """

    confirm_fix(fix(code, "type step/0 is unused", 2), expected)
  end

  test "removes a single-line declaration" do
    code = """
    defmodule M do
      @typep name :: atom()

      def hello, do: :world
    end
    """

    expected = """
    defmodule M do
      def hello, do: :world
    end
    """

    confirm_fix(fix(code, "type name/0 is unused", 2), expected)
  end

  test "removes a parameterized declaration" do
    code = """
    defmodule M do
      @typep pair(a) :: {a, a}

      def hello, do: :world
    end
    """

    expected = """
    defmodule M do
      def hello, do: :world
    end
    """

    confirm_fix(fix(code, "type pair/1 is unused", 2), expected)
  end

  test "removes only the declaration the diagnostic names" do
    code = """
    defmodule M do
      @typep name :: atom()
      @typep count :: integer()

      @spec hello() :: name()
      def hello, do: :world
    end
    """

    expected = """
    defmodule M do
      @typep name :: atom()
      @spec hello() :: name()
      def hello, do: :world
    end
    """

    confirm_fix(fix(code, "type count/0 is unused", 3), expected)
  end

  test "keeps the same-named declaration of a different arity" do
    code = """
    defmodule M do
      @typep t :: atom()
      @typep t(a) :: {a}
      @spec hi() :: t()
      def hi, do: :ok
    end
    """

    expected = """
    defmodule M do
      @typep t :: atom()
      @spec hi() :: t()
      def hi, do: :ok
    end
    """

    confirm_fix(fix(code, "type t/1 is unused", 3), expected)
  end

  test "keeps a same-named declaration in another module in the file" do
    code = """
    defmodule Used do
      @typep step :: atom()
      @spec hi() :: step()
      def hi, do: :ok
    end

    defmodule Unused do
      @typep step :: atom()
      def hi, do: :ok
    end
    """

    expected = """
    defmodule Used do
      @typep step :: atom()
      @spec hi() :: step()
      def hi, do: :ok
    end

    defmodule Unused do
      def hi, do: :ok
    end
    """

    confirm_fix(fix(code, "type step/0 is unused", 8), expected)
  end

  test "removes the @typedoc that documents the deleted declaration" do
    code = """
    defmodule M do
      @typedoc "a single step"
      @typep step :: atom()

      def hello, do: :world
    end
    """

    expected = """
    defmodule M do
      def hello, do: :world
    end
    """

    confirm_fix(fix(code, "type step/0 is unused", 3), expected)
  end

  test "leaves a @typedoc that documents a different type alone" do
    code = """
    defmodule M do
      @typedoc "the public one"
      @type pub :: atom()
      @typep step :: atom()

      @spec hello() :: pub()
      def hello, do: :world
    end
    """

    expected = """
    defmodule M do
      @typedoc "the public one"
      @type pub :: atom()
      @spec hello() :: pub()
      def hello, do: :world
    end
    """

    confirm_fix(fix(code, "type step/0 is unused", 4), expected)
  end

  test "no-op: the declaration sits inside a quote" do
    code = """
    defmodule M do
      defmacro define do
        quote do
          @typep step :: atom()
        end
      end
    end
    """

    confirm_fix(fix(code, "type step/0 is unused", 4), code)
  end

  test "no-op: the declaration is the module's whole body" do
    code = """
    defmodule M do
      @typep step :: atom()
    end
    """

    confirm_fix(fix(code, "type step/0 is unused", 2), code)
  end

  test "no-op: the flagged line holds no matching declaration" do
    code = """
    defmodule M do
      @typep step :: atom()
      def hi, do: :ok
    end
    """

    confirm_fix(fix(code, "type step/0 is unused", 3), code)
  end

  test "no-op: the message is not this rule's" do
    code = """
    defmodule M do
      @typep name :: atom()
      def hello, do: :world
    end
    """

    confirm_fix(fix(code, "unrelated warning", 2), code)
  end

  test "no-op: the diagnostic carries no usable position" do
    code = """
    defmodule M do
      @typep name :: atom()
      def hello, do: :world
    end
    """

    confirm_fix(
      NoUnusedTypeDeclaration.fix(code, %{
        severity: :warning,
        message: "type name/0 is unused",
        position: nil
      }),
      code
    )
  end

  test "no-op: the source does not parse" do
    code = """
    defmodule M do
      @typep step ::
    """

    confirm_fix(fix(code, "type step/0 is unused", 2), code)
  end

  test "the rewrite clears the warning and introduces no new one" do
    code = """
    defmodule CredenceUnusedTypepCleared do
      @typep step :: %{name: atom()}

      def hi, do: :ok
    end
    """

    assert diagnostics(code) == ["type step/0 is unused"]
    assert diagnostics(fix(code, "type step/0 is unused", 2)) == []
  end

  test "removing the @typedoc too avoids trading one warning for another" do
    code = """
    defmodule CredenceUnusedTypepTypedoc do
      @typedoc "a single step"
      @typep step :: atom()

      def hi, do: :ok
    end
    """

    assert diagnostics(code) == [
             "type step/0 is private, @typedoc's are always discarded for private types",
             "type step/0 is unused"
           ]

    assert diagnostics(fix(code, "type step/0 is unused", 3)) == []
  end

  test "fixed output is well-formed (parses)" do
    code = """
    defmodule M do
      @typep name :: atom()
      def hello, do: :world
    end
    """

    assert valid_syntax?(fix(code, "type name/0 is unused", 2))
  end
end
