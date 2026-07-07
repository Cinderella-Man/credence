defmodule Credence.Semantic.NoListKeystoreThreeArgsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoListKeystoreThreeArgs

  @real_message "List.keystore/3 is undefined or private. Did you mean:\n\n    * keystore/4\n"

  defp fix(source, message, line \\ 1) do
    NoListKeystoreThreeArgs.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "inserts 0 as position argument" do
    input = """
    defmodule Repaired do
      def update_topic_refs(topic_refs, topic, new_ref_list) do
        List.keystore(topic_refs, topic, {topic, new_ref_list})
      end
    end
    """

    expected = """
    defmodule Repaired do
      def update_topic_refs(topic_refs, topic, new_ref_list) do
        List.keystore(topic_refs, 0, topic, {topic, new_ref_list})
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Repaired do
      def update_topic_refs(topic_refs, topic, new_ref_list) do
        List.keystore(topic_refs, topic, {topic, new_ref_list})
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no List.keystore/3 call" do
    input = """
    defmodule Clean do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged when List.keystore/4 is used correctly" do
    input = """
    defmodule Correct do
      def update(list, key, tuple) do
        List.keystore(list, 0, key, tuple)
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
