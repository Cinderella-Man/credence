defmodule Credence.Pattern.NoIfEmptyForEnumMinMaxCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoIfEmptyForEnumMinMax

  describe "check — flagged Enum.empty? forms" do
    test "detects if Enum.empty?(var) then default else Enum.min(var)" do
      code = """
      defmodule Bad do
        def run(lengths) do
          if Enum.empty?(lengths), do: 0, else: Enum.min(lengths)
        end
      end
      """

      issues = check(NoIfEmptyForEnumMinMax, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_if_empty_for_enum_min_max
    end

    test "detects if Enum.empty?(var) then default else Enum.max(var)" do
      code = """
      defmodule Bad do
        def run(lengths) do
          if Enum.empty?(lengths), do: -1, else: Enum.max(lengths)
        end
      end
      """

      assert length(check(NoIfEmptyForEnumMinMax, code)) == 1
    end

    test "detects if !Enum.empty?(var) then Enum.min(var) else default" do
      code = """
      defmodule Bad do
        def run(lengths) do
          if !Enum.empty?(lengths), do: Enum.min(lengths), else: 0
        end
      end
      """

      assert length(check(NoIfEmptyForEnumMinMax, code)) == 1
    end

    test "detects if not Enum.empty?(var) then Enum.max(var) else default" do
      code = """
      defmodule Bad do
        def run(lengths) do
          if not Enum.empty?(lengths), do: Enum.max(lengths), else: -1
        end
      end
      """

      assert length(check(NoIfEmptyForEnumMinMax, code)) == 1
    end
  end

  describe "check — does not fire" do
    test "does NOT fire on code that already uses Enum.min/2 with default" do
      code = """
      defmodule Good do
        def run(lengths) do
          Enum.min(lengths, fn -> 0 end)
        end
      end
      """

      assert check(NoIfEmptyForEnumMinMax, code) == []
    end

    test "does NOT fire on plain Enum.min/1 call" do
      code = """
      defmodule Good do
        def run(lengths) do
          Enum.min(lengths)
        end
      end
      """

      assert check(NoIfEmptyForEnumMinMax, code) == []
    end

    test "does NOT fire when Enum.empty? uses a different variable than the Enum call" do
      code = """
      defmodule Good do
        def run(a, b) do
          if Enum.empty?(a), do: 0, else: Enum.min(b)
        end
      end
      """

      assert check(NoIfEmptyForEnumMinMax, code) == []
    end
  end

  # The forms below test emptiness with the literal empty list (`== []`, `!= []`,
  # or a `[]` clause). On a non-list empty enumerable (`%{}`, an empty range, an
  # empty MapSet) the empty test is false / the `[]` clause does not match, so the
  # original calls `Enum.min(var)` and raises `Enum.EmptyError`, while the
  # `Enum.min(var, fn -> default end)` rewrite returns the default. That is a
  # behaviour change, so these forms are deliberately NOT flagged.
  describe "check — deliberately NOT flagged (non-list empty enumerables diverge)" do
    test "does NOT fire on if var == [] then default else Enum.min(var)" do
      code = """
      defmodule Skip do
        def run(lengths) do
          if lengths == [], do: 0, else: Enum.min(lengths)
        end
      end
      """

      assert check(NoIfEmptyForEnumMinMax, code) == []
    end

    test "does NOT fire on if var != [] then Enum.max(var) else default" do
      code = """
      defmodule Skip do
        def run(lengths) do
          if lengths != [], do: Enum.max(lengths), else: -1
        end
      end
      """

      assert check(NoIfEmptyForEnumMinMax, code) == []
    end

    test "does NOT fire on case var do [] -> default; v -> Enum.min(v) end" do
      code = """
      defmodule Skip do
        def run(lengths) do
          case lengths do
            [] -> 0
            filtered -> Enum.min(filtered)
          end
        end
      end
      """

      assert check(NoIfEmptyForEnumMinMax, code) == []
    end

    test "does NOT fire on case with wildcard _ using subject in Enum.max" do
      code = """
      defmodule Skip do
        def run(primes) do
          case primes do
            [] -> nil
            _ -> Enum.max(primes)
          end
        end
      end
      """

      assert check(NoIfEmptyForEnumMinMax, code) == []
    end
  end
end
