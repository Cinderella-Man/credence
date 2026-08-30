defmodule Credence.Pattern.NoGroupByForFrequenciesFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoGroupByForFrequencies
  alias Credence.RuleHelpers

  describe "rewrites to Enum.frequencies_by/2" do
    test "piped group_by/2 |> Map.new(length)" do
      code = """
      words
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {key, group} -> {key, length(group)} end)
      """

      expected = "Enum.frequencies_by(words, &String.downcase/1)"

      confirm_fix(fix(NoGroupByForFrequencies, code), expected)
    end

    test "direct Map.new(Enum.group_by/2, ...)" do
      code =
        "Map.new(Enum.group_by(words, &String.downcase/1), fn {key, group} -> {key, length(group)} end)"

      expected = "Enum.frequencies_by(words, &String.downcase/1)"

      confirm_fix(fix(NoGroupByForFrequencies, code), expected)
    end

    test "Enum.count variant" do
      code = """
      list
      |> Enum.group_by(& &1)
      |> Map.new(fn {k, g} -> {k, Enum.count(g)} end)
      """

      # identity key_fn → the cleaner `Enum.frequencies/1`
      expected = "Enum.frequencies(list)"

      confirm_fix(fix(NoGroupByForFrequencies, code), expected)
    end

    test "Kernel.length variant" do
      code = """
      list
      |> Enum.group_by(fn x -> x end)
      |> Map.new(fn {key, group} -> {key, Kernel.length(group)} end)
      """

      # identity key_fn (`fn x -> x end`) → the cleaner `Enum.frequencies/1`
      expected = "Enum.frequencies(list)"

      confirm_fix(fix(NoGroupByForFrequencies, code), expected)
    end

    test "head-position group_by/2 piped to Map.new (non-identity) → frequencies_by" do
      confirm_fix(
        fix(
          NoGroupByForFrequencies,
          "Enum.group_by(words, &String.downcase/1) |> Map.new(fn {k, g} -> {k, length(g)} end)"
        ),
        "Enum.frequencies_by(words, &String.downcase/1)"
      )
    end

    test "head-position group_by/2 (identity) piped to Enum.into(%{}) → frequencies" do
      confirm_fix(
        fix(
          NoGroupByForFrequencies,
          "Enum.group_by(list, & &1) |> Enum.into(%{}, fn {k, g} -> {k, length(g)} end)"
        ),
        "Enum.frequencies(list)"
      )
    end

    test "preserves leading pipe steps as the enum source" do
      code = """
      data
      |> Enum.map(fn x -> x.name end)
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {key, group} -> {key, length(group)} end)
      """

      expected = "Enum.frequencies_by(data |> Enum.map(fn x -> x.name end), &String.downcase/1)"

      confirm_fix(fix(NoGroupByForFrequencies, code), expected)
    end

    test "preserves a trailing pipe step after Map.new" do
      code = """
      words
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {key, group} -> {key, length(group)} end)
      |> Enum.sort()
      """

      expected = """
      Enum.frequencies_by(words, &String.downcase/1)
      |> Enum.sort()
      """

      confirm_fix(fix(NoGroupByForFrequencies, code), expected)
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def freq(words) do
          total = length(words)

          counts =
            words
            |> Enum.group_by(&String.downcase/1)
            |> Map.new(fn {key, group} -> {key, length(group)} end)

          {total, counts}
        end
      end
      """

      expected = """
      defmodule M do
        def freq(words) do
          total = length(words)

          counts =
            Enum.frequencies_by(words, &String.downcase/1)

          {total, counts}
        end
      end
      """

      confirm_fix(fix(NoGroupByForFrequencies, code), expected)
    end
  end

  describe "no-op — leaves code unchanged" do
    test "local length/1 may shadow Kernel.length/1" do
      code = """
      defmodule NoGroupByForFrequenciesShadowedLengthFixture do
        import Kernel, except: [length: 1]

        def length(_group), do: 99

        def freq(words) do
          words
          |> Enum.group_by(&String.downcase/1)
          |> Map.new(fn {key, group} -> {key, length(group)} end)
        end
      end

      %{"a" => 99} = NoGroupByForFrequenciesShadowedLengthFixture.freq(["A"])
      """

      emitted = fix(NoGroupByForFrequencies, code)

      confirm_fix(emitted, code)
      assert clean?(NoGroupByForFrequencies, code)
      assert {:ok, []} = RuleHelpers.compile_and_capture(code)
      assert RuleHelpers.compile_and_capture(emitted) == RuleHelpers.compile_and_capture(code)
    end

    test "non-frequency group_by (different transform)" do
      code = """
      words
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {key, items} -> {key, hd(items)} end)
      """

      confirm_fix(fix(NoGroupByForFrequencies, code), code)
    end

    test "piped group_by/3 with a value_fun" do
      code = """
      list
      |> Enum.group_by(fn x -> x.key end, fn x -> x.value end)
      |> Map.new(fn {k, g} -> {k, length(g)} end)
      """

      confirm_fix(fix(NoGroupByForFrequencies, code), code)
    end

    # group_by/3 in head position carries a value_fun, which frequencies_by/2
    # never calls — dropping a side-effecting value_fun would change the answer,
    # so this stays a no-op (only group_by/2 head-position is rewritten).
    test "head-position group_by/3 with a value_fun is left unchanged" do
      code = """
      Enum.group_by(words, &String.downcase/1, fn x -> x.id end)
      |> Map.new(fn {key, group} -> {key, length(group)} end)
      """

      confirm_fix(fix(NoGroupByForFrequencies, code), code)
    end
  end

  describe "round-trip" do
    test "fixed code no longer triggers the rule" do
      code = """
      words
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {key, group} -> {key, length(group)} end)
      """

      fixed = fix(NoGroupByForFrequencies, code)
      assert clean?(NoGroupByForFrequencies, fixed)
    end
  end
end
