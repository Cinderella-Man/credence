defmodule Credence.Pattern.NoIdentityFunctionInEnumCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoIdentityFunctionInEnum

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoIdentityFunctionInEnum.check(ast, [])
  end

  describe "check/2 — detects identity fn in _by variants" do
    test "flags Enum.uniq_by with fn x -> x end" do
      code = """
      defmodule Example do
        def run(list), do: Enum.uniq_by(list, fn x -> x end)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_identity_function_in_enum
      assert issue.message =~ "Enum.uniq"
    end

    test "flags Enum.sort_by with fn item -> item end" do
      code = """
      defmodule Example do
        def run(list), do: Enum.sort_by(list, fn item -> item end)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.sort"
    end

    test "flags Enum.min_by with fn x -> x end" do
      code = """
      defmodule Example do
        def run(list), do: Enum.min_by(list, fn x -> x end)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.min"
    end

    test "flags Enum.max_by with fn x -> x end" do
      code = """
      defmodule Example do
        def run(list), do: Enum.max_by(list, fn x -> x end)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.max"
    end

    test "flags Enum.dedup_by with fn x -> x end" do
      code = """
      defmodule Example do
        def run(list), do: Enum.dedup_by(list, fn x -> x end)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.dedup"
    end

    test "flags piped form with identity fn" do
      code = """
      defmodule Example do
        def run(list), do: list |> Enum.uniq_by(fn x -> x end)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_identity_function_in_enum
    end

    test "flags & &1 capture" do
      code = """
      defmodule Example do
        def run(list), do: Enum.sort_by(list, & &1)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.sort"
    end

    test "flags piped & &1" do
      code = """
      defmodule Example do
        def run(list), do: list |> Enum.uniq_by(& &1)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_identity_function_in_enum
    end

    test "flags with long variable name" do
      code = """
      defmodule Example do
        def run(items), do: items |> Enum.uniq_by(fn grapheme -> grapheme end)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_identity_function_in_enum
    end

    test "flags inside a pipeline" do
      code = """
      defmodule Example do
        def run(str) do
          str |> String.graphemes() |> Enum.uniq_by(fn g -> g end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_identity_function_in_enum
    end
  end

  describe "check/2 — negative cases" do
    test "does not flag Enum.uniq (already simplified)" do
      code = """
      defmodule Example do
        def run(list), do: Enum.uniq(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag non-identity function" do
      code = """
      defmodule Example do
        def run(list), do: Enum.sort_by(list, fn x -> -x end)
      end
      """

      assert check(code) == []
    end

    test "does not flag uniq_by with a transformation" do
      code = """
      defmodule Example do
        def run(list), do: Enum.uniq_by(list, fn x -> String.downcase(x) end)
      end
      """

      assert check(code) == []
    end

    test "does not flag uniq_by with field access" do
      code = """
      defmodule Example do
        def run(list), do: Enum.uniq_by(list, & &1.name)
      end
      """

      assert check(code) == []
    end

    test "does not flag fn with different variables in arg and body" do
      code = """
      defmodule Example do
        def run(list), do: Enum.sort_by(list, fn x -> y end)
      end
      """

      assert check(code) == []
    end

    test "does not flag multi-clause fn" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.sort_by(list, fn
            nil -> 0
            x -> x
          end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
