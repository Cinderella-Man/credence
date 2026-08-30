defmodule Credence.Pattern.FixMapFetchCaseMatchFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.FixMapFetchCaseMatch

  # ═══════════════════════════════════════════════════════════════════
  # FIXABLE — bare map pattern in case Map.fetch success clause
  # ═══════════════════════════════════════════════════════════════════

  describe "wraps bare map patterns in {:ok, ...}" do
    test "map-match pattern (%{...} = var)" do
      input = """
      case Map.fetch(state, key) do
        :error ->
          Map.put(state, key, %{callers: [from]})

        %{callers: callers} = info ->
          Map.put(state, key, %{info | callers: [from | callers]})
      end
      """

      expected = """
      case Map.fetch(state, key) do
        :error ->
          Map.put(state, key, %{callers: [from]})

        {:ok, %{callers: callers} = info} ->
          Map.put(state, key, %{info | callers: [from | callers]})
      end
      """

      confirm_fix(fix(FixMapFetchCaseMatch, input), expected)
    end

    test "bare map literal pattern (%{...})" do
      input = """
      case Map.fetch(state, key) do
        :error -> nil
        %{callers: callers} -> callers
      end
      """

      expected = """
      case Map.fetch(state, key) do
        :error -> nil
        {:ok, %{callers: callers}} -> callers
      end
      """

      confirm_fix(fix(FixMapFetchCaseMatch, input), expected)
    end

    test "single-line case" do
      input = "case Map.fetch(m, k) do :error -> nil; %{x: x} -> x end"

      expected = "case Map.fetch(m, k) do :error -> nil; {:ok, %{x: x}} -> x end"

      confirm_fix(fix(FixMapFetchCaseMatch, input), expected)
    end

    test "guarded bare map pattern" do
      input = """
      case Map.fetch(m, k) do
        :error -> nil
        %{y: y} when is_integer(y) -> y
      end
      """

      expected = """
      case Map.fetch(m, k) do
        :error -> nil
        {:ok, %{y: y}} when is_integer(y) -> y
      end
      """

      confirm_fix(fix(FixMapFetchCaseMatch, input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NOT FIXABLE — left untouched
  # ═══════════════════════════════════════════════════════════════════

  describe "leaves correct code untouched" do
    test "already wrapped in {:ok, ...}" do
      code = """
      case Map.fetch(state, key) do
        :error -> nil
        {:ok, %{callers: callers} = info} -> info
      end
      """

      confirm_fix(fix(FixMapFetchCaseMatch, code), code)
    end

    test "already wrapped {:ok, _}" do
      code = """
      case Map.fetch(state, key) do
        :error -> nil
        {:ok, val} -> val
      end
      """

      confirm_fix(fix(FixMapFetchCaseMatch, code), code)
    end

    test "non-Map.fetch case with bare map pattern" do
      code = """
      case something do
        :error -> nil
        %{x: x} -> x
      end
      """

      confirm_fix(fix(FixMapFetchCaseMatch, code), code)
    end

    test "bare variable pattern (not a map)" do
      code = """
      case Map.fetch(state, key) do
        :error -> nil
        val -> val
      end
      """

      confirm_fix(fix(FixMapFetchCaseMatch, code), code)
    end

    test "tuple pattern (not a map)" do
      code = """
      case Map.fetch(state, key) do
        :error -> nil
        {:ok, val} -> val
      end
      """

      confirm_fix(fix(FixMapFetchCaseMatch, code), code)
    end

    test "catch-all variable clause — wrapping would steal its matches" do
      code = """
      case Map.fetch(m, k) do
        :error -> nil
        %{x: x} -> x
        other -> other
      end
      """

      confirm_fix(fix(FixMapFetchCaseMatch, code), code)
    end

    test "wildcard clause — wrapping would steal its matches" do
      code = """
      case Map.fetch(m, k) do
        %{x: x} -> x
        _ -> :default
      end
      """

      confirm_fix(fix(FixMapFetchCaseMatch, code), code)
    end

    test "an {:ok, _} clause alongside the bare map clause" do
      code = """
      case Map.fetch(m, k) do
        {:ok, val} -> val
        %{x: x} -> x
        :error -> nil
      end
      """

      confirm_fix(fix(FixMapFetchCaseMatch, code), code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIXABLE — extra clauses that provably cannot match {:ok, _}
  # ═══════════════════════════════════════════════════════════════════

  describe "wraps alongside clauses that cannot match a two-tuple" do
    test "non-:ok tagged two-tuple and atom clauses stay untouched" do
      input = """
      case Map.fetch(m, k) do
        :error -> nil
        {:error, reason} -> reason
        %{x: x} -> x
      end
      """

      expected = """
      case Map.fetch(m, k) do
        :error -> nil
        {:error, reason} -> reason
        {:ok, %{x: x}} -> x
      end
      """

      confirm_fix(fix(FixMapFetchCaseMatch, input), expected)
    end
  end
end
