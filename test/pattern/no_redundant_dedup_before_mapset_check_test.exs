defmodule Credence.Pattern.NoRedundantDedupBeforeMapsetCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantDedupBeforeMapset

  describe "fires on the safe core (dedup/uniq directly before MapSet.new)" do
    test "Enum.dedup(x) |> MapSet.new()" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.dedup(items) |> MapSet.new()
        end
      end
      """

      issues = check(NoRedundantDedupBeforeMapset, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_redundant_dedup_before_mapset
    end

    test "x |> Enum.dedup() |> MapSet.new()" do
      code = """
      defmodule Example do
        def run(items) do
          items |> Enum.dedup() |> MapSet.new()
        end
      end
      """

      assert length(check(NoRedundantDedupBeforeMapset, code)) == 1
    end

    test "MapSet.new(Enum.dedup(x))" do
      code = """
      defmodule Example do
        def run(items) do
          MapSet.new(Enum.dedup(items))
        end
      end
      """

      assert length(check(NoRedundantDedupBeforeMapset, code)) == 1
    end

    test "Enum.uniq(x) |> MapSet.new()" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.uniq(items) |> MapSet.new()
        end
      end
      """

      assert length(check(NoRedundantDedupBeforeMapset, code)) == 1
    end

    test "MapSet.new(Enum.uniq(x))" do
      code = """
      defmodule Example do
        def run(items) do
          MapSet.new(Enum.uniq(items))
        end
      end
      """

      assert length(check(NoRedundantDedupBeforeMapset, code)) == 1
    end

    test "multiple occurrences in same module" do
      code = """
      defmodule Example do
        def run(a, b) do
          first = Enum.dedup(a) |> MapSet.new()
          second = Enum.dedup(b) |> MapSet.new()
          {first, second}
        end
      end
      """

      assert length(check(NoRedundantDedupBeforeMapset, code)) == 2
    end
  end

  describe "does not fire" do
    test "MapSet.new/2 transform forms" do
      pipe_code = "Enum.uniq(items) |> MapSet.new(transform)"
      direct_code = "MapSet.new(Enum.uniq(items), transform)"

      assert check(NoRedundantDedupBeforeMapset, pipe_code) == []
      assert check(NoRedundantDedupBeforeMapset, direct_code) == []
    end

    test "MapSet.new(items) with no dedup" do
      code = """
      defmodule Example do
        def run(items) do
          MapSet.new(items)
        end
      end
      """

      assert check(NoRedundantDedupBeforeMapset, code) == []
    end

    test "Enum.dedup used alone" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.dedup(items)
        end
      end
      """

      assert check(NoRedundantDedupBeforeMapset, code) == []
    end

    test "Enum.dedup piped to a non-MapSet function" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.dedup(items) |> Enum.count()
        end
      end
      """

      assert check(NoRedundantDedupBeforeMapset, code) == []
    end

    test "Enum.sort alone piped to MapSet.new" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.sort(items) |> MapSet.new()
        end
      end
      """

      assert check(NoRedundantDedupBeforeMapset, code) == []
    end
  end

  # Deliberately NOT flagged: a sort/sort_by intermediate between dedup/uniq
  # and MapSet.new. Dropping it is not behaviour-preserving — the comparator
  # or key function can have side effects or raise on some element, so
  # removing the sort can change the answer (turn a raise into a MapSet).
  describe "no issue: sort/sort_by intermediate (unsafe to drop)" do
    test "Enum.uniq(x) |> Enum.sort() |> MapSet.new()" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.uniq(items) |> Enum.sort() |> MapSet.new()
        end
      end
      """

      assert check(NoRedundantDedupBeforeMapset, code) == []
    end

    test "items |> Enum.uniq() |> Enum.sort() |> MapSet.new()" do
      code = """
      defmodule Example do
        def run(items) do
          items |> Enum.uniq() |> Enum.sort() |> MapSet.new()
        end
      end
      """

      assert check(NoRedundantDedupBeforeMapset, code) == []
    end

    test "Enum.dedup(x) |> Enum.sort() |> MapSet.new()" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.dedup(items) |> Enum.sort() |> MapSet.new()
        end
      end
      """

      assert check(NoRedundantDedupBeforeMapset, code) == []
    end

    test "items |> Enum.dedup() |> Enum.sort_by(& &1) |> MapSet.new()" do
      code = """
      defmodule Example do
        def run(items) do
          items |> Enum.dedup() |> Enum.sort_by(& &1) |> MapSet.new()
        end
      end
      """

      assert check(NoRedundantDedupBeforeMapset, code) == []
    end
  end
end
