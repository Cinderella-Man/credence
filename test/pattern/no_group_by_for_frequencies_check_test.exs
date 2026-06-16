defmodule Credence.Pattern.NoGroupByForFrequenciesCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoGroupByForFrequencies

  describe "flags the manual frequency-by-key pattern" do
    test "piped group_by/2 |> Map.new with length" do
      code = """
      defmodule M do
        def freq(words) do
          words
          |> Enum.group_by(&String.downcase/1)
          |> Map.new(fn {key, group} -> {key, length(group)} end)
        end
      end
      """

      issues = check(NoGroupByForFrequencies, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_group_by_for_frequencies
      assert hd(issues).message =~ "Enum.frequencies_by"
    end

    test "direct Map.new(Enum.group_by/2, ...) form" do
      code = """
      defmodule M do
        def freq(words) do
          Map.new(Enum.group_by(words, &String.downcase/1), fn {key, group} -> {key, length(group)} end)
        end
      end
      """

      issues = check(NoGroupByForFrequencies, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_group_by_for_frequencies
    end

    test "Enum.count variant" do
      code = """
      defmodule M do
        def freq(list) do
          list
          |> Enum.group_by(& &1)
          |> Map.new(fn {k, g} -> {k, Enum.count(g)} end)
        end
      end
      """

      assert length(check(NoGroupByForFrequencies, code)) == 1
    end

    test "Kernel.length remote-call variant" do
      code = """
      defmodule M do
        def freq(list) do
          list
          |> Enum.group_by(fn x -> x end)
          |> Map.new(fn {key, group} -> {key, Kernel.length(group)} end)
        end
      end
      """

      assert length(check(NoGroupByForFrequencies, code)) == 1
    end

    test "extra leading pipe steps before group_by" do
      code = """
      defmodule M do
        def freq(data) do
          data
          |> Enum.map(fn x -> x.name end)
          |> Enum.group_by(&String.downcase/1)
          |> Map.new(fn {key, group} -> {key, length(group)} end)
        end
      end
      """

      assert length(check(NoGroupByForFrequencies, code)) == 1
    end

    test "reports exactly once when a trailing pipe step follows Map.new" do
      code = """
      defmodule M do
        def freq(words) do
          words
          |> Enum.group_by(&String.downcase/1)
          |> Map.new(fn {key, group} -> {key, length(group)} end)
          |> Enum.sort()
        end
      end
      """

      assert length(check(NoGroupByForFrequencies, code)) == 1
    end
  end

  describe "does not flag — out of scope" do
    test "non-length transform" do
      code = """
      defmodule M do
        def first_by_key(list) do
          list
          |> Enum.group_by(fn x -> x.key end)
          |> Map.new(fn {k, items} -> {k, hd(items)} end)
        end
      end
      """

      assert check(NoGroupByForFrequencies, code) == []
    end

    test "arithmetic on length" do
      code = """
      defmodule M do
        def adjusted(list) do
          list
          |> Enum.group_by(& &1)
          |> Map.new(fn {k, g} -> {k, length(g) + 1} end)
        end
      end
      """

      assert check(NoGroupByForFrequencies, code) == []
    end

    test "Map.new on a non-group_by source" do
      code = """
      defmodule M do
        def to_map(list) do
          Map.new(list, fn x -> {x.key, x.value} end)
        end
      end
      """

      assert check(NoGroupByForFrequencies, code) == []
    end

    test "group_by alone, without Map.new" do
      code = """
      defmodule M do
        def grouped(list) do
          Enum.group_by(list, &String.downcase/1)
        end
      end
      """

      assert check(NoGroupByForFrequencies, code) == []
    end
  end

  describe "does not flag — deliberately excluded for safety" do
    # A piped `Enum.group_by/3` carries a value_fun. `frequencies_by/2` never
    # calls it, so dropping a side-effecting or raising value_fun would change
    # the answer. `length(group)` is the element COUNT regardless of value_fun,
    # so the result map would match — but only when value_fun is pure and total.
    # Under :strict we cannot assume that, so this is left untouched.
    test "piped group_by/3 with a value_fun" do
      code = """
      defmodule M do
        def freq(list) do
          list
          |> Enum.group_by(fn x -> x.key end, fn x -> x.value end)
          |> Map.new(fn {k, g} -> {k, length(g)} end)
        end
      end
      """

      assert check(NoGroupByForFrequencies, code) == []
    end

    test "direct Map.new(Enum.group_by/3, ...) with a value_fun" do
      code = """
      defmodule M do
        def freq(list) do
          Map.new(Enum.group_by(list, fn x -> x.key end, fn x -> x.value end), fn {k, g} -> {k, length(g)} end)
        end
      end
      """

      assert check(NoGroupByForFrequencies, code) == []
    end

    # Head-position group_by/3 carries a value_fun, which frequencies_by/2 never
    # calls — dropping a side-effecting value_fun would change the answer. (The
    # group_by/2 head-position form IS now handled — see the fix tests.)
    test "head-position group_by/3 with a value_fun" do
      code = """
      defmodule M do
        def freq(words) do
          Enum.group_by(words, &String.downcase/1, fn x -> x.id end)
          |> Map.new(fn {key, group} -> {key, length(group)} end)
        end
      end
      """

      assert check(NoGroupByForFrequencies, code) == []
    end
  end
end
