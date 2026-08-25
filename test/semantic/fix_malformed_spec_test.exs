defmodule Credence.Semantic.FixMalformedSpecTest do
  @moduledoc """
  This rule was `Credence.Syntax.FixMalformedSpec` and could never fire: its
  moduledoc claimed "## Bad (won't parse)", but `@spec f(a :: b)` *parses* —
  `::` is an ordinary right-associative binary operator, so it is a well-formed
  call argument — and the Syntax phase only runs on source that fails to parse.
  The T1 pipeline-witness gate caught it; docs/22 T3.8 is the disposition.

  The failure mode is real. The line parses and then fails to **compile**, with a
  precise `:error` diagnostic that no live rule claimed:

      type specification missing return type: max_product(list(integer()) :: integer())

  So these tests are the receipts that the failure mode survived the move: the
  rewrite is byte-identical to the retired rule's, and it now runs where the
  compiler can reach it.
  """
  use ExUnit.Case, async: true

  import Credence.RuleCase, only: [confirm_fix: 2, compiles?: 1, valid_syntax?: 1]

  alias Credence.RuleHelpers
  alias Credence.Semantic.FixMalformedSpec

  # The rule takes the diagnostic the compiler really emits, not a hand-written
  # map. A fabricated `%{message:, severity:}` is exactly what T1 was built to
  # stop passing for evidence (docs/22 Part I §2, the G1 class).
  defp diagnose(source) do
    case RuleHelpers.compile_and_capture(source) do
      {:ok, ds} -> ds
      {:error, ds} -> ds
    end
  end

  defp only_diagnostic(source) do
    [d] = Enum.filter(diagnose(source), &FixMalformedSpec.match?/1)
    d
  end

  describe "match?/1 — keyed on the real diagnostic" do
    test "matches the compiler's missing-return-type error" do
      source = """
      defmodule MalformedSpecMatch do
        @spec max_product(list(integer()) :: integer())
        def max_product(l), do: Enum.max(l)
      end
      """

      assert [d] = Enum.filter(diagnose(source), &FixMalformedSpec.match?/1)
      assert d.severity == :error
      assert d.message =~ "type specification missing return type:"
    end

    test "a valid named-argument spec produces no diagnostic at all" do
      source = """
      defmodule MalformedSpecNamedOk do
        @spec add(count :: integer(), other :: integer()) :: integer()
        def add(a, b), do: a + b
      end
      """

      assert diagnose(source) == []
    end

    test "does not match an unrelated diagnostic" do
      refute FixMalformedSpec.match?(%{
               message: "unknown key :message for struct Jason.DecodeError",
               position: 1,
               severity: :error
             })
    end
  end

  describe "to_issue/1" do
    # The atom is module-derived, not author-chosen, because that is how the T1
    # witness gate attributes an issue back to its rule. Carrying the old Syntax
    # atom `:malformed_spec` across the phase boundary made this rule
    # unattributable, and T1 went red on exactly that.
    test "pins the issue attribution" do
      issue = FixMalformedSpec.to_issue(%{message: "m", position: 7})

      assert issue.rule == :fix_malformed_spec
      assert issue.meta == %{line: 7}
    end
  end

  describe "fix/2" do
    test "moves the separator out of the argument parens" do
      source = """
      defmodule MalformedSpecFixA do
        @spec max_product(list(integer()) :: integer())
        def max_product(l), do: Enum.max(l)
      end
      """

      expected = """
      defmodule MalformedSpecFixA do
        @spec max_product(list(integer())) :: integer()
        def max_product(l), do: Enum.max(l)
      end
      """

      confirm_fix(FixMalformedSpec.fix(source, only_diagnostic(source)), expected)
    end

    test "handles a multi-argument spec, splitting at the LAST top-level ::" do
      source = """
      defmodule MalformedSpecFixB do
        @spec merge(map(), map() :: {:ok, map()})
        def merge(a, b), do: {:ok, Map.merge(a, b)}
      end
      """

      expected = """
      defmodule MalformedSpecFixB do
        @spec merge(map(), map()) :: {:ok, map()}
        def merge(a, b), do: {:ok, Map.merge(a, b)}
      end
      """

      confirm_fix(FixMalformedSpec.fix(source, only_diagnostic(source)), expected)
    end

    test "preserves a bang in the function name" do
      source = """
      defmodule MalformedSpecFixC do
        @spec save!(map() :: {:ok, map()})
        def save!(m), do: {:ok, m}
      end
      """

      expected = """
      defmodule MalformedSpecFixC do
        @spec save!(map()) :: {:ok, map()}
        def save!(m), do: {:ok, m}
      end
      """

      confirm_fix(FixMalformedSpec.fix(source, only_diagnostic(source)), expected)
    end

    test "the output compiles, which the input did not" do
      source = """
      defmodule MalformedSpecCompiles do
        @spec max_product(list(integer()) :: integer())
        def max_product(l), do: Enum.max(l)
      end
      """

      refute compiles?(source)
      assert compiles?(FixMalformedSpec.fix(source, only_diagnostic(source)))
    end

    test "the output is well-formed (parses)" do
      # Weaker than `compiles?/1` above and asserted anyway: the Semantic
      # meta-gate requires this one by name, because a fix whose output does not
      # parse takes the whole file down with it.
      source = """
      defmodule MalformedSpecWellFormed do
        @spec merge(map(), map() :: {:ok, map()})
        def merge(a, b), do: {:ok, Map.merge(a, b)}
      end
      """

      assert valid_syntax?(FixMalformedSpec.fix(source, only_diagnostic(source)))
    end

    test "declines a line that already has a return type outside the parens" do
      # Belt and braces: this shape cannot produce the diagnostic, so the rule
      # is never handed it in the pipeline. Fed by hand it must still no-op.
      source = """
      defmodule MalformedSpecDecline do
        @spec add(count :: integer()) :: integer()
        def add(a), do: a
      end
      """

      diagnostic = %{message: "type specification missing return type: x", position: 2}

      confirm_fix(FixMalformedSpec.fix(source, diagnostic), source)
    end

    test "declines a named argument when the spec omits its return type" do
      source = """
      defmodule MalformedSpecNamedMissingReturn do
        @spec f(count :: integer())
        def f(x), do: x
      end
      """

      confirm_fix(FixMalformedSpec.fix(source, only_diagnostic(source)), source)
    end

    test "preserves everything after the spec's closing parenthesis" do
      comment_source = """
      defmodule MalformedSpecTrailingComment do
        @spec f(integer() :: atom()) # important
        def f(x), do: x
      end
      """

      comment_expected = """
      defmodule MalformedSpecTrailingComment do
        @spec f(integer()) :: atom() # important
        def f(x), do: x
      end
      """

      semicolon_source = """
      defmodule MalformedSpecTrailingCode do
        @spec f(integer() :: atom()); def marker, do: :ok
        def f(x), do: x
      end
      """

      semicolon_expected = """
      defmodule MalformedSpecTrailingCode do
        @spec f(integer()) :: atom(); def marker, do: :ok
        def f(x), do: x
      end
      """

      confirm_fix(
        FixMalformedSpec.fix(comment_source, only_diagnostic(comment_source)),
        comment_expected
      )

      confirm_fix(
        FixMalformedSpec.fix(semicolon_source, only_diagnostic(semicolon_source)),
        semicolon_expected
      )
    end

    test "a position pointing at a non-@spec line is a no-op, not a crash" do
      source = """
      defmodule M do
        def f(x), do: x
      end
      """

      diagnostic = %{message: "type specification missing return type: x", position: 2}

      confirm_fix(FixMalformedSpec.fix(source, diagnostic), source)
    end

    test "a position past the end of the file is a no-op, not a crash" do
      source = """
      defmodule M do
      end
      """

      diagnostic = %{message: "type specification missing return type: x", position: 99}

      confirm_fix(FixMalformedSpec.fix(source, diagnostic), source)
    end

    test "accepts a {line, col} position as well as a bare line" do
      source = """
      defmodule MalformedSpecTuplePos do
        @spec f(integer() :: atom())
        def f(x), do: x
      end
      """

      expected = """
      defmodule MalformedSpecTuplePos do
        @spec f(integer()) :: atom()
        def f(x), do: x
      end
      """

      confirm_fix(FixMalformedSpec.fix(source, %{message: "m", position: {2, 3}}), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # THE POINT OF THE RE-HOME — it fires through the real pipeline now,
  # which is precisely what it could never do in the Syntax phase.
  # ═══════════════════════════════════════════════════════════════════

  describe "end-to-end through Credence" do
    test "the malformed spec is repaired through real dispatch" do
      source = """
      defmodule MalformedSpecInteg do
        @spec max_product(list(integer()) :: integer())
        def max_product(l), do: Enum.max(l)
      end
      """

      result = Credence.fix(source)

      expected = """
      defmodule MalformedSpecInteg do
        @spec max_product(list(integer())) :: integer()
        def max_product(l), do: Enum.max(l)
      end
      """

      assert {FixMalformedSpec, 1} in result.applied_rules
      assert result.code == expected
      assert compiles?(result.code)
    end

    test "a valid spec is left alone through real dispatch" do
      source = """
      defmodule MalformedSpecIntegOk do
        @spec add(count :: integer(), other :: integer()) :: integer()
        def add(a, b), do: a + b
      end
      """

      assert Credence.fix(source).code == source
      assert Credence.analyze(source).issues == []
    end

    test "the input parses — which is why this could never be a Syntax rule" do
      source = """
      defmodule MalformedSpecParses do
        @spec max_product(list(integer()) :: integer())
        def max_product(l), do: Enum.max(l)
      end
      """

      assert valid_syntax?(source)
      refute compiles?(source)
    end
  end
end
