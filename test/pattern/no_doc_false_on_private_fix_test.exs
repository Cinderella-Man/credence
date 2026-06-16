defmodule Credence.Pattern.NoDocFalseOnPrivateFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoDocFalseOnPrivate

  describe "removes a redundant @doc false before a defp" do
    test "single defp" do
      input = """
      defmodule Bad do
        @doc false
        defp helper(x), do: x + 1
      end
      """

      expected = """
      defmodule Bad do
        defp helper(x), do: x + 1
      end
      """

      confirm_fix(fix(NoDocFalseOnPrivate, input), expected)
    end

    test "multiple defps — drops each @doc false, keeps the blank line between them" do
      input = """
      defmodule Bad do
        @doc false
        defp helper1(x), do: x + 1

        @doc false
        defp helper2(x), do: x * 2
      end
      """

      expected = """
      defmodule Bad do
        defp helper1(x), do: x + 1

        defp helper2(x), do: x * 2
      end
      """

      confirm_fix(fix(NoDocFalseOnPrivate, input), expected)
    end

    test "guarded defp" do
      input = """
      defmodule Bad do
        @doc false
        defp helper(x) when is_integer(x), do: x + 1
      end
      """

      expected = """
      defmodule Bad do
        defp helper(x) when is_integer(x), do: x + 1
      end
      """

      confirm_fix(fix(NoDocFalseOnPrivate, input), expected)
    end
  end

  describe "leaves untouched" do
    test "@doc false on a public function" do
      code = """
      defmodule Good do
        @doc false
        def internal_api(x), do: x + 1
      end
      """

      confirm_fix(fix(NoDocFalseOnPrivate, code), code)
    end
  end
end
