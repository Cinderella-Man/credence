defmodule Credence.Pattern.NoManualEnumUniqCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoManualEnumUniq

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoManualEnumUniq.check(ast, [])
  end

  describe "NoManualEnumUniq check" do
    test "flags manual Enum.uniq/1 using MapSet and reduce" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, {MapSet.new(), []}, fn item, {seen, acc} ->
            if MapSet.member?(seen, item) do
              {seen, acc}
            else
              {MapSet.put(seen, item), [item | acc]}
            end
          end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags even if variable names are different or logic is inverted" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, {[], MapSet.new()}, fn x, {results, tracked} ->
            unless MapSet.member?(tracked, x) do
              {[x | results], MapSet.put(tracked, x)}
            else
              {results, tracked}
            end
          end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags piped Enum.reduce" do
      code = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.reduce({MapSet.new(), []}, fn item, {seen, acc} ->
            if MapSet.member?(seen, item) do
              {seen, acc}
            else
              {MapSet.put(seen, item), [item | acc]}
            end
          end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags piped Enum.reduce in longer pipeline" do
      code = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.map(&String.upcase/1)
          |> Enum.reduce({MapSet.new(), []}, fn item, {seen, acc} ->
            if MapSet.member?(seen, item) do
              {seen, acc}
            else
              {MapSet.put(seen, item), [item | acc]}
            end
          end)
          |> Enum.reverse()
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags negated condition with !" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, {MapSet.new(), []}, fn item, {seen, acc} ->
            if !MapSet.member?(seen, item) do
              {MapSet.put(seen, item), [item | acc]}
            else
              {seen, acc}
            end
          end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags negated condition with not" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, {MapSet.new(), []}, fn item, {seen, acc} ->
            if not MapSet.member?(seen, item) do
              {MapSet.put(seen, item), [item | acc]}
            else
              {seen, acc}
            end
          end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags case-based dedup" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, {MapSet.new(), []}, fn item, {seen, acc} ->
            case MapSet.member?(seen, item) do
              true -> {seen, acc}
              false -> {MapSet.put(seen, item), [item | acc]}
            end
          end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags inside Enum.map" do
      code = """
      Enum.map(list, fn outer ->
        Enum.reduce(outer, {MapSet.new(), []}, fn item, {seen, acc} ->
          if MapSet.member?(seen, item) do
            {seen, acc}
          else
            {MapSet.put(seen, item), [item | acc]}
          end
        end)
      end)
      """

      assert length(check(code)) == 1
    end

    test "flags multiple occurrences in same source" do
      code = """
      defmodule Example do
        def run1(list) do
          Enum.reduce(list, {MapSet.new(), []}, fn item, {seen, acc} ->
            if MapSet.member?(seen, item) do
              {seen, acc}
            else
              {MapSet.put(seen, item), [item | acc]}
            end
          end)
        end

        def run2(list) do
          Enum.reduce(list, {[], MapSet.new()}, fn x, {results, tracked} ->
            unless MapSet.member?(tracked, x) do
              {[x | results], MapSet.put(tracked, x)}
            else
              {results, tracked}
            end
          end)
        end
      end
      """

      assert length(check(code)) == 2
    end

    test "does not flag The \"Unique Errors\" Pattern" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, {MapSet.new(), []}, fn item, {error_tags, results} ->
            new_tags = MapSet.put(error_tags, item.type)

            if MapSet.member?(error_tags, "CRITICAL") do
              {new_tags, [item | results]}
            else
              {new_tags, results}
            end
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag The \"Two-Channel\" Filter" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, {MapSet.new(), []}, fn item, {categories, values} ->
            if String.starts_with?(item, "cat:") do
              {MapSet.put(categories, item), values}
            else
              {categories, [item | values]}
            end
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Cross-Referencing (The \"Foreign Key\" Check)" do
      code = """
      defmodule Example do
        def run(list_a, list_b_set) do
          Enum.reduce(list_a, {MapSet.new(), []}, fn item, {matched_from_b, acc} ->
            if MapSet.member?(list_b_set, item) do
              {MapSet.put(matched_from_b, item), [item | acc]}
            else
              {matched_from_b, acc}
            end
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag normal Enum.reduce summing numbers" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, 0, fn item, acc ->
            item + acc
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.reduce using MapSet purely as an accumulator" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, MapSet.new(), fn item, acc ->
            MapSet.put(acc, item)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag valid Enum.uniq/1 usages" do
      code = "Enum.uniq(list)"
      assert check(code) == []
    end
  end
end
