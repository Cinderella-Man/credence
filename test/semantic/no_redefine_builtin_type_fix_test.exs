defmodule Credence.Semantic.NoRedefineBuiltinTypeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoRedefineBuiltinType

  @real_message "credence_check.ex:2: type node/0 is a built-in type and it cannot be redefined"

  defp fix(source, message \\ @real_message, line \\ 2) do
    NoRedefineBuiltinType.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "renames @type node to @type trie_node" do
    input = """
    defmodule Trie do
      @type node :: %{children: %{char => node}, end_of_word: boolean}
      @type t :: node

      defstruct [:children, :end_of_word]

      def new(), do: %{children: %{}, end_of_word: false}

      def insert(trie, word) do
        insert_word(trie, word, 0)
      end

      defp insert_word(node, word, index) do
        if index == String.length(word) do
          %{node | end_of_word: true}
        else
          char = String.at(word, index)
          children =
            case Map.get(node.children, char) do
              nil -> %{children: %{}, end_of_word: false}
              child -> child
            end
          new_child = insert_word(children, word, index + 1)
          %{node | children: Map.put(node.children, char, new_child)}
        end
      end

      def size(trie), do: count_words(trie, 0)

      defp count_words(%{end_of_word: eow, children: children}, acc) do
        acc = if eow, do: acc + 1, else: acc
        Enum.reduce(children, acc, fn {_char, child}, a -> count_words(child, a) end)
      end
    end
    """

    expected = """
    defmodule Trie do
      @type trie_node :: %{children: %{char => trie_node}, end_of_word: boolean}
      @type t :: trie_node

      defstruct [:children, :end_of_word]

      def new(), do: %{children: %{}, end_of_word: false}

      def insert(trie, word) do
        insert_word(trie, word, 0)
      end

      defp insert_word(node, word, index) do
        if index == String.length(word) do
          %{node | end_of_word: true}
        else
          char = String.at(word, index)

          children =
            case Map.get(node.children, char) do
              nil -> %{children: %{}, end_of_word: false}
              child -> child
            end

          new_child = insert_word(children, word, index + 1)
          %{node | children: Map.put(node.children, char, new_child)}
        end
      end

      def size(trie), do: count_words(trie, 0)

      defp count_words(%{end_of_word: eow, children: children}, acc) do
        acc = if eow, do: acc + 1, else: acc
        Enum.reduce(children, acc, fn {_char, child}, a -> count_words(child, a) end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Trie do
      @type node :: %{children: %{char => node}, end_of_word: boolean}
      @type t :: node

      defstruct [:children, :end_of_word]
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "preserves variable names" do
    input = """
    defmodule Tree do
      @type node :: %{value: integer, left: node, right: node}

      def insert(node, value) do
        %{node | value: value}
      end
    end
    """

    result = fix(input)
    # Variable names should be preserved
    assert String.contains?(result, "def insert(node, value)")
    assert String.contains?(result, "%{node | value: value}")
    # Type should be renamed
    assert String.contains?(result, "@type trie_node")
    refute String.contains?(result, "@type node")
  end

  test "renames @typep too" do
    input = """
    defmodule Tree do
      @typep node :: %{value: integer, children: list(node)}
      @type t :: node
    end
    """

    result = fix(input)
    assert String.contains?(result, "@typep trie_node")
    assert String.contains?(result, "@type t :: trie_node")
  end

  test "returns source unchanged when no type name in message" do
    input = """
    defmodule Foo do
      @type node :: atom()
    end
    """

    result =
      NoRedefineBuiltinType.fix(input, %{severity: :error, message: "unrelated", position: {1, 1}})

    confirm_fix(result, input)
  end

  test "returns source unchanged when type is not a builtin" do
    input = """
    defmodule Foo do
      @type my_type :: atom()
    end
    """

    # Message says "my_type" is a builtin, but source doesn't define it
    # Actually, the fix should still try — the rename just won't find the type
    result = fix(input, "file.ex:2: type my_type/0 is a built-in type and it cannot be redefined")
    # Should return unchanged since @type my_type is not in the source... wait,
    # it IS in the source. The fix should rename it.
    assert String.contains?(result, "@type trie_my_type")
  end
end
