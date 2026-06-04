defmodule Credence.Pattern.NoChunkByIdentityForDedupCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoChunkByIdentityForDedup

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoChunkByIdentityForDedup.check(ast, [])
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK — positive cases
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — detects chunk_by identity + map first" do
    test "flags chunk_by(& &1) |> Enum.map(&List.first/1)" do
      code = """
      defmodule Example do
        def dedup(list) do
          list
          |> Enum.chunk_by(& &1)
          |> Enum.map(&List.first/1)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_chunk_by_identity_for_dedup
      assert hd(issues).message =~ "Enum.dedup"
    end

    test "flags chunk_by(fn x -> x end) |> Enum.map(&List.first/1)" do
      code = """
      defmodule Example do
        def dedup(list) do
          list
          |> Enum.chunk_by(fn x -> x end)
          |> Enum.map(&List.first/1)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags chunk_by |> Enum.map_join(&List.first/1)" do
      code = """
      defmodule Example do
        def compress(list) do
          list
          |> Enum.chunk_by(& &1)
          |> Enum.map_join(&List.first/1)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_chunk_by_identity_for_dedup
    end

    test "flags direct call: Enum.map(Enum.chunk_by(list, & &1), &List.first/1)" do
      code = """
      defmodule Example do
        def dedup(list), do: Enum.map(Enum.chunk_by(list, & &1), &List.first/1)
      end
      """

      assert length(check(code)) == 1
    end

    test "flags direct call: Enum.map_join(Enum.chunk_by(list, & &1), &List.first/1)" do
      code = """
      defmodule Example do
        def compress(list), do: Enum.map_join(Enum.chunk_by(list, & &1), &List.first/1)
      end
      """

      assert length(check(code)) == 1
    end

    test "flags inside a longer pipeline" do
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

      assert length(check(code)) == 1
    end

    test "flags chunk_by(fn item -> item end)" do
      code = """
      defmodule Example do
        def dedup(list) do
          list
          |> Enum.chunk_by(fn item -> item end)
          |> Enum.map(&List.first/1)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags & hd(&1) as the first-extractor" do
      code = """
      defmodule Example do
        def dedup(list) do
          list
          |> Enum.chunk_by(& &1)
          |> Enum.map(&hd(&1))
        end
      end
      """

      assert length(check(code)) == 1
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK — negative cases
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — negative cases" do
    test "does not flag Enum.dedup (already simplified)" do
      code = """
      defmodule Example do
        def dedup(list), do: Enum.dedup(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag chunk_by with a non-identity function" do
      code = """
      defmodule Example do
        def group(list), do: list |> Enum.chunk_by(& &1.length) |> Enum.map(&List.first/1)
      end
      """

      assert check(code) == []
    end

    test "does not flag chunk_by(identity) with a different map function" do
      code = """
      defmodule Example do
        def sizes(list), do: list |> Enum.chunk_by(& &1) |> Enum.map(&length/1)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.dedup |> Enum.join" do
      code = """
      defmodule Example do
        def dedup_join(list), do: list |> Enum.dedup() |> Enum.join()
      end
      """

      assert check(code) == []
    end

    test "does not flag chunk_by(identity) extracting last instead of first" do
      code = """
      defmodule Example do
        def f(list), do: list |> Enum.chunk_by(& &1) |> Enum.map(&List.last/1)
      end
      """

      assert check(code) == []
    end
  end
end
