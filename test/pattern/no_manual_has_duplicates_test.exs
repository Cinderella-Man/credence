defmodule Credence.Pattern.NoManualHasDuplicatesTest do
  use ExUnit.Case

  alias Credence.Pattern.NoManualHasDuplicates

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoManualHasDuplicates.check(ast, [])
  end

  describe "NoManualHasDuplicates check" do
    test "flags manual recursive duplicate detection with Map.get" do
      code = """
      defmodule Example do
        def has_duplicates(elements) do
          do_has_duplicates(elements, %{})
        end

        defp do_has_duplicates([], _seen), do: false

        defp do_has_duplicates([head | tail], seen) do
          if Map.get(seen, head) do
            true
          else
            do_has_duplicates(tail, Map.put(seen, head, true))
          end
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags manual recursive duplicate detection with MapSet.member?" do
      code = """
      defmodule Example do
        def has_dupes(list), do: check(list, MapSet.new())

        defp check([], _seen), do: false
        defp check([head | tail], seen) do
          if MapSet.member?(seen, head) do
            true
          else
            check(tail, MapSet.put(seen, head))
          end
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags manual recursive duplicate detection with Map.has_key?" do
      code = """
      defmodule Example do
        defp find_dup([], _seen), do: false
        defp find_dup([h | t], seen) do
          if Map.has_key?(seen, h) do
            true
          else
            find_dup(t, Map.put(seen, h, true))
          end
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "does not flag Enum.uniq-based duplicate check" do
      code = """
      defmodule Example do
        def has_duplicates(list), do: Enum.uniq(list) != list
      end
      """

      assert check(code) == []
    end

    test "does not flag recursive function without set accumulator pattern" do
      code = """
      defmodule Example do
        defp find_match([], _opts), do: false
        defp find_match([head | tail], opts) do
          if matches?(head, opts) do
            true
          else
            find_match(tail, opts)
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when base case does not return false" do
      code = """
      defmodule Example do
        defp do_check([], acc), do: {:ok, acc}
        defp do_check([head | tail], seen) do
          if Map.get(seen, head) do
            true
          else
            do_check(tail, Map.put(seen, head, true))
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when true branch does something other than return true" do
      code = """
      defmodule Example do
        defp do_check([], _seen), do: false
        defp do_check([head | tail], seen) do
          if Map.get(seen, head) do
            head
          else
            do_check(tail, Map.put(seen, head, true))
          end
        end
      end
      """

      assert check(code) == []
    end
  end
end
