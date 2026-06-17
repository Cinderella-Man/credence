defmodule Credence.Syntax.PreferSpecArrowOperatorFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.PreferSpecArrowOperator

  defp analyze(code), do: PreferSpecArrowOperator.analyze(code)
  defp fix(code), do: PreferSpecArrowOperator.fix(code)

  # ── fixes missing arrow ──────────────────────────────────────────

  describe "inserts :: before return type" do
    test "the LLM pattern from the rationale" do
      input = "@spec get_days_between_dates(String.t(), String.t()) integer()"
      expected = "@spec get_days_between_dates(String.t(), String.t()) :: integer()"
      confirm_fix(fix(input), expected)
    end

    test "single param" do
      confirm_fix(fix("@spec foo(integer()) string()"), "@spec foo(integer()) :: string()")
    end

    test "module return type" do
      confirm_fix(fix("@spec bar(String.t()) Map.t()"), "@spec bar(String.t()) :: Map.t()")
    end

    test "tuple return type" do
      confirm_fix(
        fix("@spec baz(integer()) {:ok, term()}"),
        "@spec baz(integer()) :: {:ok, term()}"
      )
    end

    test "atom literal return" do
      confirm_fix(fix("@spec qux(string()) :ok"), "@spec qux(string()) :: :ok")
    end

    test "function name with ?" do
      confirm_fix(
        fix("@spec valid?(string()) boolean()"),
        "@spec valid?(string()) :: boolean()"
      )
    end

    test "function name with !" do
      confirm_fix(fix("@spec save!(map()) :ok"), "@spec save!(map()) :: :ok")
    end

    test "preserves leading whitespace" do
      confirm_fix(fix("  @spec foo(integer()) string()"), "  @spec foo(integer()) :: string()")
    end

    test "complex return type with union" do
      confirm_fix(
        fix("@spec foo(integer()) {:ok, term()} | {:error, string()}"),
        "@spec foo(integer()) :: {:ok, term()} | {:error, string()}"
      )
    end

    test "list return type" do
      confirm_fix(
        fix("@spec bar(string()) list(integer())"),
        "@spec bar(string()) :: list(integer())"
      )
    end
  end

  # ── realistic context ────────────────────────────────────────────

  describe "realistic context" do
    test "preserves surrounding code" do
      code = """
      defmodule Fix do
        @spec get_days_between_dates(String.t(), String.t()) integer()
        def get_days_between_dates(a, b), do: :ok
      end
      """

      expected = """
      defmodule Fix do
        @spec get_days_between_dates(String.t(), String.t()) :: integer()
        def get_days_between_dates(a, b), do: :ok
      end
      """

      confirm_fix(fix(code), expected)
    end

    test "fixes multiple missing-arrow specs in same module" do
      code = """
      @spec foo(integer()) string()
      @spec bar(list()) map()
      """

      expected = """
      @spec foo(integer()) :: string()
      @spec bar(list()) :: map()
      """

      confirm_fix(fix(code), expected)
    end
  end

  # ── no-ops ───────────────────────────────────────────────────────

  describe "no-ops" do
    test "correct spec unchanged" do
      code = "@spec foo(integer()) :: string()"
      confirm_fix(fix(code), code)
    end

    test "correct spec with multiple params" do
      code = "@spec add(integer(), integer()) :: integer()"
      confirm_fix(fix(code), code)
    end

    test "spec with no return type unchanged" do
      code = "@spec foo(integer())"
      confirm_fix(fix(code), code)
    end

    test "spec with guard unchanged" do
      code = "@spec foo(integer()) when is_integer(x) :: string()"
      confirm_fix(fix(code), code)
    end

    test "no spec at all" do
      code = "def foo(x), do: x + 1"
      confirm_fix(fix(code), code)
    end

    test "type definition unchanged" do
      code = "@type t :: %{name: String.t()}"
      confirm_fix(fix(code), code)
    end
  end

  # ── round-trip ───────────────────────────────────────────────────

  describe "round-trip" do
    test "fixed spec produces zero analyze issues" do
      code = """
      @spec get_days_between_dates(String.t(), String.t()) integer()
      @spec add(integer(), integer()) string()
      """

      assert analyze(fix(code)) == []
    end
  end

  describe "fix output is well-formed" do
    test "fixed output parses" do
      assert valid_syntax?(fix("@spec foo(integer()) string()"))
    end

    test "fixed output in context parses" do
      code = """
      defmodule Fix do
        @spec get_days_between_dates(String.t(), String.t()) integer()
        def get_days_between_dates(a, b), do: :ok
      end
      """

      assert valid_syntax?(fix(code))
    end
  end
end
