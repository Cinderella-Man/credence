defmodule Credence.Pattern.NoRedundantCaseNilClauseFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoRedundantCaseNilClause

  defp fix(code), do: Credence.RuleHelpers.apply_rule_fix(NoRedundantCaseNilClause, code)

  test "removes nil clause and folds not is_nil into the guard" do
    input = """
    case Map.get(map, key) do
      nil ->
        default_action()

      prev when prev >= left ->
        use_value(prev)

      _prev ->
        default_action()
    end
    """

    expected = """
    case Map.get(map, key) do
      prev when not is_nil(prev) and prev >= left ->
        use_value(prev)

      _prev ->
        default_action()
    end
    """

    assert fix(input) == expected
  end

  test "single-line bodies" do
    input = """
    case x do
      nil -> 0
      n when n > 0 -> n
      _ -> 0
    end
    """

    expected = """
    case x do
      n when not is_nil(n) and n > 0 -> n
      _ -> 0
    end
    """

    assert fix(input) == expected
  end

  test "preserves multi-line bodies" do
    input = """
    case Map.get(m, k) do
      nil ->
        a = compute_default()
        {a, acc}

      val when val >= threshold ->
        a = transform(val)
        {a, Map.put(acc, k, val)}

      _val ->
        a = compute_default()
        {a, acc}
    end
    """

    expected = """
    case Map.get(m, k) do
      val when not is_nil(val) and val >= threshold ->
        a = transform(val)
        {a, Map.put(acc, k, val)}

      _val ->
        a = compute_default()
        {a, acc}
    end
    """

    assert fix(input) == expected
  end

  test "fixes piped case" do
    input = """
    map
    |> Map.get(key)
    |> case do
      nil -> :not_found
      v when v > 0 -> {:ok, v}
      _v -> :not_found
    end
    """

    expected = """
    map
    |> Map.get(key)
    |> case do
      v when not is_nil(v) and v > 0 -> {:ok, v}
      _v -> :not_found
    end
    """

    assert fix(input) == expected
  end

  test "wraps the original guard so precedence is preserved" do
    input = """
    case x do
      nil -> :a
      v when v > 0 or v < -5 -> :b
      _ -> :a
    end
    """

    expected = """
    case x do
      v when not is_nil(v) and (v > 0 or v < -5) -> :b
      _ -> :a
    end
    """

    assert fix(input) == expected
  end

  test "result is valid, compilable code" do
    input = """
    defmodule TestFix do
      def check(map, key, left) do
        case Map.get(map, key) do
          nil ->
            0

          prev when prev >= left ->
            prev - left

          _prev ->
            0
        end
      end
    end
    """

    expected = """
    defmodule TestFix do
      def check(map, key, left) do
        case Map.get(map, key) do
          prev when not is_nil(prev) and prev >= left ->
            prev - left

          _prev ->
            0
        end
      end
    end
    """

    output = fix(input)
    assert output == expected
    assert {:ok, _} = Code.string_to_quoted(output)
  end

  # ── no-op: shapes the rule must leave untouched ──────────────────────

  test "leaves non-redundant case (different bodies) unchanged" do
    input = """
    case x do
      nil -> :a
      val when val > 0 -> :b
      _ -> :c
    end
    """

    assert fix(input) == input
  end

  test "leaves non-bare-variable middle pattern unchanged" do
    # `not is_nil(r = {:ok, v})` would not compile (= is banned in guards),
    # so this shape must never be rewritten.
    input = """
    case x do
      nil -> :a
      r = {:ok, v} when v > 0 -> :a
      _ -> :a
    end
    """

    assert fix(input) == input
  end
end
