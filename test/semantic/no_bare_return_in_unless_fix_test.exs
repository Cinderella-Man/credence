defmodule Credence.Semantic.NoBareReturnInUnlessFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoBareReturnInUnless

  @msg "undefined function return/1"

  defp fix(source, line \\ 1) do
    NoBareReturnInUnless.fix(source, %{severity: :error, message: @msg, position: {line, 1}})
  end

  @input """
  defmodule MetricAggregator do
    def validate(name, value, tags) do
      case nil do
        {:ok, _} ->
          unless is_binary(name) and String.length(name) > 0 do
            return {:error, :invalid_name}
          else
            unless is_number(value) do
              return {:error, :invalid_value}
            else
              unless is_map(tags) do
                return {:error, :invalid_tags}
              else
                {:ok, %{name: name, value: value, tags: tags}}
              end
            end
          end
      end
    end
  end
  """

  @expected """
  defmodule MetricAggregator do
    def validate(name, value, tags) do
      case nil do
        {:ok, _} ->
          unless is_binary(name) and String.length(name) > 0 do
            {:error, :invalid_name}
          else
            unless is_number(value) do
              {:error, :invalid_value}
            else
              unless is_map(tags) do
                {:error, :invalid_tags}
              else
                {:ok, %{name: name, value: value, tags: tags}}
              end
            end
          end
      end
    end
  end
  """

  test "removes return from unless with else" do
    confirm_fix(fix(@input), @expected)
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix(@input))
  end

  # This test used to assert the *bug*: it expected the `return` to be stripped
  # in place, leaving `unless … do {:error, :bad} end` as a discarded expression
  # with `:ok` still running afterwards. That output compiles clean and returns
  # `:ok` for every input, so the validation silently stopped happening — and
  # the test passed the whole time, because the expectation was written from the
  # implementation rather than from the program's meaning.
  test "restructures an unless early-exit guard into if/else" do
    input = """
    defmodule Example do
      def check(value) do
        unless value == :ok do
          return {:error, :bad}
        end

        :ok
      end
    end
    """

    expected = """
    defmodule Example do
      def check(value) do
        if value == :ok do
          :ok
        else
          {:error, :bad}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "strips bare return outside unless" do
    input = """
    defmodule Example do
      def check(value) do
        return value
      end
    end
    """

    expected = """
    defmodule Example do
      def check(value) do
        value
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "handles single unless with else" do
    input = """
    defmodule Example do
      def check(value) do
        unless value == :ok do
          return {:error, :bad}
        else
          :ok
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def check(value) do
        unless value == :ok do
          {:error, :bad}
        else
          :ok
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "restructures if COND, do: return(EXPR); REST into if/else" do
    input = """
    defmodule EarlyReturnInIf do
      def check(n) do
        if n == 0, do: return(:empty)
        {:ok, n}
      end
    end
    """

    expected = """
    defmodule EarlyReturnInIf do
      def check(n) do
        if n == 0 do
          :empty
        else
          {:ok, n}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed if early-return output is well-formed (parses)" do
    input = """
    defmodule EarlyReturnInIf do
      def check(n) do
        if n == 0, do: return(:empty)
        {:ok, n}
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  # Same story as the `unless` case above — the old expectation discarded the
  # `:empty` branch and let `{:ok, n}` run unconditionally.
  test "restructures an if early-exit guard into if/else" do
    input = """
    defmodule Example do
      def check(n) do
        if n == 0 do
          return(:empty)
        end

        {:ok, n}
      end
    end
    """

    expected = """
    defmodule Example do
      def check(n) do
        if n == 0 do
          :empty
        else
          {:ok, n}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  # The output above is asserted as text; this asserts what it MEANS. A future
  # change that makes the rule emit a discarded expression again would keep the
  # file compiling and would slip past every string comparison in this file.
  test "the repaired guard actually still guards" do
    input = """
    defmodule EarlyExitBehaviour do
      def check(n) do
        unless n >= 0 do
          return({:error, :neg})
        end

        {:ok, n}
      end
    end
    """

    fixed = fix(input)

    assert Credence.RuleCase.call_fixed(fixed, EarlyExitBehaviour, :check, [-5]) ==
             {:error, :neg}

    assert Credence.RuleCase.call_fixed(fixed, EarlyExitBehaviour, :check, [5]) == {:ok, 5}
  end

  test "preserves early exit from an if with else" do
    input = """
    defmodule EarlyExitWithElseNBRIU do
      def check(flag) do
        if flag, do: return(:error), else: :ok
        :continued
      end
    end
    """

    expected = """
    defmodule EarlyExitWithElseNBRIU do
      def check(flag) do
        if flag do
          :error
        else
          :ok
          :continued
        end
      end
    end
    """

    fixed = fix(input)
    confirm_fix(fixed, expected)
    assert Credence.RuleCase.call_fixed(fixed, EarlyExitWithElseNBRIU, :check, [true]) == :error

    assert Credence.RuleCase.call_fixed(fixed, EarlyExitWithElseNBRIU, :check, [false]) ==
             :continued
  end

  test "nil is an early-exit value, not the not-found sentinel" do
    input = """
    defmodule NilEarlyExitNBRIU do
      def check(flag) do
        if flag, do: return(nil)
        :continued
      end
    end
    """

    expected = """
    defmodule NilEarlyExitNBRIU do
      def check(flag) do
        if flag do
          nil
        else
          :continued
        end
      end
    end
    """

    fixed = fix(input)
    confirm_fix(fixed, expected)
    assert Credence.RuleCase.call_fixed(fixed, NilEarlyExitNBRIU, :check, [true]) == nil

    assert Credence.RuleCase.call_fixed(fixed, NilEarlyExitNBRIU, :check, [false]) ==
             :continued
  end

  test "preserves work before a terminal return in a conditional branch" do
    input = """
    defmodule WorkedEarlyExitNBRIU do
      def check(flag) do
        if flag do
          Process.put(:worked_early_exit_nbriu, true)
          return(:error)
        end

        :continued
      end
    end
    """

    expected = """
    defmodule WorkedEarlyExitNBRIU do
      def check(flag) do
        if flag do
          Process.put(:worked_early_exit_nbriu, true)
          :error
        else
          :continued
        end
      end
    end
    """

    fixed = fix(input)
    confirm_fix(fixed, expected)
    Process.delete(:worked_early_exit_nbriu)
    assert Credence.RuleCase.call_fixed(fixed, WorkedEarlyExitNBRIU, :check, [true]) == :error
    assert Process.get(:worked_early_exit_nbriu) == true
  after
    Process.delete(:worked_early_exit_nbriu)
  end

  test "preserves early exit from a non-final case branch" do
    input = """
    defmodule CaseEarlyExitNBRIU do
      def check(value) do
        case value do
          :bad -> return(:error)
          _ -> :ok
        end

        :continued
      end
    end
    """

    expected = """
    defmodule CaseEarlyExitNBRIU do
      def check(value) do
        case value do
          :bad ->
            :error

          _ ->
            :ok
            :continued
        end
      end
    end
    """

    fixed = fix(input)
    confirm_fix(fixed, expected)
    assert Credence.RuleCase.call_fixed(fixed, CaseEarlyExitNBRIU, :check, [:bad]) == :error
    assert Credence.RuleCase.call_fixed(fixed, CaseEarlyExitNBRIU, :check, [:ok]) == :continued
  end

  test "strips return from case branch" do
    input = """
    defmodule DBCleaner do
      def clean() do
        case get_spec() do
          nil -> :ok
          _spec ->
            case :error do
              {:ok, ordered_tables} ->
                Enum.each(ordered_tables, fn table ->
                  IO.puts("DELETE FROM \#{table}")
                end)
                :ok

              {:error, {:cycle, remaining_tables}} ->
                return {:error, {:cycle, remaining_tables}}
            end
        end
      end

      defp get_spec, do: Process.get(:spec)
    end
    """

    expected = """
    defmodule DBCleaner do
      def clean() do
        case get_spec() do
          nil ->
            :ok

          _spec ->
            case :error do
              {:ok, ordered_tables} ->
                Enum.each(ordered_tables, fn table ->
                  IO.puts("DELETE FROM \#{table}")
                end)

                :ok

              {:error, {:cycle, remaining_tables}} ->
                {:error, {:cycle, remaining_tables}}
            end
        end
      end

      defp get_spec, do: Process.get(:spec)
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "case branch fix is well-formed (parses)" do
    input = """
    defmodule DBCleaner do
      def clean() do
        case get_spec() do
          nil -> :ok
          _spec ->
            case :error do
              {:error, {:cycle, remaining_tables}} ->
                return {:error, {:cycle, remaining_tables}}
            end
        end
      end

      defp get_spec, do: Process.get(:spec)
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "ignores if keyword do: without return" do
    source = """
    defmodule Example do
      def check(n) do
        if n == 0, do: :empty
        {:ok, n}
      end
    end
    """

    confirm_fix(fix(source), source)
  end
end
