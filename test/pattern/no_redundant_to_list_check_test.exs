defmodule Credence.Pattern.NoRedundantToListCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantToList

  describe "fires" do
    test "Enum.to_list(x) |> MapSet.new()" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.to_list(items) |> MapSet.new()
        end
      end
      """

      issues = check(NoRedundantToList, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_redundant_to_list
    end

    test "x |> Enum.to_list() |> MapSet.new()" do
      code = """
      defmodule Example do
        def run(items) do
          items |> Enum.to_list() |> MapSet.new()
        end
      end
      """

      assert length(check(NoRedundantToList, code)) == 1
    end

    test "MapSet.new(Enum.to_list(x))" do
      code = """
      defmodule Example do
        def run(items) do
          MapSet.new(Enum.to_list(items))
        end
      end
      """

      assert length(check(NoRedundantToList, code)) == 1
    end

    test "Enum.to_list(x) |> Map.new()" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.to_list(items) |> Map.new()
        end
      end
      """

      assert length(check(NoRedundantToList, code)) == 1
    end

    test "non-pipe /2 form keeps fix safe, so it still fires" do
      code = """
      defmodule Example do
        def run(items) do
          MapSet.new(Enum.to_list(items), fn x -> x + 1 end)
        end
      end
      """

      assert length(check(NoRedundantToList, code)) == 1
    end

    test "multiple occurrences in same module" do
      code = """
      defmodule Example do
        def run(a, b) do
          first = Enum.to_list(a) |> MapSet.new()
          second = Enum.to_list(b) |> MapSet.new()
          {first, second}
        end
      end
      """

      assert length(check(NoRedundantToList, code)) == 2
    end
  end

  describe "no issue" do
    test "MapSet.new(items)" do
      code = """
      defmodule Example do
        def run(items) do
          MapSet.new(items)
        end
      end
      """

      assert check(NoRedundantToList, code) == []
    end

    test "Enum.to_list used alone" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.to_list(items)
        end
      end
      """

      assert check(NoRedundantToList, code) == []
    end

    test "Enum.to_list piped to arbitrary function" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.to_list(items) |> IO.inspect()
        end
      end
      """

      assert check(NoRedundantToList, code) == []
    end

    # Deliberately NOT fired: the pipe /2 form would drop the extra arg
    # (the piped list becomes arg 1, the transform arg 2). Removing
    # Enum.to_list here without re-threading the transform changes behaviour,
    # so the rule is narrowed to the no-extra-arg pipe shape only.
    test "Enum.to_list(x) |> MapSet.new(fun) — unsafe pipe /2, skipped" do
      code = """
      defmodule Example do
        def run(items) do
          Enum.to_list(items) |> MapSet.new(fn x -> x + 1 end)
        end
      end
      """

      assert check(NoRedundantToList, code) == []
    end

    test "Enum.to_list(x) |> Map.new(fun) — unsafe pipe /2, skipped" do
      code = """
      defmodule Example do
        def run(pairs) do
          Enum.to_list(pairs) |> Map.new(fn {k, v} -> {k, v + 1} end)
        end
      end
      """

      assert check(NoRedundantToList, code) == []
    end

    # Only `Map.new`/`MapSet.new` accept an arbitrary enumerable. `Map.take`'s
    # keys argument is list-shaped — stripping `Enum.to_list` would pass a
    # non-list enumerable (e.g. a MapSet) and trigger a deprecation, so a
    # non-`.new` function must not be flagged.
    test "does not flag Enum.to_list feeding a non-.new function (Map.take)" do
      code = """
      defmodule Example do
        def run(record, resource) do
          record |> Map.take(Enum.to_list(attribute_names(resource)))
        end
      end
      """

      assert check(NoRedundantToList, code) == []
    end
  end
end
