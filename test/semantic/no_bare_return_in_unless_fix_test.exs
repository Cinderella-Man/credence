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

  test "ignores unless without else" do
    source = """
    defmodule Example do
      def check(value) do
        unless value == :ok do
          return {:error, :bad}
        end

        :ok
      end
    end
    """

    confirm_fix(fix(source), source)
  end

  test "ignores return outside unless" do
    source = """
    defmodule Example do
      def check(value) do
        return value
      end
    end
    """

    confirm_fix(fix(source), source)
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
end
