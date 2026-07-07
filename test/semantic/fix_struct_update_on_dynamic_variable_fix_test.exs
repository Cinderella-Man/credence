defmodule Credence.Semantic.FixStructUpdateOnDynamicVariableFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixStructUpdateOnDynamicVariable

  @message "a struct for AutocompleteTrie is expected on struct update:\n\n    %AutocompleteTrie{node | weight: weight}\n\nbut got type:\n\n    dynamic()\n\nwhere \"node\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:36:18\n    node\n\nwhen defining the variable \"node\", you must also pattern match on \"%AutocompleteTrie{}\".\n\nhint: given pattern matching is enough to catch typing errors, you may optionally convert the struct update into a map update. For example, instead of:\n\n    user = some_function()\n    %User{user | name: \"John Doe\"}\n\nit is enough to write:\n\n    %User{} = user = some_function()\n    %{user | name: \"John Doe\"}\n"

  defp fix(source, message, line \\ 1) do
    FixStructUpdateOnDynamicVariable.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "adds struct pattern to tuple destructuring" do
    input = """
    defmodule AutocompleteTrie do
      defstruct children: %{}, weight: 0, count: 0

      def insert(trie, word) do
        {node, flag} = do_insert(trie, word)
        if flag do
          %__MODULE__{node | count: node.count + 1}
        else
          node
        end
      end

      defp do_insert(trie, word) do
        {%__MODULE__{trie | weight: 1}, true}
      end
    end
    """

    expected = """
    defmodule AutocompleteTrie do
      defstruct children: %{}, weight: 0, count: 0

      def insert(trie, word) do
        {%__MODULE__{} = node, flag} = do_insert(trie, word)

        if flag do
          %__MODULE__{node | count: node.count + 1}
        else
          node
        end
      end

      defp do_insert(trie, word) do
        {%__MODULE__{trie | weight: 1}, true}
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule AutocompleteTrie do
      defstruct children: %{}, weight: 0, count: 0

      def insert(trie, word) do
        {node, flag} = do_insert(trie, word)
        if flag do
          %__MODULE__{node | count: node.count + 1}
        else
          node
        end
      end

      defp do_insert(trie, word) do
        {%__MODULE__{trie | weight: 1}, true}
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no tuple destructuring with target variable" do
    input = """
    defmodule Example do
      def test do
        x + 1
      end
    end
    """

    result = fix(input, @message)
    confirm_fix(result, input)
  end

  test "returns source unchanged when variable not in tuple" do
    input = """
    defmodule Example do
      def test do
        {a, b} = {1, 2}
        a + b
      end
    end
    """

    # The message references "node" but the source has "a" and "b"
    result = fix(input, @message)
    confirm_fix(result, input)
  end

  test "handles variable in second position of tuple" do
    input = """
    defmodule Example do
      defstruct [:value]

      def get_pair(x) do
        {flag, node} = compute(x)
        %__MODULE__{node | value: node.value + 1}
      end
    end
    """

    expected = """
    defmodule Example do
      defstruct [:value]

      def get_pair(x) do
        {flag, %__MODULE__{} = node} = compute(x)
        %__MODULE__{node | value: node.value + 1}
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end
end
