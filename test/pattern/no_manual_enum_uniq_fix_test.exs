defmodule Credence.Pattern.NoManualEnumUniqFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoManualEnumUniq

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoManualEnumUniq.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoManualEnumUniq, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "NoManualEnumUniq fix" do
    test "fixes basic manual Enum.uniq with MapSet first" do
      input = """
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

      expected = """
      defmodule Example do
        def run(list) do
          Enum.uniq(list)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes inverted tuple with unless" do
      input = """
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

      expected = """
      defmodule Example do
        def run(list) do
          Enum.uniq(list)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes piped Enum.reduce" do
      input = """
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

      expected = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.uniq()
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes longer pipeline and strips orphaned Enum.reverse" do
      input = """
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

      expected = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.map(&String.upcase/1)
          |> Enum.uniq()
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes negated condition with !" do
      input = """
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

      expected = """
      defmodule Example do
        def run(list) do
          Enum.uniq(list)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes negated condition with not" do
      input = """
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

      expected = """
      defmodule Example do
        def run(list) do
          Enum.uniq(list)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes case-based dedup" do
      input = """
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

      expected = """
      defmodule Example do
        def run(list) do
          Enum.uniq(list)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes inside Enum.map" do
      input = """
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

      expected = """
      Enum.map(list, fn outer ->
        Enum.uniq(outer)
      end)
      """

      assert fix(input) == expected
    end

    test "fixes multiple occurrences in same source" do
      input = """
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

      expected = """
      defmodule Example do
        def run1(list) do
          Enum.uniq(list)
        end

        def run2(list) do
          Enum.uniq(list)
        end
      end
      """

      assert fix(input) == expected
    end

    test "preserves list argument expression" do
      input = """
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

      expected = """
      defmodule Example do
        def run(items, extra) do
          Enum.uniq(items ++ extra)
        end
      end
      """

      assert fix(input) == expected
    end

    test "preserves surrounding code" do
      input = """
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

      expected = """
      defmodule Example do
        def run(list) do
          before()
          result = Enum.uniq(list)
          finish(result)
        end
      end
      """

      assert fix(input) == expected
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

      assert fix(code) == code
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

      assert fix(code) == code
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

      assert fix(code) == code
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

      assert fix(code) == code
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

      assert fix(code) == code
    end

    test "does not modify valid Enum.uniq" do
      code = """
      defmodule Example do
        def run(list), do: Enum.uniq(list)
      end
      """

      assert fix(code) == code
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Orphaned pipeline stripping (production bug reproduction)
  # ═══════════════════════════════════════════════════════════════

  describe "fix strips orphaned |> elem(N) |> Enum.reverse()" do
    test "strips elem(0) and Enum.reverse from piped reduce with {list, MapSet} order" do
      input = """
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

      expected = """
      defmodule UniqueChars do
        def unique_char_in_order(input_string) do
          String.graphemes(input_string)
          |> Enum.uniq()
        end
      end
      """

      assert fix(input) == expected
    end

    test "strips elem(1) and Enum.reverse from {MapSet, list} order" do
      input = """
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

      expected = """
      defmodule Example do
        def run(list) do
          Enum.uniq(list)
        end
      end
      """

      assert fix(input) == expected
    end

    test "strips only elem(0) when no Enum.reverse follows" do
      input = """
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

      expected = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.uniq()
        end
      end
      """

      assert fix(input) == expected
    end

    test "preserves pipeline steps after the orphans are stripped" do
      input = """
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

      expected = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.uniq()
          |> Enum.take(5)
        end
      end
      """

      assert fix(input) == expected
    end

    test "does not strip elem/reverse from pre-existing Enum.uniq" do
      code = """
      defmodule Example do
        def run(list) do
          list |> Enum.uniq() |> Enum.reverse()
        end
      end
      """

      assert fix(code) == code
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

      assert check(fix(code)) == []
    end
  end
end
