defmodule Credence.Semantic.NoUnderscorePatternBindingWithBareBodyUseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUnderscorePatternBindingWithBareBodyUse

  @message "variable \"_old_name\" is unused"

  defp fix(source, message, line) do
    NoUnderscorePatternBindingWithBareBodyUse.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "removes underscore from pattern binding in case clause" do
    input = """
    defmodule M do
      def convert_name(name) do
        case name do
          [{^name, {value, _old_name}}] ->
            new_name = String.upcase(name)
            IO.puts(old_name)
            IO.puts(new_name)
          [] ->
            :miss
        end
      end
    end
    """

    expected = """
    defmodule M do
      def convert_name(name) do
        case name do
          [{^name, {value, old_name}}] ->
            new_name = String.upcase(name)
            IO.puts(old_name)
            IO.puts(new_name)
          [] ->
            :miss
        end
      end
    end
    """

    confirm_fix(fix(input, @message, 4), expected)
  end

  test "removes underscore from nested tuple pattern binding" do
    input = """
    defmodule M do
      def convert(data) do
        case data do
          {:ok, {_key, _val}} ->
            IO.puts(val)
            :ok
          _ ->
            :error
        end
      end
    end
    """

    expected = """
    defmodule M do
      def convert(data) do
        case data do
          {:ok, {_key, val}} ->
            IO.puts(val)
            :ok
          _ ->
            :error
        end
      end
    end
    """

    confirm_fix(fix(input, "variable \"_val\" is unused", 4), expected)
  end

  test "does not touch other function clauses" do
    input = """
    defmodule M do
      def handle({:ok, _value}), do: :ok
      def handle({:error, _value}), do: :error
      def handle({:update, _value}), do
        value
      end
    end
    """

    expected = """
    defmodule M do
      def handle({:ok, _value}), do: :ok
      def handle({:error, _value}), do: :error
      def handle({:update, value}), do
        value
      end
    end
    """

    confirm_fix(fix(input, "variable \"_value\" is unused", 5), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def convert_name(name) do
        case name do
          [{^name, {value, _old_name}}] ->
            new_name = String.upcase(name)
            IO.puts(old_name)
            IO.puts(new_name)
          [] ->
            :miss
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @message, 4))
  end

  test "returns source unchanged when no underscore binding found" do
    input = """
    defmodule NoMatch do
      def test do
        x + 1
      end
    end
    """

    result = fix(input, "variable \"_missing\" is unused", 3)
    confirm_fix(result, input)
  end

  test "returns source unchanged when bare name not used in body" do
    input = """
    defmodule NoMatch do
      def test do
        _unused = 1
        :ok
      end
    end
    """

    result = fix(input, "variable \"_unused\" is unused", 3)
    confirm_fix(result, input)
  end
end
