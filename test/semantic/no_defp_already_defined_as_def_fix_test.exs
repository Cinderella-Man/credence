defmodule Credence.Semantic.NoDefpAlreadyDefinedAsDefFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoDefpAlreadyDefinedAsDef

  @real_message "defp sequence/2 already defined as def"

  defp fix(source, message, line \\ 1) do
    NoDefpAlreadyDefinedAsDef.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "renames defp to do_<name> when argument patterns differ from def" do
    input = """
    defmodule M do
      use GenServer

      def stab_count(server, point) do
        GenServer.call(server, {:stab_count, point})
      end

      def init(state), do: {:ok, state}

      def handle_call({:stab_count, point}, _from, tree) do
        {:reply, stab_count(tree, point), tree}
      end

      defp stab_count(nil, _point), do: 0
      defp stab_count(%{left: l, right: r}, point) do
        1 + stab_count(l, point) + stab_count(r, point)
      end
    end
    """

    result = fix(input, "defp stab_count/2 already defined as def", 15)
    assert valid_syntax?(result)
    # defp clauses renamed
    assert String.contains?(result, "defp do_stab_count(nil, _point)")
    assert String.contains?(result, "defp do_stab_count(%{left: l, right: r}, point)")
    # Internal recursive call sites renamed
    assert String.contains?(result, "do_stab_count(l, point)")
    assert String.contains?(result, "do_stab_count(r, point)")
    # handle_call call site renamed
    assert String.contains?(result, "do_stab_count(tree, point)")
    # The public def must NOT be renamed
    assert String.contains?(result, "def stab_count(server, point)")
    # The tuple literal must NOT be renamed
    assert String.contains?(result, "{:stab_count, point}")
  end

  test "removes defp when argument patterns are identical to def (no guard)" do
    input = """
    defmodule Example do
      def greet(name) do
        "Hello, " <> name
      end

      defp greet(name) do
        "Hi, " <> name
      end
    end
    """

    expected = """
    defmodule Example do
      def greet(name) do
        "Hello, " <> name
      end
    end
    """

    confirm_fix(fix(input, "defp greet/1 already defined as def", 6), expected)
  end

  test "removes defp with guard when argument patterns are identical" do
    input = """
    defmodule Example do
      def sequence(name, formatter_fn) do
        formatter_fn.(name)
      end

      # ... other code ...

      defp sequence(name, formatter_fn) when is_function(formatter_fn, 1) do
        formatter_fn.(name + 1)
      end
    end
    """

    expected = """
    defmodule Example do
      def sequence(name, formatter_fn) do
        formatter_fn.(name)
      end

      # ... other code ...
    end
    """

    confirm_fix(fix(input, @real_message, 8), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def greet(name) do
        "Hello, " <> name
      end

      defp greet(name) do
        "Hi, " <> name
      end
    end
    """

    assert valid_syntax?(fix(input, "defp greet/1 already defined as def", 6))
  end

  test "returns source unchanged when no matching defp found" do
    input = """
    defmodule Example do
      def other(name) do
        name
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule Example do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
