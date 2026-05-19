defmodule Credence.Pattern.PreferMapFetchOverHasKeyTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.PreferMapFetchOverHasKey.check(ast, [])
  end

  describe "fixable?/0" do
    test "reports as not fixable" do
      assert Credence.Pattern.PreferMapFetchOverHasKey.fixable?() == false
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK — positive cases
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — positive cases" do
    test "flags if Map.has_key?(map, key)" do
      code = """
      defmodule Example do
        def run(map, key) do
          if Map.has_key?(map, key) do
            map[key]
          else
            nil
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :prefer_map_fetch_over_has_key
      assert issue.message =~ "Map.fetch"
    end

    test "flags Map.has_key? combined with and" do
      code = """
      defmodule Example do
        def run(seen, char, start) do
          if Map.has_key?(seen, char) and seen[char] >= start do
            seen[char] + 1
          else
            start
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :prefer_map_fetch_over_has_key
    end

    test "flags Map.has_key? with or" do
      code = """
      defmodule Example do
        def run(map, key) do
          if Map.has_key?(map, key) or key == :default do
            :ok
          else
            :error
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :prefer_map_fetch_over_has_key
    end

    test "flags Map.has_key? with not" do
      code = """
      defmodule Example do
        def run(map, key) do
          if not Map.has_key?(map, key) do
            Map.put(map, key, 0)
          else
            map
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :prefer_map_fetch_over_has_key
    end

    test "flags multiple if blocks with Map.has_key?" do
      code = """
      defmodule Example do
        def run(map) do
          x = if Map.has_key?(map, :a), do: map[:a], else: 0
          y = if Map.has_key?(map, :b), do: map[:b], else: 0
          x + y
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK — negative cases
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — negative cases" do
    test "does not flag Map.fetch usage" do
      code = """
      defmodule Example do
        def run(map, key) do
          case Map.fetch(map, key) do
            {:ok, val} -> val
            :error -> nil
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Map.get usage" do
      code = """
      defmodule Example do
        def run(map, key) do
          Map.get(map, key, :default)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Map.has_key? outside if/cond" do
      code = """
      defmodule Example do
        def run(map, key) do
          result = Map.has_key?(map, key)
          result
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag pattern matching on maps" do
      code = """
      defmodule Example do
        def run(%{key: value}), do: value
        def run(_), do: nil
      end
      """

      assert check(code) == []
    end

    test "does not flag if with non-map conditions" do
      code = """
      defmodule Example do
        def run(x) do
          if x > 0, do: x, else: 0
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Map.has_key? in guard" do
      code = """
      defmodule Example do
        def run(map, key) when is_map_key(map, key), do: map[key]
        def run(_map, _key), do: nil
      end
      """

      assert check(code) == []
    end
  end
end
