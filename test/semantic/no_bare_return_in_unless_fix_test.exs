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

  test "strips return from unless without else" do
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
        unless value == :ok do
          {:error, :bad}
        end

        :ok
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

  test "strips return from if with block do/end form" do
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
        end

        {:ok, n}
      end
    end
    """

    confirm_fix(fix(input), expected)
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
