defmodule Credence.Semantic.NoRedefineBuiltinTypeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoRedefineBuiltinType

  @real_message "credence_check.ex:2: type node/0 is a built-in type and it cannot be redefined"

  defp fix(source, message \\ @real_message, line \\ 2) do
    NoRedefineBuiltinType.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "the target really raises the built-in-type diagnostic and the fix resolves it" do
    input = """
    defmodule Trie do
      @type node :: %{children: %{char => node}, end_of_word: boolean}
      @type t :: node
    end
    """

    # Production path: compiling the target genuinely produces an error-severity
    # diagnostic this rule matches (not a fabricated message that never fires).
    {:error, diagnostics} = Credence.RuleHelpers.compile_and_capture(input)
    diag = Enum.find(diagnostics, &NoRedefineBuiltinType.match?/1)
    assert diag, "expected the built-in-type redefinition diagnostic to be emitted"

    # And applying the fix produces source that compiles cleanly.
    fixed = NoRedefineBuiltinType.fix(input, diag)
    assert {:ok, _} = Credence.RuleHelpers.compile_and_capture(fixed)
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

  test "fixed output is well-formed (parses) and renames the type" do
    input = """
    defmodule Trie do
      @type node :: %{children: %{char => node}, end_of_word: boolean}
      @type t :: node

      defstruct [:children, :end_of_word]
    end
    """

    expected = """
    defmodule Trie do
      @type trie_node :: %{children: %{char => trie_node}, end_of_word: boolean}
      @type t :: trie_node

      defstruct [:children, :end_of_word]
    end
    """

    assert valid_syntax?(fix(input))
    confirm_fix(fix(input), expected)
  end

  test "renames the type reference but leaves same-named variables untouched" do
    input = """
    defmodule Tree do
      @type node :: %{value: integer, left: node, right: node}

      def insert(node, value) do
        %{node | value: value}
      end
    end
    """

    # The @type LHS + its self-references become trie_node; the `node`
    # variable and pattern in insert/2 stay exactly as written.
    expected = """
    defmodule Tree do
      @type trie_node :: %{value: integer, left: trie_node, right: trie_node}

      def insert(node, value) do
        %{node | value: value}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "renames @typep too" do
    input = """
    defmodule Tree do
      @typep node :: %{value: integer, children: list(node)}
      @type t :: node
    end
    """

    expected = """
    defmodule Tree do
      @typep trie_node :: %{value: integer, children: list(trie_node)}
      @type t :: trie_node
    end
    """

    confirm_fix(fix(input), expected)
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

  test "renames a parameterized built-in type using the compiler diagnostic" do
    input = """
    defmodule ParameterizedBuiltin do
      @type list(element) :: [element]
      @type strings :: list(String.t())
    end
    """

    expected = """
    defmodule ParameterizedBuiltin do
      @type trie_list(element) :: [element]
      @type strings :: trie_list(String.t())
    end
    """

    {:error, diagnostics} = Credence.RuleHelpers.compile_and_capture(input)
    diag = Enum.find(diagnostics, &NoRedefineBuiltinType.match?/1)
    assert diag, "expected the parameterized built-in-type diagnostic to be emitted"

    emitted = NoRedefineBuiltinType.fix(input, diag)

    confirm_fix(emitted, expected)
    assert {:ok, _} = Credence.RuleHelpers.compile_and_capture(emitted)
  end

  test "returns source unchanged when the flagged type is absent from the source" do
    input = """
    defmodule Foo do
      @type other :: atom()
    end
    """

    # The message names `node`, but the source defines no `node` type, so the
    # rename finds nothing to change and the source is returned untouched.
    confirm_fix(
      fix(input, "file.ex:2: type node/0 is a built-in type and it cannot be redefined"),
      input
    )
  end

  test "only renames references in the module containing the rejected definition" do
    input = """
    defmodule BadScopeA do
      @type node :: atom()
    end

    defmodule GoodScopeB do
      @type t :: node
    end
    """

    expected = """
    defmodule BadScopeA do
      @type trie_node :: atom()
    end

    defmodule GoodScopeB do
      @type t :: node
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "chooses an unused replacement when trie_node is already defined" do
    input = """
    defmodule Collision do
      @type trie_node :: integer()
      @type node :: atom()
    end
    """

    emitted = fix(input, @real_message, 3)

    expected = """
    defmodule Collision do
      @type trie_node :: integer()
      @type trie_node_2 :: atom()
    end
    """

    confirm_fix(emitted, expected)
    assert {:ok, _} = Credence.RuleHelpers.compile_and_capture(emitted)
  end

  test "renames references in specs in the affected module" do
    input = """
    defmodule SpecCase do
      @type node :: atom()
      @spec f() :: node
      def f, do: :ok
    end
    """

    expected = """
    defmodule SpecCase do
      @type trie_node :: atom()
      @spec f() :: trie_node
      def f, do: :ok
    end
    """

    confirm_fix(fix(input), expected)
  end
end
