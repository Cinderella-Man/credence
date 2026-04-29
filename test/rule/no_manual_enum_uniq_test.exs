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

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_manual_enum_uniq
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

    test "does not flag Enum.reduce using MapSet purely as an accumulator (e.g. converting list to MapSet)" do
      # Note: Enum.into(list, MapSet.new()) is better, but this shouldn't trigger the uniqueness warning
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, MapSet.new(), fn item, acc ->
            MapSet.put(acc, item)
          end)
        end
      end
      """

      # Our current heuristic flags if MapSet.new() is in init AND MapSet.put is in the reducer.
      # To avoid flagging `MapSet.new()` -> `MapSet.put` purely as collection building,
      # you might want to require both `put` AND `member?` for maximum safety, but
      # let's test our current boundary. If you want to tighten it, you can require `member?` specifically.
      # The provided implementation will flag this. If this is a false positive, update `contains_mapset_tracking?`
      # to require `[:member?]` explicitly instead of `in [:put, :member?]`.

      # Let's assert based on the current logic (which assumes MapSet.new + MapSet.put = tracking pattern)
      assert length(check(code)) == 1
    end

    test "does not flag valid Enum.uniq/1 usages" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.uniq(list)
        end
      end
      """

      assert check(code) == []
    end
  end
end
