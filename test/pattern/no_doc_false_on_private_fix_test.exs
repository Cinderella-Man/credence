defmodule Credence.Pattern.NoDocFalseOnPrivateFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoDocFalseOnPrivate

  describe "removes a redundant @doc before a defp" do
    test "single defp with @doc false" do
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

    test "single defp with @doc string" do
      input = """
      defmodule Bad do
        @doc "Helper that finds the first unique character."
        defp find_first_unique(string), do: string
      end
      """

      expected = """
      defmodule Bad do
        defp find_first_unique(string), do: string
      end
      """

      confirm_fix(fix(NoDocFalseOnPrivate, input), expected)
    end

    test "multiple defps — drops each @doc, keeps the blank line between them" do
      input = """
      defmodule Bad do
        @doc false
        defp helper1(x), do: x + 1

        @doc "Some doc"
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

    test "guarded defp with @doc false" do
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

    test "guarded defp with @doc string" do
      input = """
      defmodule Bad do
        @doc "Guarded helper"
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

    test "defp with a spec keeps the spec and removes @doc false" do
      input = """
      defmodule BadWithSpec do
        @doc false
        @spec helper(integer()) :: integer()
        defp helper(x), do: x + 1
      end
      """

      expected = """
      defmodule BadWithSpec do
        @spec helper(integer()) :: integer()
        defp helper(x), do: x + 1
      end
      """

      fixed = fix(NoDocFalseOnPrivate, input)
      confirm_fix(fixed, expected)
      confirm_fix(fix(NoDocFalseOnPrivate, fixed), fixed)
    end

    test "mix of public @doc and private @doc — only removes private ones" do
      input = """
      defmodule Mixed do
        @doc "Public function"
        def public_fn(x), do: helper(x)

        @doc "Private helper"
        defp helper(x), do: x + 1
      end
      """

      expected = """
      defmodule Mixed do
        @doc "Public function"
        def public_fn(x), do: helper(x)

        defp helper(x), do: x + 1
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

    test "@doc string on a public function" do
      code = """
      defmodule Good do
        @doc "Does something"
        def process(x), do: x + 1
      end
      """

      confirm_fix(fix(NoDocFalseOnPrivate, code), code)
    end
  end
end
