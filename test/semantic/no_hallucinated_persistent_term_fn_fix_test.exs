defmodule Credence.Semantic.NoHallucinatedPersistentTermFnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedPersistentTermFn

  @real_message "clauses with the same name and arity (number of arguments) should be grouped together, \"def handle_call/3\" was previously defined (credence_check.ex:90)"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedPersistentTermFn.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "fixes the get_keys pattern" do
    input = """
    defmodule PTCleanup do
      def cleanup_keys do
        keys = :persistent_term.get_keys()
        Enum.each(keys, fn key ->
          :persistent_term.erase(key)
        end)
      end
    end
    """

    expected = """
    defmodule PTCleanup do
      def cleanup_keys do
        Enum.each(:persistent_term.get(), fn {key, _value} ->
          :persistent_term.erase(key)
        end)
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule PTCleanup do
      def cleanup_keys do
        keys = :persistent_term.get_keys()
        Enum.each(keys, fn key ->
          :persistent_term.erase(key)
        end)
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no :persistent_term.get_keys present" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def add(a, b), do: a + b
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
