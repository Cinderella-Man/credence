defmodule Credence.Semantic.PreferRescueBeforeCatchFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.PreferRescueBeforeCatch

  @message "\"catch\" should always come after \"rescue\" in try"

  defp fix(source, line \\ 3) do
    PreferRescueBeforeCatch.fix(source, %{
      severity: :warning,
      message: @message,
      position: {line, 5}
    })
  end

  test "reorders catch before rescue to rescue before catch" do
    input = """
    defmodule CredenceRescueOrderFixBasic do
      def run(fn_or_val) do
        result =
          try do
            {:ok, fn_or_val.()}
          catch
            :exit, reason ->
              {:error, %{kind: :exit, reason: reason}}

            :throw, value ->
              {:error, %{kind: :throw, reason: value}}
          rescue
            e ->
              {:error, %{kind: :error, reason: Exception.message(e)}}
          end

        result
      end
    end
    """

    expected = """
    defmodule CredenceRescueOrderFixBasic do
      def run(fn_or_val) do
        result =
          try do
            {:ok, fn_or_val.()}
          rescue
            e ->
              {:error, %{kind: :error, reason: Exception.message(e)}}
          catch
            :exit, reason ->
              {:error, %{kind: :exit, reason: reason}}

            :throw, value ->
              {:error, %{kind: :throw, reason: value}}
          end

        result
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "keeps else and after in place while moving rescue ahead of catch" do
    input = """
    defmodule CredenceRescueOrderElseAfter do
      def run(f) do
        try do
          f.()
        catch
          :exit, reason -> {:exit, reason}
          :throw, value -> {:throw, value}
        else
          value -> {:ok, value}
        after
          IO.puts("done")
        rescue
          e in ArgumentError -> {:arg, e.message}
        end
      end
    end
    """

    expected = """
    defmodule CredenceRescueOrderElseAfter do
      def run(f) do
        try do
          f.()
        rescue
          e in ArgumentError -> {:arg, e.message}
        catch
          :exit, reason -> {:exit, reason}
          :throw, value -> {:throw, value}
        else
          value -> {:ok, value}
        after
          IO.puts("done")
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  test "reorders both the inner and the outer try" do
    input = """
    defmodule CredenceRescueOrderNested do
      def run(f) do
        try do
          try do
            f.()
          catch
            :exit, reason -> {:inner_exit, reason}
          rescue
            e -> {:inner_rescue, e}
          end
        catch
          :throw, value -> {:outer_throw, value}
        rescue
          e -> {:outer_rescue, e}
        end
      end
    end
    """

    expected = """
    defmodule CredenceRescueOrderNested do
      def run(f) do
        try do
          try do
            f.()
          rescue
            e -> {:inner_rescue, e}
          catch
            :exit, reason -> {:inner_exit, reason}
          end
        rescue
          e -> {:outer_rescue, e}
        catch
          :throw, value -> {:outer_throw, value}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "does not change source where rescue already precedes catch" do
    input = """
    defmodule CredenceRescueOrderAlreadyCorrectFix do
      def run(fn_or_val) do
        try do
          {:ok, fn_or_val.()}
        rescue
          e ->
            {:error, Exception.message(e)}
        catch
          :exit, reason ->
            {:error, reason}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not touch a def body that puts catch before rescue" do
    input = """
    defmodule CredenceRescueOrderDefLevelFix do
      def run(f) do
        f.()
      catch
        :exit, reason -> {:exit, reason}
      rescue
        e -> {:rescue, e}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not touch a try that has a catch but no rescue" do
    input = """
    defmodule CredenceRescueOrderCatchOnlyFix do
      def run(f) do
        try do
          f.()
        catch
          :exit, reason -> {:exit, reason}
        after
          IO.puts("done")
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not touch a local call named try" do
    input = """
    defmodule CredenceRescueOrderLocalTryCall do
      def run(x), do: try(x)
    end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves unparseable source alone" do
    input = "defmodule Broken do"

    confirm_fix(fix(input), input)
  end

  test "the whole semantic phase reorders the block and clears the warning" do
    input = """
    defmodule CredenceRescueOrderEndToEnd do
      def run(f) do
        try do
          f.()
        catch
          :exit, reason -> {:exit, reason}
        rescue
          e -> {:rescue, e}
        end
      end
    end
    """

    expected = """
    defmodule CredenceRescueOrderEndToEnd do
      def run(f) do
        try do
          f.()
        rescue
          e -> {:rescue, e}
        catch
          :exit, reason -> {:exit, reason}
        end
      end
    end
    """

    fixed = Credence.Semantic.fix(input)
    confirm_fix(fixed, expected)

    {:ok, diags} = Credence.RuleHelpers.compile_and_capture(fixed)
    refute Enum.any?(diags, &PreferRescueBeforeCatch.match?/1)
  end
end
