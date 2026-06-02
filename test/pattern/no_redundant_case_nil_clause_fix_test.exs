defmodule Credence.Pattern.NoRedundantCaseNilClauseFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoRedundantCaseNilClause

  defp fix(code) do
    ast = Sourceror.parse_string!(code)
    patches = NoRedundantCaseNilClause.fix_patches(ast, source: code)

    case patches do
      [] -> code
      _ -> Sourceror.patch_string(code, patches)
    end
  end

  test "removes nil clause and adds not is_nil guard" do
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

    output = fix(input)

    assert output =~ "not is_nil(prev) and prev >= left"
    refute output =~ "nil ->"
    assert output =~ "_prev ->"
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

    output = fix(input)

    assert output =~ "not is_nil(val) and val >= threshold"
    assert output =~ "transform(val)"
    refute output =~ "nil ->"
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

    output = fix(input)

    assert output =~ "not is_nil(v) and v > 0"
    refute output =~ "nil ->"
  end

  test "does not modify code without the pattern" do
    input = """
    case x do
      nil -> :a
      val when val > 0 -> :b
      _ -> :c
    end
    """

    output = fix(input)
    assert output == input
  end

  test "result compiles" do
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

    output = fix(input)
    assert {:ok, _} = Code.string_to_quoted(output)
  end
end
