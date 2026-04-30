defmodule Credence.Rule.NoManualEnumUniqTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoManualEnumUniq.check(ast, [])
  end

  describe "NoManualEnumUniq" do
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

    test "does not flag The \"Unique Errors\" Pattern" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, {MapSet.new(), []}, fn item, {error_tags, results} ->
            # We collect EVERY item into results (no deduplication)
            # But we also record the 'type' of the item in a set for a summary report
            new_tags = MapSet.put(error_tags, item.type)

            if MapSet.member?(error_tags, "CRITICAL") do
              # Logic is driven by a specific tag presence, not 'item' uniqueness
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
              # We only put into the MapSet here
              {MapSet.put(categories, item), values}
            else
              # We only put into the List here
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
        def run(list) do
          # list_b_set was passed in from outside
          Enum.reduce(list_a, {MapSet.new(), []}, fn item, {matched_from_b, acc} ->
            if MapSet.member?(list_b_set, item) do
              # We track which items from B were actually hit
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
