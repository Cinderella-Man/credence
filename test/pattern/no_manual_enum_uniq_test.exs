defmodule Credence.Pattern.NoManualEnumUniqTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoManualEnumUniq.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoManualEnumUniq.fix(code, [])
  end

  describe "NoManualEnumUniq fixable?" do
    test "returns true" do
      assert Credence.Pattern.NoManualEnumUniq.fixable?() == true
    end
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

  describe "NoManualEnumUniq fix" do
    test "fixes basic manual Enum.uniq with MapSet first" do
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

      result = fix(code)
      assert result =~ "Enum.uniq(list)"
      refute result =~ "Enum.reduce"
      refute result =~ "MapSet"
    end

    test "fixes inverted tuple with unless" do
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

      result = fix(code)
      assert result =~ "Enum.uniq(list)"
      refute result =~ "Enum.reduce"
      refute result =~ "MapSet"
    end

    test "fixes piped Enum.reduce" do
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

      result = fix(code)
      assert result =~ "Enum.uniq()"
      assert result =~ "|>"
      refute result =~ "Enum.reduce"
      refute result =~ "MapSet"
    end

    test "fixes longer pipeline and strips orphaned Enum.reverse" do
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

      result = fix(code)
      assert result =~ "Enum.uniq"
      assert result =~ "Enum.map"
      refute result =~ "Enum.reverse"
      refute result =~ "Enum.reduce"
      refute result =~ "MapSet"
    end

    test "fixes negated condition with !" do
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

      result = fix(code)
      assert result =~ "Enum.uniq(list)"
      refute result =~ "Enum.reduce"
      refute result =~ "MapSet"
    end

    test "fixes negated condition with not" do
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

      result = fix(code)
      assert result =~ "Enum.uniq(list)"
      refute result =~ "Enum.reduce"
      refute result =~ "MapSet"
    end

    test "fixes case-based dedup" do
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

      result = fix(code)
      assert result =~ "Enum.uniq(list)"
      refute result =~ "Enum.reduce"
      refute result =~ "MapSet"
    end

    test "fixes inside Enum.map" do
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

      result = fix(code)
      assert result =~ "Enum.uniq"
      refute result =~ "Enum.reduce"
      refute result =~ "MapSet"
    end

    test "fixes multiple occurrences in same source" do
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

      result = fix(code)
      assert result =~ "Enum.uniq"
      refute result =~ "Enum.reduce"
      refute result =~ "MapSet"
    end

    test "preserves list argument expression" do
      code = """
      defmodule Example do
        def run(items, extra) do
          Enum.reduce(items ++ extra, {MapSet.new(), []}, fn item, {seen, acc} ->
            if MapSet.member?(seen, item) do
              {seen, acc}
            else
              {MapSet.put(seen, item), [item | acc]}
            end
          end)
        end
      end
      """

      result = fix(code)
      assert result =~ "Enum.uniq"
      assert result =~ "++"
      refute result =~ "Enum.reduce"
      refute result =~ "MapSet"
    end

    test "preserves surrounding code" do
      code = """
      defmodule Example do
        def run(list) do
          before()
          result = Enum.reduce(list, {MapSet.new(), []}, fn item, {seen, acc} ->
            if MapSet.member?(seen, item) do
              {seen, acc}
            else
              {MapSet.put(seen, item), [item | acc]}
            end
          end)
          finish(result)
        end
      end
      """

      result = fix(code)
      assert result =~ "before()"
      assert result =~ "finish("
      assert result =~ "Enum.uniq(list)"
      refute result =~ "Enum.reduce"
    end

    test "does not modify The \"Unique Errors\" Pattern" do
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

      result = fix(code)
      assert result =~ "Enum.reduce"
      assert result =~ "MapSet"
    end

    test "does not modify The \"Two-Channel\" Filter" do
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

      result = fix(code)
      assert result =~ "Enum.reduce"
      assert result =~ "MapSet"
    end

    test "does not modify Cross-Referencing Pattern" do
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

      result = fix(code)
      assert result =~ "Enum.reduce"
      assert result =~ "MapSet"
    end

    test "does not modify normal Enum.reduce" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, 0, fn item, acc ->
            item + acc
          end)
        end
      end
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
    end

    test "does not modify MapSet as pure accumulator" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.reduce(list, MapSet.new(), fn item, acc ->
            MapSet.put(acc, item)
          end)
        end
      end
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      assert result =~ "MapSet"
    end

    test "does not modify valid Enum.uniq" do
      code = """
      defmodule Example do
        def run(list), do: Enum.uniq(list)
      end
      """

      result = fix(code)
      assert result =~ "Enum.uniq"
      refute result =~ "Enum.reduce"
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Orphaned pipeline stripping (production bug reproduction)
  # ═══════════════════════════════════════════════════════════════

  describe "fix strips orphaned |> elem(N) |> Enum.reverse()" do
    test "strips elem(0) and Enum.reverse from piped reduce with {list, MapSet} order" do
      code = """
      defmodule UniqueChars do
        def unique_char_in_order(input_string) do
          String.graphemes(input_string)
          |> Enum.reduce({[], MapSet.new()}, fn char, {acc_list, acc_set} ->
            if MapSet.member?(acc_set, char) do
              {acc_list, acc_set}
            else
              {[char | acc_list], MapSet.put(acc_set, char)}
            end
          end)
          |> elem(0)
          |> Enum.reverse()
        end
      end
      """

      result = fix(code)
      assert result =~ "Enum.uniq()"
      assert result =~ "String.graphemes(input_string)"
      refute result =~ "Enum.reduce"
      refute result =~ "MapSet"
      refute result =~ "elem(0)"
      refute result =~ "Enum.reverse"
    end

    test "strips elem(1) and Enum.reverse from {MapSet, list} order" do
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
          |> elem(1)
          |> Enum.reverse()
        end
      end
      """

      result = fix(code)
      assert result =~ "Enum.uniq(list)"
      refute result =~ "elem(1)"
      refute result =~ "Enum.reverse"
      refute result =~ "Enum.reduce"
    end

    test "strips only elem(0) when no Enum.reverse follows" do
      code = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.reduce({[], MapSet.new()}, fn char, {acc_list, acc_set} ->
            if MapSet.member?(acc_set, char) do
              {acc_list, acc_set}
            else
              {[char | acc_list], MapSet.put(acc_set, char)}
            end
          end)
          |> elem(0)
        end
      end
      """

      result = fix(code)
      assert result =~ "Enum.uniq()"
      refute result =~ "elem(0)"
      refute result =~ "Enum.reduce"
    end

    test "preserves pipeline steps after the orphans are stripped" do
      code = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.reduce({[], MapSet.new()}, fn char, {acc_list, acc_set} ->
            if MapSet.member?(acc_set, char) do
              {acc_list, acc_set}
            else
              {[char | acc_list], MapSet.put(acc_set, char)}
            end
          end)
          |> elem(0)
          |> Enum.reverse()
          |> Enum.take(5)
        end
      end
      """

      result = fix(code)
      assert result =~ "Enum.uniq()"
      assert result =~ "Enum.take(5)"
      refute result =~ "elem(0)"
      refute result =~ "Enum.reverse"
      refute result =~ "Enum.reduce"
    end

    test "does not strip elem/reverse from pre-existing Enum.uniq" do
      code = """
      defmodule Example do
        def run(list) do
          list |> Enum.uniq() |> Enum.reverse()
        end
      end
      """

      result = fix(code)
      # Pre-existing Enum.uniq should NOT have reverse stripped
      assert result =~ "Enum.uniq()"
      assert result =~ "Enum.reverse"
    end

    test "output compiles without errors" do
      code = """
      defmodule UniqueChars do
        def unique_char_in_order(input_string) do
          String.graphemes(input_string)
          |> Enum.reduce({[], MapSet.new()}, fn char, {acc_list, acc_set} ->
            if MapSet.member?(acc_set, char) do
              {acc_list, acc_set}
            else
              {[char | acc_list], MapSet.put(acc_set, char)}
            end
          end)
          |> elem(0)
          |> Enum.reverse()
        end
      end
      """

      result = fix(code)
      assert {:ok, _ast} = Code.string_to_quoted(result)
    end

    test "round-trip: fixed code has zero issues" do
      code = """
      defmodule UniqueChars do
        def unique_char_in_order(input_string) do
          String.graphemes(input_string)
          |> Enum.reduce({[], MapSet.new()}, fn char, {acc_list, acc_set} ->
            if MapSet.member?(acc_set, char) do
              {acc_list, acc_set}
            else
              {[char | acc_list], MapSet.put(acc_set, char)}
            end
          end)
          |> elem(0)
          |> Enum.reverse()
        end
      end
      """

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      assert [] == Credence.Pattern.NoManualEnumUniq.check(ast, [])
    end
  end
end
