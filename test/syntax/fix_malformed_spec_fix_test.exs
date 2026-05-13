defmodule Credence.Syntax.FixMalformedSpecFixTest do
  use ExUnit.Case

  defp analyze(code) do
    Credence.Syntax.FixMalformedSpec.analyze(code)
  end

  defp fix(code) do
    Credence.Syntax.FixMalformedSpec.fix(code)
  end

  # ── simple types ───────────────────────────────────────────────

  describe "simple types" do
    test "single param, simple return" do
      assert fix("@spec foo(integer() :: string())") ==
               "@spec foo(integer()) :: string()"
    end

    test "atom return type" do
      assert fix("@spec foo(binary() :: atom())") ==
               "@spec foo(binary()) :: atom()"
    end

    test "boolean return" do
      assert fix("@spec valid?(string() :: boolean())") ==
               "@spec valid?(string()) :: boolean()"
    end

    test "bang function" do
      assert fix("@spec save!(map() :: :ok)") ==
               "@spec save!(map()) :: :ok"
    end
  end

  # ── parameterized types ────────────────────────────────────────

  describe "parameterized types" do
    test "the actual LLM log case" do
      assert fix("@spec max_product(list(integer()) :: integer())") ==
               "@spec max_product(list(integer())) :: integer()"
    end

    test "nested parameterized types" do
      assert fix("@spec process(list(list(integer())) :: list(integer()))") ==
               "@spec process(list(list(integer()))) :: list(integer())"
    end

    test "map type in params" do
      assert fix("@spec foo(map(atom(), string()) :: list())") ==
               "@spec foo(map(atom(), string())) :: list()"
    end
  end

  # ── multiple params ────────────────────────────────────────────

  describe "multiple params" do
    test "two simple params" do
      assert fix("@spec add(integer(), integer() :: integer())") ==
               "@spec add(integer(), integer()) :: integer()"
    end

    test "mixed simple and parameterized" do
      assert fix("@spec find(list(integer()), integer() :: integer())") ==
               "@spec find(list(integer()), integer()) :: integer()"
    end
  end

  # ── complex return types ───────────────────────────────────────

  describe "complex return types" do
    test "tuple return" do
      assert fix("@spec foo(integer() :: {atom(), integer()})") ==
               "@spec foo(integer()) :: {atom(), integer()}"
    end

    test "union return type" do
      assert fix("@spec foo(string() :: :ok | :error)") ==
               "@spec foo(string()) :: :ok | :error"
    end

    test "tagged tuple union return" do
      assert fix("@spec foo(integer() :: {:ok, term()} | {:error, string()})") ==
               "@spec foo(integer()) :: {:ok, term()} | {:error, string()}"
    end

    test "list return type" do
      assert fix("@spec foo(list() :: list(integer()))") ==
               "@spec foo(list()) :: list(integer())"
    end
  end

  # ── with indentation ───────────────────────────────────────────

  describe "with indentation" do
    test "preserves leading whitespace" do
      assert fix("  @spec foo(integer() :: string())") ==
               "  @spec foo(integer()) :: string()"
    end

    test "deep indentation" do
      assert fix("      @spec foo(integer() :: atom())") ==
               "      @spec foo(integer()) :: atom()"
    end
  end

  # ── realistic context ──────────────────────────────────────────

  describe "realistic context" do
    test "preserves surrounding code" do
      code = """
      defmodule MaxProduct do
        @spec max_product(list(integer()) :: integer())
        def max_product(numbers) do
          Enum.max(numbers)
        end
      end
      """

      expected = """
      defmodule MaxProduct do
        @spec max_product(list(integer())) :: integer()
        def max_product(numbers) do
          Enum.max(numbers)
        end
      end
      """

      assert fix(code) == expected
    end

    test "fixes multiple malformed specs in same module" do
      code = """
      @spec foo(integer() :: string())
      @spec bar(list() :: map())
      """

      expected = """
      @spec foo(integer()) :: string()
      @spec bar(list()) :: map()
      """

      assert fix(code) == expected
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "correct spec unchanged" do
      code = "@spec foo(integer()) :: string()"
      assert fix(code) == code
    end

    test "correct spec with multiple params" do
      code = "@spec add(integer(), integer()) :: integer()"
      assert fix(code) == code
    end

    test "named parameter unchanged" do
      code = "@spec foo(name :: integer()) :: string()"
      assert fix(code) == code
    end

    test "multiple named params unchanged" do
      code = "@spec foo(x :: integer(), y :: string()) :: atom()"
      assert fix(code) == code
    end

    test "no spec at all" do
      code = "def foo(x), do: x + 1"
      assert fix(code) == code
    end

    test "type definition unchanged" do
      code = "@type t :: %{name: String.t()}"
      assert fix(code) == code
    end
  end

  # ── round-trip ─────────────────────────────────────────────────

  describe "round-trip" do
    test "fixed spec produces zero analyze issues" do
      code = """
      @spec max_product(list(integer()) :: integer())
      @spec add(integer(), integer() :: integer())
      """

      assert analyze(fix(code)) == []
    end
  end
end
