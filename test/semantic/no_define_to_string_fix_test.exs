defmodule Credence.Semantic.NoDefineToStringFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoDefineToString

  @real_message "imported Kernel.to_string/1 conflicts with local function"

  defp fix(source, message, line \\ 1) do
    NoDefineToString.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "renames to_string/1 to key_to_string/1 in full module" do
    input = """
    defmodule Anonymizer do
      defp to_string(key) when is_binary(key), do: key
      defp to_string(key) when is_atom(key), do: Atom.to_string(key)

      defp apply_rule_to_path(record, segments) do
        case segments do
          [segment | rest] ->
            segment_str = to_string(segment)
            apply_rule_to_path(record, segment_str, rest)
          [] -> nil
        end
      end

      defp apply_rule_to_path(record, segments) when is_list(record) do
        case segments do
          [segment | rest] ->
            segment_str = to_string(segment)
            apply_rule_to_path(record, segment_str, rest)
          _ -> nil
        end
      end

      defp transform_value(value) do
        :crypto.hash(:sha256, to_string(value))
      end
    end
    """

    result = fix(input, @real_message)

    # Verify key_to_string is present
    assert result =~ "key_to_string(segment)"
    assert result =~ "key_to_string(key) when is_binary(key)"
    assert result =~ "key_to_string(key) when is_atom(key)"
    assert result =~ "key_to_string(value)"

    # Verify no bare to_string function definition remains
    refute result =~ "defp to_string("

    # Verify qualified calls are untouched
    assert result =~ "Atom.to_string(key)"
  end

  test "renames to_string/1 to key_to_string/1 in single-clause module" do
    input = """
    defmodule Anonymizer do
      defp to_string(key) when is_binary(key), do: key
      defp to_string(key) when is_atom(key), do: Atom.to_string(key)
      def hello(x), do: to_string(x)
    end
    """

    expected = """
    defmodule Anonymizer do
      defp key_to_string(key) when is_binary(key), do: key
      defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
      def hello(x), do: key_to_string(x)
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Anonymizer do
      defp to_string(key) when is_binary(key), do: key
      defp to_string(key) when is_atom(key), do: Atom.to_string(key)
      def hello(x), do: to_string(x)
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no to_string conflict" do
    input = """
    defmodule CleanExample do
      def hello, do: Kernel.to_string(:world)
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
