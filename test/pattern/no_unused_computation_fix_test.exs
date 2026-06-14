defmodule Credence.Pattern.NoUnusedComputationFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoUnusedComputation

  # ── positive fix cases ──────────────────────────────────────────────

  test "removes _n = length(chars)" do
    input = """
    defmodule Example do
      @spec process(String.t()) :: map()
      def process(s) do
        chars = String.graphemes(s)
        _n = length(chars)

        chars
        |> Enum.with_index()
        |> Enum.into(%{}, fn {char, idx} -> {char, idx} end)
      end
    end
    """

    expected = """
    defmodule Example do
      @spec process(String.t()) :: map()
      def process(s) do
        chars = String.graphemes(s)

        chars
        |> Enum.with_index()
        |> Enum.into(%{}, fn {char, idx} -> {char, idx} end)
      end
    end
    """

    confirm_fix(fix(NoUnusedComputation, input), expected)
  end

  test "removes _count = String.length(s)" do
    input = """
    defmodule Fix do
      def run(s) do
        _count = String.length(s)
        String.upcase(s)
      end
    end
    """

    expected = """
    defmodule Fix do
      def run(s) do
        String.upcase(s)
      end
    end
    """

    confirm_fix(fix(NoUnusedComputation, input), expected)
  end

  test "removes bare _ = length(list)" do
    input = """
    defmodule Fix do
      def process(list) do
        _ = length(list)
        Enum.reverse(list)
      end
    end
    """

    expected = """
    defmodule Fix do
      def process(list) do
        Enum.reverse(list)
      end
    end
    """

    confirm_fix(fix(NoUnusedComputation, input), expected)
  end

  test "removes multiple dead assignments" do
    input = """
    defmodule Fix do
      def process(list) do
        _n = length(list)
        _rev = Enum.reverse(list)
        Enum.sort(list)
      end
    end
    """

    expected = """
    defmodule Fix do
      def process(list) do
        Enum.sort(list)
      end
    end
    """

    confirm_fix(fix(NoUnusedComputation, input), expected)
  end

  test "preserves dead assignment that is the last expression" do
    code = """
    defmodule Fix do
      def process(list) do
        _n = length(list)
      end
    end
    """

    confirm_fix(fix(NoUnusedComputation, code), code)
  end

  # ── negative fix cases (unchanged) ─────────────────────────────────

  test "does not change used variable assignment" do
    code = """
    defmodule Clean do
      def process(list) do
        n = length(list)
        n + 1
      end
    end
    """

    confirm_fix(fix(NoUnusedComputation, code), code)
  end

  test "does not change impure call (IO.puts)" do
    code = """
    defmodule Clean do
      def run do
        _n = IO.puts("hello")
        :ok
      end
    end
    """

    confirm_fix(fix(NoUnusedComputation, code), code)
  end

  test "does not change unknown function call" do
    code = """
    defmodule Clean do
      def run(x) do
        _n = some_unknown_function(x)
        :ok
      end
    end
    """

    confirm_fix(fix(NoUnusedComputation, code), code)
  end

  test "idempotent: running fix twice produces same result" do
    input = """
    defmodule Example do
      def process(s) do
        chars = String.graphemes(s)
        _n = length(chars)

        chars
        |> Enum.with_index()
        |> Enum.into(%{}, fn {char, idx} -> {char, idx} end)
      end
    end
    """

    once = fix(NoUnusedComputation, input)
    twice = fix(NoUnusedComputation, once)
    confirm_fix(once, twice)
  end
end
