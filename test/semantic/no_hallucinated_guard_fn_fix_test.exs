defmodule Credence.Semantic.NoHallucinatedGuardFnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedGuardFn

  @real_message "cannot find or invoke local is_regex/1 inside a guard. Only macros can be invoked inside a guard and they must be defined before their invocation. Called as: is_regex(format)"

  defp fix(source, message, position \\ {2, 33}) do
    NoHallucinatedGuardFn.fix(source, %{severity: :error, message: message, position: position})
  end

  test "replaces is_regex with is_struct(Regex) in guard" do
    input = """
    defmodule Demo do
      def check(value, format) when is_regex(format) do
        Regex.match?(format, value)
      end

      def check(_value, _format), do: false
    end
    """

    expected = """
    defmodule Demo do
      def check(value, format) when is_struct(format, Regex) do
        Regex.match?(format, value)
      end

      def check(_value, _format), do: false
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Demo do
      def check(value, format) when is_regex(format) do
        Regex.match?(format, value)
      end

      def check(_value, _format), do: false
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no is_regex present" do
    input = """
    defmodule CleanExample do
      def check(value, format) when is_binary(format) do
        Regex.match?(format, value)
      end
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

  test "leaves a bare `is_regex` variable untouched (no arity-1 call)" do
    input = """
    defmodule Demo do
      def check(is_regex) do
        is_regex
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "leaves a non-arity-1 is_regex call untouched" do
    input = """
    defmodule Demo do
      def check(a, b) do
        is_regex(a, b)
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "rewrites only the is_regex call identified by the diagnostic" do
    input = """
    defmodule NoHallucinatedGuardFnScopeFixture do
      def check(value) when is_regex(value), do: true
      def quoted(value), do: quote(do: is_regex(value))
      def ordinary(value), do: is_regex(value)
    end
    """

    expected = """
    defmodule NoHallucinatedGuardFnScopeFixture do
      def check(value) when is_struct(value, Regex), do: true
      def quoted(value), do: quote(do: is_regex(value))
      def ordinary(value), do: is_regex(value)
    end
    """

    assert {:error, diagnostics} = Credence.RuleHelpers.compile_and_capture(input)
    diagnostic = Enum.find(diagnostics, &NoHallucinatedGuardFn.match?/1)
    confirm_fix(NoHallucinatedGuardFn.fix(input, diagnostic), expected)
  end

  test "repairs the real compiler diagnostic through semantic dispatch" do
    input = """
    defmodule NoHallucinatedGuardFnPipelineFixture do
      def check(value, format) when is_regex(format) do
        Regex.match?(format, value)
      end

      def check(_value, _format), do: false
    end
    """

    expected = """
    defmodule NoHallucinatedGuardFnPipelineFixture do
      def check(value, format) when is_struct(format, Regex) do
        Regex.match?(format, value)
      end

      def check(_value, _format), do: false
    end
    """

    assert {:error, diagnostics} = Credence.RuleHelpers.compile_and_capture(input)
    assert Enum.any?(diagnostics, &NoHallucinatedGuardFn.match?/1)

    emitted = Credence.Semantic.fix(input)
    confirm_fix(emitted, expected)

    assert Credence.RuleHelpers.compile_and_capture(emitted) ==
             Credence.RuleHelpers.compile_and_capture(expected)
  end
end
