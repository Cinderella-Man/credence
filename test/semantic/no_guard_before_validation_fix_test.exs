defmodule Credence.Semantic.NoGuardBeforeValidationFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoGuardBeforeValidation

  @match_msg "guard duplicates body validation"

  defp fix(source, message \\ @match_msg, line \\ 1) do
    NoGuardBeforeValidation.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "removes redundant guard that duplicates body validation" do
    input = ~S"""
    defmodule GuardBeforeValidationExample do
      def process(data, interval_ms, opts \\ [])
          when is_map(data) and is_integer(interval_ms) and interval_ms > 0 do
        agg = Keyword.get(opts, :agg, :sum)

        unless agg in [:sum, :count] do
          raise ArgumentError, "invalid agg mode: #{inspect(agg)}"
        end

        unless interval_ms > 0 do
          raise ArgumentError, "interval_ms must be positive, got: #{interval_ms}"
        end

        {data, interval_ms, agg}
      end
    end
    """

    expected = ~S"""
    defmodule GuardBeforeValidationExample do
      def process(data, interval_ms, opts \\ [])
          when is_map(data) and is_integer(interval_ms) do
        agg = Keyword.get(opts, :agg, :sum)

        unless agg in [:sum, :count] do
          raise ArgumentError, "invalid agg mode: #{inspect(agg)}"
        end

        unless interval_ms > 0 do
          raise ArgumentError, "interval_ms must be positive, got: #{interval_ms}"
        end

        {data, interval_ms, agg}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule GuardBeforeValidationExample do
      def process(data, interval_ms, opts \\ [])
          when is_map(data) and is_integer(interval_ms) and interval_ms > 0 do
        unless interval_ms > 0 do
          raise ArgumentError, "interval_ms must be positive, got: #{interval_ms}"
        end
        {data, interval_ms}
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no guard duplicates body validation" do
    input = ~S"""
    defmodule CleanExample do
      def process(data, interval_ms) when is_map(data) and is_integer(interval_ms) do
        unless interval_ms > 0 do
          raise ArgumentError, "interval_ms must be positive"
        end
        data
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when body has no validation" do
    input = ~S"""
    defmodule NoValidationExample do
      def process(data, interval_ms)
          when is_map(data) and is_integer(interval_ms) and interval_ms > 0 do
        {data, interval_ms}
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
