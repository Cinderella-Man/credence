defmodule Credence.Pattern.NoAttrBeforeDefmoduleFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoAttrBeforeDefmodule

  describe "moves attrs into the module" do
    test "single @moduledoc" do
      code = """
      @moduledoc "some doc"
      defmodule Foo do
        def bar, do: :ok
      end

      """

      expected = """
      defmodule Foo do
        @moduledoc "some doc"
        def bar, do: :ok
      end

      """

      assert fix(NoAttrBeforeDefmodule, code) == expected
    end

    test "multiple doc/spec attrs, in order" do
      code =
        """
        @moduledoc "m"
        @doc "f"
        @spec foo() :: :ok
        defmodule Foo do
          def foo, do: :ok
        end

        """

      expected =
        """
        defmodule Foo do
          @moduledoc "m"
          @doc "f"
          @spec foo() :: :ok
          def foo, do: :ok
        end

        """

      assert fix(NoAttrBeforeDefmodule, code) == expected
    end

    test "heredoc @moduledoc is re-indented inside the module" do
      code = "@moduledoc \"\"\"\nSome doc\n\"\"\"\ndefmodule Foo do\n  def bar, do: :ok\nend\n"

      expected =
        "defmodule Foo do\n  @moduledoc \"\"\"\n  Some doc\n  \"\"\"\n  def bar, do: :ok\nend\n"

      assert fix(NoAttrBeforeDefmodule, code) == expected
    end

    test "non-attr code before the attrs stays at the top level" do
      code = """
      IO.puts("hi")
      @moduledoc "d"
      defmodule Foo do
        def bar, do: :ok
      end

      """

      # the blank line left where the attr was is cosmetic (mix format runs after rules)
      expected =
        """
        IO.puts("hi")

        defmodule Foo do
          @moduledoc "d"
          def bar, do: :ok
        end

        """

      assert fix(NoAttrBeforeDefmodule, code) == expected
    end
  end

  describe "leaves code unchanged" do
    test "attribute already inside the module" do
      code = """
      defmodule Foo do
        @moduledoc "d"
        def bar, do: :ok
      end

      """

      assert fix(NoAttrBeforeDefmodule, code) == code
    end

    test "no defmodule at all" do
      code = """
      @moduledoc "d"
      def foo, do: :ok

      """

      assert fix(NoAttrBeforeDefmodule, code) == code
    end

    test "non doc/spec attribute (@impl)" do
      code = """
      @impl true
      defmodule Foo do
        def bar, do: :ok
      end

      """

      assert fix(NoAttrBeforeDefmodule, code) == code
    end

    test "plain module with no leading attrs" do
      code = """
      defmodule Foo do
        def bar, do: :ok
      end

      """

      assert fix(NoAttrBeforeDefmodule, code) == code
    end
  end

  describe "round-trip" do
    test "fixed code compiles and has no remaining issues" do
      code =
        """
        @moduledoc "d"
        @spec rt_foo() :: :ok
        defmodule RtAttrFoo do
          def rt_foo, do: :ok
        end

        """

      fixed = fix(NoAttrBeforeDefmodule, code)

      assert clean?(NoAttrBeforeDefmodule, fixed)
      # the original does not compile (attr outside module); the fixed code must
      assert compiles?(fixed)
    end
  end
end
