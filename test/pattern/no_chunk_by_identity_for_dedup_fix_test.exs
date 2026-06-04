defmodule Credence.Pattern.NoChunkByIdentityForDedupFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoChunkByIdentityForDedup

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoChunkByIdentityForDedup, code, [])
  end

  describe "fix/2 — pipeline forms" do
    test "fixes |> chunk_by(& &1) |> map(&List.first/1) → |> dedup()" do
      code = """
      defmodule Example do
        def dedup(list) do
          list
          |> Enum.chunk_by(& &1)
          |> Enum.map(&List.first/1)
        end
      end
      """

      expected = """
      defmodule Example do
        def dedup(list) do
          list
          |> Enum.dedup()
        end
      end
      """

      assert fix(code) == expected
    end

    test "fixes |> chunk_by(& &1) |> map_join(&List.first/1) → |> dedup() |> join()" do
      code = """
      defmodule Example do
        def compress(list) do
          list
          |> Enum.chunk_by(& &1)
          |> Enum.map_join(&List.first/1)
        end
      end
      """

      expected = """
      defmodule Example do
        def compress(list) do
          list
          |> Enum.dedup()
          |> Enum.join()
        end
      end
      """

      assert fix(code) == expected
    end

    test "fixes in a longer pipeline preserving surrounding steps" do
      code = """
      defmodule Example do
        def compress(str) do
          str
          |> String.graphemes()
          |> Enum.chunk_by(& &1)
          |> Enum.map(&List.first/1)
          |> Enum.join()
        end
      end
      """

      expected = """
      defmodule Example do
        def compress(str) do
          str
          |> String.graphemes()
          |> Enum.dedup()
          |> Enum.join()
        end
      end
      """

      assert fix(code) == expected
    end

    test "fixes chunk_by(fn x -> x end) pipeline" do
      code = """
      defmodule Example do
        def dedup(list) do
          list
          |> Enum.chunk_by(fn x -> x end)
          |> Enum.map(&List.first/1)
        end
      end
      """

      expected = """
      defmodule Example do
        def dedup(list) do
          list
          |> Enum.dedup()
        end
      end
      """

      assert fix(code) == expected
    end

    test "fixes & hd(&1) extractor pipeline" do
      code = """
      defmodule Example do
        def dedup(list) do
          list
          |> Enum.chunk_by(& &1)
          |> Enum.map(&hd(&1))
        end
      end
      """

      expected = """
      defmodule Example do
        def dedup(list) do
          list
          |> Enum.dedup()
        end
      end
      """

      assert fix(code) == expected
    end
  end

  describe "fix/2 — direct call forms" do
    test "fixes Enum.map(Enum.chunk_by(list, & &1), &List.first/1)" do
      code = """
      defmodule Example do
        def dedup(list), do: Enum.map(Enum.chunk_by(list, & &1), &List.first/1)
      end
      """

      expected = """
      defmodule Example do
        def dedup(list), do: Enum.dedup(list)
      end
      """

      assert fix(code) == expected
    end

    test "fixes Enum.map_join(Enum.chunk_by(list, & &1), &List.first/1)" do
      code = """
      defmodule Example do
        def compress(list), do: Enum.map_join(Enum.chunk_by(list, & &1), &List.first/1)
      end
      """

      expected = """
      defmodule Example do
        def compress(list), do: Enum.dedup(list) |> Enum.join()
      end
      """

      assert fix(code) == expected
    end
  end

  describe "fix/2 — edge cases (no-op)" do
    test "does not touch non-identity chunk_by" do
      code = """
      defmodule Example do
        def group(list), do: list |> Enum.chunk_by(& &1.length) |> Enum.map(&List.first/1)
      end
      """

      assert fix(code) == code
    end

    test "returns source unchanged when nothing to fix" do
      code = """
      defmodule Example do
        def dedup(list), do: Enum.dedup(list)
      end
      """

      assert fix(code) == code
    end

    test "does not touch chunk_by(identity) extracting last" do
      code = """
      defmodule Example do
        def f(list), do: list |> Enum.chunk_by(& &1) |> Enum.map(&List.last/1)
      end
      """

      assert fix(code) == code
    end

    test "preserves surrounding code" do
      code = """
      defmodule Example do
        def foo(x), do: x + 1

        def dedup(list) do
          list
          |> Enum.chunk_by(& &1)
          |> Enum.map(&List.first/1)
        end

        def bar(y), do: y * 2
      end
      """

      expected = """
      defmodule Example do
        def foo(x), do: x + 1

        def dedup(list) do
          list
          |> Enum.dedup()
        end

        def bar(y), do: y * 2
      end
      """

      assert fix(code) == expected
    end
  end
end
