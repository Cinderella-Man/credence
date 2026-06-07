defmodule Credence.Pattern.NoIfEmptyForEnumMinMaxFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoIfEmptyForEnumMinMax

  describe "fix — rewrites Enum.empty? forms to Enum.min/2 or Enum.max/2" do
    test "if Enum.empty?(var), do: 0, else: Enum.min(var)" do
      assert fix(
               NoIfEmptyForEnumMinMax,
               """
               if Enum.empty?(lengths), do: 0, else: Enum.min(lengths)
               """
             ) ==
               """
               Enum.min(lengths, fn -> 0 end)
               """
    end

    test "if Enum.empty?(var), do: -1, else: Enum.max(var)" do
      assert fix(
               NoIfEmptyForEnumMinMax,
               """
               if Enum.empty?(lengths), do: -1, else: Enum.max(lengths)
               """
             ) ==
               """
               Enum.max(lengths, fn -> -1 end)
               """
    end

    test "if !Enum.empty?(var), do: Enum.min(var), else: default" do
      assert fix(
               NoIfEmptyForEnumMinMax,
               """
               if !Enum.empty?(lengths), do: Enum.min(lengths), else: 0
               """
             ) ==
               """
               Enum.min(lengths, fn -> 0 end)
               """
    end

    test "if not Enum.empty?(var), do: Enum.max(var), else: default" do
      assert fix(
               NoIfEmptyForEnumMinMax,
               """
               if not Enum.empty?(lengths), do: Enum.max(lengths), else: -1
               """
             ) ==
               """
               Enum.max(lengths, fn -> -1 end)
               """
    end

    test "rewrites inside surrounding code, leaving the rest intact" do
      code = """
      defmodule Example do
        def run(lengths) do
          if Enum.empty?(lengths), do: 0, else: Enum.min(lengths)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(lengths) do
          Enum.min(lengths, fn -> 0 end)
        end
      end
      """

      assert fix(NoIfEmptyForEnumMinMax, code) == expected
    end
  end

  describe "fix — no-ops" do
    test "leaves plain Enum.min/1 untouched" do
      code = """
      Enum.min(lengths)
      """

      assert fix(NoIfEmptyForEnumMinMax, code) == code
    end

    test "leaves already-correct Enum.min/2 untouched" do
      code = """
      Enum.min(lengths, fn -> 0 end)
      """

      assert fix(NoIfEmptyForEnumMinMax, code) == code
    end

    test "leaves if var == [] form untouched (deliberately unflagged)" do
      code = """
      if lengths == [], do: 0, else: Enum.min(lengths)
      """

      assert fix(NoIfEmptyForEnumMinMax, code) == code
    end

    test "leaves case-on-empty-list form untouched (deliberately unflagged)" do
      code = """
      case lengths do
        [] -> 0
        filtered -> Enum.min(filtered)
      end
      """

      assert fix(NoIfEmptyForEnumMinMax, code) == code
    end

    test "leaves Enum.empty? with a different variable untouched" do
      code = """
      if Enum.empty?(a), do: 0, else: Enum.min(b)
      """

      assert fix(NoIfEmptyForEnumMinMax, code) == code
    end
  end

  describe "fix — round-trip" do
    test "fixed code produces no issues" do
      code = """
      if Enum.empty?(lengths), do: 0, else: Enum.min(lengths)
      """

      assert check(NoIfEmptyForEnumMinMax, fix(NoIfEmptyForEnumMinMax, code)) == []
    end

    test "fixed negated form produces no issues" do
      code = """
      if !Enum.empty?(lengths), do: Enum.max(lengths), else: -1
      """

      assert check(NoIfEmptyForEnumMinMax, fix(NoIfEmptyForEnumMinMax, code)) == []
    end
  end
end
