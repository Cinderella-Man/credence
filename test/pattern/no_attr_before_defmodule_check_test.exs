defmodule Credence.Pattern.NoAttrBeforeDefmoduleCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoAttrBeforeDefmodule
  alias Credence.Issue

  describe "detects" do
    test "@moduledoc before defmodule" do
      code = """
      @moduledoc "some doc"
      defmodule Foo do
        def bar, do: :ok
      end

      """

      assert [%Issue{rule: :no_attr_before_defmodule}] = check(NoAttrBeforeDefmodule, code)
    end

    test "multiple doc/spec attrs before defmodule" do
      code =
        """
        @moduledoc "m"
        @doc "f"
        @spec foo() :: :ok
        defmodule Foo do
          def foo, do: :ok
        end

        """

      assert [%Issue{}] = check(NoAttrBeforeDefmodule, code)
    end

    test "heredoc @moduledoc before defmodule" do
      code = "@moduledoc \"\"\"\nSome doc\n\"\"\"\ndefmodule Foo do\n  def bar, do: :ok\nend\n"
      assert [%Issue{}] = check(NoAttrBeforeDefmodule, code)
    end

    test "fires even when other code precedes the attrs" do
      code = """
      IO.puts("hi")
      @moduledoc "d"
      defmodule Foo do
        def bar, do: :ok
      end

      """

      assert [%Issue{}] = check(NoAttrBeforeDefmodule, code)
    end

    test "reports the attribute's line number" do
      code = """
      @moduledoc "d"
      defmodule Foo do
        def bar, do: :ok
      end

      """

      assert [%Issue{meta: %{line: 1}}] = check(NoAttrBeforeDefmodule, code)
    end
  end

  describe "does not flag" do
    test "attribute already inside the module" do
      code = """
      defmodule Foo do
        @moduledoc "d"
        def bar, do: :ok
      end

      """

      assert check(NoAttrBeforeDefmodule, code) == []
    end

    test "no defmodule at all (we never invent a module)" do
      code = """
      @moduledoc "d"
      def foo, do: :ok

      """

      assert check(NoAttrBeforeDefmodule, code) == []
    end

    test "non doc/spec attribute (@impl) is left where it is" do
      code = """
      @impl true
      defmodule Foo do
        def bar, do: :ok
      end

      """

      assert check(NoAttrBeforeDefmodule, code) == []
    end

    test "plain module with no leading attrs" do
      code = """
      defmodule Foo do
        def bar, do: :ok
      end

      """

      assert check(NoAttrBeforeDefmodule, code) == []
    end
  end
end
