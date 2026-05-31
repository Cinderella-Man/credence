defmodule Credence.Pattern.NoChunkByIdentityForDedupTest do
  use ExUnit.Case

  alias Credence.Pattern.NoChunkByIdentityForDedup

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoChunkByIdentityForDedup.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoChunkByIdentityForDedup, code, [])
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

      issues = check(code)
      assert length(issues) == 1
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

      issues = check(code)
      assert length(issues) == 1
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

      issues = check(code)
      assert length(issues) == 1
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

      issues = check(code)
      assert length(issues) == 1
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

    test "does not flag chunk_by with identity but different map function" do
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
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — pipeline forms
  # ═══════════════════════════════════════════════════════════════════

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

      fixed = fix(code)
      assert fixed =~ "Enum.dedup()"
      refute fixed =~ "chunk_by"
      refute fixed =~ "List.first"
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

      fixed = fix(code)
      assert fixed =~ "Enum.dedup()"
      assert fixed =~ "Enum.join()"
      refute fixed =~ "chunk_by"
      refute fixed =~ "map_join"
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

      fixed = fix(code)
      assert fixed =~ "String.graphemes()"
      assert fixed =~ "Enum.dedup()"
      assert fixed =~ "Enum.join()"
      refute fixed =~ "chunk_by"
      refute fixed =~ "List.first"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — direct call forms
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — direct call forms" do
    test "fixes Enum.map(Enum.chunk_by(list, & &1), &List.first/1)" do
      code = """
      defmodule Example do
        def dedup(list), do: Enum.map(Enum.chunk_by(list, & &1), &List.first/1)
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.dedup(list)"
      refute fixed =~ "chunk_by"
      refute fixed =~ "List.first"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — edge cases
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — edge cases" do
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

      fixed = fix(code)
      assert fixed =~ "def foo(x), do: x + 1"
      assert fixed =~ "Enum.dedup()"
      assert fixed =~ "def bar(y), do: y * 2"
    end
  end
end
