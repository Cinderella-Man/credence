defmodule Credence.Pattern.NoEnumCountForLengthCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoEnumCountForLength

  describe "flags Enum.count/1 over a known list" do
    test "in a pipeline" do
      [issue] =
        check(NoEnumCountForLength, """
        defmodule Bad do
          def count_items(list) do
            list
            |> Enum.filter(&(&1 > 0))
            |> Enum.count()
          end
        end
        """)

      assert issue.message =~ "Enum.count/1"
    end

    test "with a direct expression" do
      [issue] =
        check(NoEnumCountForLength, """
        defmodule Bad do
          def grapheme_count(str) do
            Enum.count(String.graphemes(str))
          end
        end
        """)

      assert issue.message =~ "length/1"
    end

    test "in a guard-like comparison" do
      [issue] =
        check(NoEnumCountForLength, """
        defmodule Bad do
          def check(list, min_size) do
            if Enum.count(String.graphemes(list)) >= min_size, do: :ok, else: :error
          end
        end
        """)

      assert issue.rule == :no_enum_count_for_length
    end

    test "multiple calls" do
      issues =
        check(NoEnumCountForLength, """
        defmodule Bad do
          def compare(a, b) do
            Enum.count(String.graphemes(a)) == Enum.count(String.graphemes(b))
          end
        end
        """)

      assert length(issues) == 2
    end

    test "in an assignment" do
      [issue] =
        check(NoEnumCountForLength, """
        defmodule Bad do
          def process(items) do
            n = Enum.count(String.graphemes(items))
            Enum.reduce(0..(n - 1), 0, fn i, acc -> acc + i end)
          end
        end
        """)

      assert issue.message =~ "length/1"
    end
  end

  describe "does not flag" do
    test "Enum.count on a bare variable (type unknown — could be a range/map/stream)" do
      assert clean?(NoEnumCountForLength, """
             defmodule Good do
               def process(input) do
                 chars = String.graphemes(input)
                 total = Enum.count(chars)
                 {chars, total}
               end
             end
             """)
    end

    test "Enum.count/2 with a predicate" do
      assert clean?(NoEnumCountForLength, """
             defmodule Good do
               def count_positives(list) do
                 Enum.count(list, &(&1 > 0))
               end
             end
             """)
    end

    test "Enum.count/2 with a predicate in a pipeline" do
      assert clean?(NoEnumCountForLength, """
             defmodule Good do
               def count_big(list) do
                 list |> Enum.count(&(&1 > 100))
               end
             end
             """)
    end

    test "length/1 (already correct)" do
      assert clean?(NoEnumCountForLength, """
             defmodule Good do
               def size(list), do: length(list)
             end
             """)
    end

    test "map_size/1" do
      assert clean?(NoEnumCountForLength, """
             defmodule Good do
               def size(map), do: map_size(map)
             end
             """)
    end

    test "MapSet.size/1" do
      assert clean?(NoEnumCountForLength, """
             defmodule Good do
               def size(set), do: MapSet.size(set)
             end
             """)
    end

    test "non-Enum count functions" do
      assert clean?(NoEnumCountForLength, """
             defmodule Good do
               def count(list), do: MyModule.count(list)
             end
             """)
    end
  end
end
