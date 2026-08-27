defmodule Credence.Pattern.NoIdentityFunctionInEnumFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoIdentityFunctionInEnum

  describe "fix/2 — direct calls" do
    test "fixes Enum.uniq_by(list, fn x -> x end) → Enum.uniq(list)" do
      input = """
      defmodule Example do
        def run(list), do: Enum.uniq_by(list, fn x -> x end)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: Enum.uniq(list)
      end
      """

      confirm_fix(fix(NoIdentityFunctionInEnum, input), expected)
    end

    test "fixes Enum.sort_by(list, fn x -> x end) → Enum.sort(list)" do
      input = """
      defmodule Example do
        def run(list), do: Enum.sort_by(list, fn item -> item end)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: Enum.sort(list)
      end
      """

      confirm_fix(fix(NoIdentityFunctionInEnum, input), expected)
    end

    test "fixes Enum.min_by(list, fn x -> x end) → Enum.min(list)" do
      input = """
      defmodule Example do
        def run(list), do: Enum.min_by(list, fn x -> x end)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: Enum.min(list)
      end
      """

      confirm_fix(fix(NoIdentityFunctionInEnum, input), expected)
    end

    test "fixes Enum.max_by(list, & &1) → Enum.max(list)" do
      input = """
      defmodule Example do
        def run(list), do: Enum.max_by(list, & &1)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: Enum.max(list)
      end
      """

      confirm_fix(fix(NoIdentityFunctionInEnum, input), expected)
    end

    test "fixes Enum.dedup_by(list, fn x -> x end) → Enum.dedup(list)" do
      input = """
      defmodule Example do
        def run(list), do: Enum.dedup_by(list, fn x -> x end)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: Enum.dedup(list)
      end
      """

      confirm_fix(fix(NoIdentityFunctionInEnum, input), expected)
    end
  end

  describe "fix/2 — piped calls" do
    test "fixes |> Enum.uniq_by(fn x -> x end) → |> Enum.uniq()" do
      input = """
      defmodule Example do
        def run(list), do: list |> Enum.uniq_by(fn x -> x end)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: list |> Enum.uniq()
      end
      """

      confirm_fix(fix(NoIdentityFunctionInEnum, input), expected)
    end

    test "fixes in a longer pipeline" do
      input = """
      defmodule Example do
        def run(str) do
          str |> String.graphemes() |> Enum.uniq_by(fn g -> g end)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(str) do
          str |> String.graphemes() |> Enum.uniq()
        end
      end
      """

      confirm_fix(fix(NoIdentityFunctionInEnum, input), expected)
    end

    test "fixes piped & &1" do
      input = """
      defmodule Example do
        def run(list), do: list |> Enum.sort_by(& &1)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: list |> Enum.sort()
      end
      """

      confirm_fix(fix(NoIdentityFunctionInEnum, input), expected)
    end
  end

  describe "fix/2 — edge cases" do
    test "does not rewrite a call on a module aliased as Enum" do
      code = """
      defmodule NoIdentityFunctionInEnumAliasedEnumFixture do
        alias MyEnum, as: Enum

        def run(list), do: Enum.uniq_by(list, fn item -> item end)
      end
      """

      confirm_fix(fix(NoIdentityFunctionInEnum, code), code)
    end

    test "does not treat a callback module aliased as Function as canonical" do
      code = """
      defmodule NoIdentityFunctionInEnumAliasedFunctionFixture do
        alias MyCallbacks, as: Function

        def run(list), do: Enum.max_by(list, &Function.identity/1)
      end
      """

      confirm_fix(fix(NoIdentityFunctionInEnum, code), code)
    end

    test "does not touch non-identity callbacks" do
      code = """
      defmodule Example do
        def run(list), do: Enum.sort_by(list, fn x -> -x end)
      end
      """

      confirm_fix(fix(NoIdentityFunctionInEnum, code), code)
    end

    test "returns source unchanged when nothing to fix" do
      code = """
      defmodule Example do
        def run(list), do: Enum.uniq(list)
      end
      """

      confirm_fix(fix(NoIdentityFunctionInEnum, code), code)
    end

    test "preserves surrounding code" do
      input = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(list), do: list |> Enum.uniq_by(fn x -> x end)
        def baz(y), do: y * 2
      end
      """

      expected = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(list), do: list |> Enum.uniq()
        def baz(y), do: y * 2
      end
      """

      confirm_fix(fix(NoIdentityFunctionInEnum, input), expected)
    end
  end
end
