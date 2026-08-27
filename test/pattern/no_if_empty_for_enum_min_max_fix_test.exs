defmodule Credence.Pattern.NoIfEmptyForEnumMinMaxFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoIfEmptyForEnumMinMax

  describe "fix — rewrites Enum.empty? forms to an explicit case" do
    test "preserves separate traversals for stateful enumerables" do
      source = "if Enum.empty?(values), do: 0, else: Enum.min(values)"

      confirm_fix(fix(NoIfEmptyForEnumMinMax, source), """
      case Enum.empty?(values) do
        true -> 0
        false -> Enum.min(values)
      end
      """)
    end

    test "if Enum.empty?(var), do: 0, else: Enum.min(var)" do
      confirm_fix(
        fix(
          NoIfEmptyForEnumMinMax,
          "if Enum.empty?(lengths), do: 0, else: Enum.min(lengths)"
        ),
        """
        case Enum.empty?(lengths) do
          true -> 0
          false -> Enum.min(lengths)
        end
        """
      )
    end

    test "if Enum.empty?(var), do: -1, else: Enum.max(var)" do
      confirm_fix(
        fix(
          NoIfEmptyForEnumMinMax,
          "if Enum.empty?(lengths), do: -1, else: Enum.max(lengths)"
        ),
        """
        case Enum.empty?(lengths) do
          true -> -1
          false -> Enum.max(lengths)
        end
        """
      )
    end

    test "if !Enum.empty?(var), do: Enum.min(var), else: default" do
      confirm_fix(
        fix(
          NoIfEmptyForEnumMinMax,
          "if !Enum.empty?(lengths), do: Enum.min(lengths), else: 0"
        ),
        """
        case Enum.empty?(lengths) do
          true -> 0
          false -> Enum.min(lengths)
        end
        """
      )
    end

    test "if not Enum.empty?(var), do: Enum.max(var), else: default" do
      confirm_fix(
        fix(
          NoIfEmptyForEnumMinMax,
          "if not Enum.empty?(lengths), do: Enum.max(lengths), else: -1"
        ),
        """
        case Enum.empty?(lengths) do
          true -> -1
          false -> Enum.max(lengths)
        end
        """
      )
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
          case Enum.empty?(lengths) do
            true -> 0
            false -> Enum.min(lengths)
          end
        end
      end
      """

      confirm_fix(fix(NoIfEmptyForEnumMinMax, code), expected)
    end
  end

  describe "fix — no-ops" do
    test "leaves plain Enum.min/1 untouched" do
      code = "Enum.min(lengths)"

      confirm_fix(fix(NoIfEmptyForEnumMinMax, code), code)
    end

    test "leaves already-correct Enum.min/2 untouched" do
      code = "Enum.min(lengths, fn -> 0 end)"

      confirm_fix(fix(NoIfEmptyForEnumMinMax, code), code)
    end

    test "leaves if var == [] form untouched (deliberately unflagged)" do
      code = "if lengths == [], do: 0, else: Enum.min(lengths)"

      confirm_fix(fix(NoIfEmptyForEnumMinMax, code), code)
    end

    test "leaves case-on-empty-list form untouched (deliberately unflagged)" do
      code = """
      case lengths do
        [] -> 0
        filtered -> Enum.min(filtered)
      end
      """

      confirm_fix(fix(NoIfEmptyForEnumMinMax, code), code)
    end

    test "leaves Enum.empty? with a different variable untouched" do
      code = "if Enum.empty?(a), do: 0, else: Enum.min(b)"

      confirm_fix(fix(NoIfEmptyForEnumMinMax, code), code)
    end
  end

  describe "fix — round-trip" do
    test "fixed code produces no issues" do
      code = "if Enum.empty?(lengths), do: 0, else: Enum.min(lengths)"

      assert check(NoIfEmptyForEnumMinMax, fix(NoIfEmptyForEnumMinMax, code)) == []
    end

    test "fixed negated form produces no issues" do
      code = "if !Enum.empty?(lengths), do: Enum.max(lengths), else: -1"

      assert check(NoIfEmptyForEnumMinMax, fix(NoIfEmptyForEnumMinMax, code)) == []
    end
  end
end
