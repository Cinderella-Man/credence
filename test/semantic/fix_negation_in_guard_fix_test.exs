defmodule Credence.Semantic.FixNegationInGuardFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixNegationInGuard
  alias Credence.RuleHelpers

  @real_message "invalid expression in guard, ! is not allowed in guards. To learn more about guards, visit: https://hexdocs.pm/elixir/patterns-and-guards.html"

  defp fix(source, message \\ @real_message, line \\ 2) do
    FixNegationInGuard.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "replaces ! with not in guard" do
    input = """
    defmodule ShipStockValidator do
      def validate(quantity, available) when !is_number(quantity) or quantity <= 0 do
        {:error, :invalid_quantity}
      end

      def validate(quantity, available) when quantity > available do
        {:error, :insufficient_stock}
      end

      def validate(_quantity, _available), do: :ok
    end
    """

    expected = """
    defmodule ShipStockValidator do
      def validate(quantity, available) when is_number(quantity) in [false, nil] or quantity <= 0 do
        {:error, :invalid_quantity}
      end

      def validate(quantity, available) when quantity > available do
        {:error, :insufficient_stock}
      end

      def validate(_quantity, _available), do: :ok
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule ShipStockValidator do
      def validate(quantity, available) when !is_number(quantity) or quantity <= 0 do
        {:error, :invalid_quantity}
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no ! in guard" do
    input = """
    defmodule CleanExample do
      def validate(quantity, available) when is_number(quantity), do: :ok
      def validate(_quantity, _available), do: :error
    end
    """

    confirm_fix(fix(input), input)
  end

  test "replaces ! in a multi-argument anonymous function guard" do
    input = """
    defmodule Example do
      def build do
        fn a, b when !is_nil(a) -> {a, b} end
      end
    end
    """

    expected = """
    defmodule Example do
      def build do
        fn a, b when is_nil(a) in [false, nil] -> {a, b} end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "replaces ! in chained guards" do
    input = """
    defmodule Example do
      def f(x) when !is_atom(x) when !is_list(x), do: x
    end
    """

    expected = """
    defmodule Example do
      def f(x) when is_atom(x) in [false, nil] when is_list(x) in [false, nil], do: x
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "replaces ! in a case clause guard" do
    input = """
    defmodule Example do
      def classify(x) do
        case x do
          v when !is_integer(v) -> :other
          v -> v
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def classify(x) do
        case x do
          v when is_integer(v) in [false, nil] -> :other
          v -> v
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "does not replace ! outside of guards" do
    input = """
    defmodule Example do
      def check(x) when !is_number(x), do: :error
      def negate(x), do: !x
    end
    """

    expected = """
    defmodule Example do
      def check(x) when is_number(x) in [false, nil], do: :error
      def negate(x), do: !x
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "preserves the truthiness semantics of ! for nil" do
    input = """
    defmodule FNIGTruthinessRegression do
      def classify(x) when !x, do: :falsy
      def classify(_), do: :truthy
    end
    unless FNIGTruthinessRegression.classify(nil) == :falsy, do: raise("nil changed meaning")
    """

    expected = """
    defmodule FNIGTruthinessRegression do
      def classify(x) when x in [false, nil], do: :falsy
      def classify(_), do: :truthy
    end

    unless FNIGTruthinessRegression.classify(nil) == :falsy, do: raise("nil changed meaning")
    """

    emitted = fix(input)
    confirm_fix(emitted, expected)
    assert {:ok, []} = RuleHelpers.compile_and_capture(emitted)
  end

  test "does not rewrite quoted guard data" do
    input = """
    defmodule FNIGQuotedDataRegression do
      def classify(x) when !is_atom(x), do: :other
      def quoted, do: quote(do: x when !x)
    end
    unless Macro.to_string(FNIGQuotedDataRegression.quoted()) == Macro.to_string(quote(do: x when !x)),
      do: raise("quote changed")
    """

    expected = """
    defmodule FNIGQuotedDataRegression do
      def classify(x) when is_atom(x) in [false, nil], do: :other
      def quoted, do: quote(do: x when !x)
    end

    unless Macro.to_string(FNIGQuotedDataRegression.quoted()) == Macro.to_string(quote(do: x when !x)),
      do: raise("quote changed")
    """

    emitted = fix(input)
    confirm_fix(emitted, expected)
    assert {:ok, []} = RuleHelpers.compile_and_capture(emitted)
  end

  test "real compiler diagnostic is dispatched and repaired by the Semantic pipeline" do
    input = """
    defmodule FNIGPipelineRegression do
      def classify(x) when !is_atom(x), do: :other
    end
    """

    expected = """
    defmodule FNIGPipelineRegression do
      def classify(x) when is_atom(x) in [false, nil], do: :other
    end
    """

    assert {:error, diagnostics} = RuleHelpers.compile_and_capture(input)
    assert Enum.any?(diagnostics, &FixNegationInGuard.match?/1)

    {emitted, applied} = Credence.Semantic.fix_with_trace(input)
    confirm_fix(emitted, String.trim_trailing(expected))
    assert applied == [{FixNegationInGuard, 1}]
    assert {:ok, []} = RuleHelpers.compile_and_capture(emitted)
  end
end
