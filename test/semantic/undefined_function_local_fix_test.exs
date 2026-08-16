defmodule Credence.Semantic.UndefinedFunction.LocalFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.UndefinedFunction
  alias Local

  defp fix(source, message, line \\ 1) do
    UndefinedFunction.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  defp msg(name, arity) do
    "undefined function #{name}/#{arity} (expected MyModule to define such a function or for it to be imported, but none are available)"
  end

  # ── infinity ───────────────────────────────────────────────────

  describe "infinity() → :math.inf()" do
    test "standalone call" do
      confirm_fix(
        fix(
          "infinity()",
          msg("infinity", 0)
        ),
        ":math.inf()"
      )
    end

    test "negated" do
      confirm_fix(
        fix(
          "-infinity()",
          msg("infinity", 0)
        ),
        "-:math.inf()"
      )
    end

    test "in a tuple" do
      confirm_fix(
        fix(
          "{-infinity(), -infinity()}",
          msg("infinity", 0)
        ),
        "{-:math.inf(), -:math.inf()}"
      )
    end

    test "in Enum.reduce accumulator" do
      input = "Enum.reduce(nums, {-infinity(), -infinity()}, fn x, acc -> x end)"

      confirm_fix(
        fix(input, msg("infinity", 0)),
        "Enum.reduce(nums, {-:math.inf(), -:math.inf()}, fn x, acc -> x end)"
      )
    end

    test "only on reported line" do
      input = """
      x = infinity()
      y = infinity()
      """

      confirm_fix(fix(input, msg("infinity", 0), 2), """
      x = infinity()
      y = :math.inf()
      """)
    end
  end

  # ── max/1 rename ───────────────────────────────────────────────

  describe "max/1 → Enum.max(list)" do
    test "with list literal" do
      confirm_fix(
        fix(
          "max([option1, option2])",
          msg("max", 1)
        ),
        "Enum.max([option1, option2])"
      )
    end

    test "with variable" do
      confirm_fix(
        fix(
          "max(values)",
          msg("max", 1)
        ),
        "Enum.max(values)"
      )
    end

    test "in assignment" do
      confirm_fix(
        fix(
          "result = max([a, b, c])",
          msg("max", 1)
        ),
        "result = Enum.max([a, b, c])"
      )
    end

    test "realistic context from LLM log" do
      code =
        """
            option1 = List.last(sorted) * Enum.at(sorted, -2) * Enum.at(sorted, -3)
            option2 = List.first(sorted) * Enum.at(sorted, -1) * List.last(sorted)

            max([option1, option2])
        """

      expected =
        """
            option1 = List.last(sorted) * Enum.at(sorted, -2) * Enum.at(sorted, -3)
            option2 = List.first(sorted) * Enum.at(sorted, -1) * List.last(sorted)

            Enum.max([option1, option2])
        """

      confirm_fix(fix(code, msg("max", 1), 4), expected)
    end

    test "only on reported line" do
      input = """
      x = max(a, b)
      y = max([option1, option2])
      """

      confirm_fix(fix(input, msg("max", 1), 2), """
      x = max(a, b)
      y = Enum.max([option1, option2])
      """)
    end
  end

  # ── max/3,4,5 wrap-args ────────────────────────────────────────

  describe "max/3 → Enum.max([a, b, c])" do
    test "three simple args" do
      confirm_fix(
        fix(
          "max(a, b, c)",
          msg("max", 3)
        ),
        "Enum.max([a, b, c])"
      )
    end

    test "in assignment" do
      confirm_fix(
        fix(
          "result = max(x, y, z)",
          msg("max", 3)
        ),
        "result = Enum.max([x, y, z])"
      )
    end

    test "with nested function call" do
      confirm_fix(
        fix(
          "max(foo(x), bar(y), z)",
          msg("max", 3)
        ),
        "Enum.max([foo(x), bar(y), z])"
      )
    end

    test "preserves inner Kernel.max/2" do
      confirm_fix(
        fix(
          "max(a, max(b, c), d)",
          msg("max", 3)
        ),
        "Enum.max([a, max(b, c), d])"
      )
    end
  end

  describe "max/4 → Enum.max([a, b, c, d])" do
    test "four simple args" do
      confirm_fix(
        fix(
          "max(a, b, c, d)",
          msg("max", 4)
        ),
        "Enum.max([a, b, c, d])"
      )
    end
  end

  describe "max/5 → Enum.max([a, b, c, d, e])" do
    test "five simple args" do
      confirm_fix(
        fix(
          "max(a, b, c, d, e)",
          msg("max", 5)
        ),
        "Enum.max([a, b, c, d, e])"
      )
    end
  end

  # ── min/1 rename ───────────────────────────────────────────────

  describe "min/1 → Enum.min(list)" do
    test "with list literal" do
      confirm_fix(
        fix(
          "min([a, b])",
          msg("min", 1)
        ),
        "Enum.min([a, b])"
      )
    end

    test "with variable" do
      confirm_fix(
        fix(
          "min(values)",
          msg("min", 1)
        ),
        "Enum.min(values)"
      )
    end

    test "in assignment" do
      confirm_fix(
        fix(
          "lowest = min([x, y, z])",
          msg("min", 1)
        ),
        "lowest = Enum.min([x, y, z])"
      )
    end
  end

  # ── min/3,4,5 wrap-args ────────────────────────────────────────

  describe "min/3 → Enum.min([a, b, c])" do
    test "three simple args" do
      confirm_fix(
        fix(
          "min(a, b, c)",
          msg("min", 3)
        ),
        "Enum.min([a, b, c])"
      )
    end

    test "with nested function call" do
      confirm_fix(
        fix(
          "min(foo(x), bar(y), z)",
          msg("min", 3)
        ),
        "Enum.min([foo(x), bar(y), z])"
      )
    end

    test "preserves inner Kernel.min/2" do
      confirm_fix(
        fix(
          "min(a, min(b, c), d)",
          msg("min", 3)
        ),
        "Enum.min([a, min(b, c), d])"
      )
    end
  end

  describe "min/4 → Enum.min([a, b, c, d])" do
    test "four simple args" do
      confirm_fix(
        fix(
          "min(a, b, c, d)",
          msg("min", 4)
        ),
        "Enum.min([a, b, c, d])"
      )
    end
  end

  describe "min/5 → Enum.min([a, b, c, d, e])" do
    test "five simple args" do
      confirm_fix(
        fix(
          "min(a, b, c, d, e)",
          msg("min", 5)
        ),
        "Enum.min([a, b, c, d, e])"
      )
    end
  end

  # ── Python built-ins ───────────────────────────────────────────

  describe "sum/1 → Enum.sum" do
    test "with variable" do
      confirm_fix(
        fix(
          "sum(numbers)",
          msg("sum", 1)
        ),
        "Enum.sum(numbers)"
      )
    end

    test "with list literal" do
      confirm_fix(
        fix(
          "sum([1, 2, 3])",
          msg("sum", 1)
        ),
        "Enum.sum([1, 2, 3])"
      )
    end

    test "in assignment" do
      confirm_fix(
        fix(
          "total = sum(values)",
          msg("sum", 1)
        ),
        "total = Enum.sum(values)"
      )
    end
  end

  describe "sorted/1 → Enum.sort" do
    test "with variable" do
      confirm_fix(
        fix(
          "sorted(numbers)",
          msg("sorted", 1)
        ),
        "Enum.sort(numbers)"
      )
    end

    test "in pipeline" do
      confirm_fix(
        fix(
          "result = sorted(items) |> Enum.take(5)",
          msg("sorted", 1)
        ),
        "result = Enum.sort(items) |> Enum.take(5)"
      )
    end
  end

  describe "len/1 → length" do
    test "with variable" do
      confirm_fix(
        fix(
          "len(items)",
          msg("len", 1)
        ),
        "length(items)"
      )
    end

    test "in comparison" do
      confirm_fix(
        fix(
          "if len(list) > 0, do: :ok",
          msg("len", 1)
        ),
        "if length(list) > 0, do: :ok"
      )
    end

    test "in assignment" do
      confirm_fix(
        fix(
          "n = len(words)",
          msg("len", 1)
        ),
        "n = length(words)"
      )
    end
  end

  describe "reversed/1 → Enum.reverse" do
    test "with variable" do
      confirm_fix(
        fix(
          "reversed(items)",
          msg("reversed", 1)
        ),
        "Enum.reverse(items)"
      )
    end

    test "in assignment" do
      confirm_fix(
        fix(
          "rev = reversed(list)",
          msg("reversed", 1)
        ),
        "rev = Enum.reverse(list)"
      )
    end
  end

  # ── double-replacement safety ──────────────────────────────────

  describe "double-replacement safety" do
    test "two max/1 on same line" do
      confirm_fix(
        fix(
          "max([a, b]) + max([c, d])",
          msg("max", 1)
        ),
        "Enum.max([a, b]) + Enum.max([c, d])"
      )
    end

    test "idempotent for max" do
      source = "max([a, b]) + max([c, d])"

      once = fix(source, msg("max", 1))
      twice = fix(once, msg("max", 1))

      confirm_fix(once, "Enum.max([a, b]) + Enum.max([c, d])")

      confirm_fix(twice, once)
    end

    test "two min/1 on same line" do
      confirm_fix(
        fix(
          "min([a, b]) + min([c, d])",
          msg("min", 1)
        ),
        "Enum.min([a, b]) + Enum.min([c, d])"
      )
    end

    test "idempotent for min" do
      source = "min(values)"

      once = fix(source, msg("min", 1))
      twice = fix(once, msg("min", 1))

      confirm_fix(once, "Enum.min(values)")

      confirm_fix(twice, once)
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "local: no-ops" do
    test "unknown local function unchanged" do
      source = "foobar()"

      confirm_fix(fix(source, msg("foobar", 0)), source)
    end

    test "max/2 not in replacements" do
      source = "max(a, b)"

      confirm_fix(fix(source, msg("max", 2)), source)
    end

    test "min/2 not in replacements" do
      source = "min(a, b)"

      confirm_fix(fix(source, msg("min", 2)), source)
    end
  end

  describe "fix output is well-formed" do
    test "fixed output parses" do
      assert valid_syntax?(
               fix(
                 "infinity()",
                 msg("infinity", 0)
               )
             )
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # Byte scope: the rewrite must not reach a same-named call that is not code.
  #
  # Found by probing rather than by reading. Every per-line replacement in this
  # rule used to run a plain `String.replace`/`Regex.replace` over the raw line,
  # so a call spelled the same way inside a string literal or a trailing comment
  # on that line was rewritten too. This is the T3.7/T3.10 byte-scope class, and
  # the self-corruption oracle could not have caught it here — that oracle runs
  # a rule's `fix/1` over its own source and only Syntax rules have one.
  # ────────────────────────────────────────────────────────────────────────

  describe "byte scope — literals and comments are not code" do
    test "a same-named call inside a string on the fixed line is left alone" do
      confirm_fix(
        fix(
          """
          defmodule M do
            def f(l), do: {len(l), "the helper len(x) is not real"}
          end
          """,
          msg("len", 1),
          2
        ),
        """
        defmodule M do
          def f(l), do: {length(l), "the helper len(x) is not real"}
        end
        """
      )
    end

    test "a same-named call in a trailing comment is left alone" do
      confirm_fix(
        fix(
          """
          defmodule M do
            def f(l), do: len(l)  # len(x) was the python spelling
          end
          """,
          msg("len", 1),
          2
        ),
        """
        defmodule M do
          def f(l), do: length(l)  # len(x) was the python spelling
        end
        """
      )
    end

    # This is the one that needs the FILE masked rather than the line. A
    # per-line edit never reaches another line, so a heredoc elsewhere was never
    # at risk; the real exposure is a diagnostic whose line number points INTO a
    # multi-line literal. Masked line-by-line, that line reads as ordinary code
    # and the docstring gets rewritten — the T3.7 `FixDivRem` defect exactly.
    test "a diagnostic pointing INTO a heredoc rewrites nothing" do
      source = ~S|defmodule M do
  @moduledoc """
  Call len(x) to measure it.
  """
  def f(l), do: length(l)
end
|

      confirm_fix(fix(source, msg("len", 1), 3), source)
    end

    # The control that keeps the guard honest: blinding the rewrite to literals
    # must not blind it to ordinary code.
    test "CONTROL: two real calls on one line are both still rewritten" do
      confirm_fix(
        fix(
          """
          defmodule M do
            def f(a, b), do: len(a) + len(b)
          end
          """,
          msg("len", 1),
          2
        ),
        """
        defmodule M do
          def f(a, b), do: length(a) + length(b)
        end
        """
      )
    end
  end

  # ── exit/2 -> Process.exit/2, and the arity check it needs (docs/16 4.6d) ──
  #
  # `Kernel.exit/1` is real and `exit/2` is the invention, so the two spellings
  # co-occur — which is why this row was deferred until the replacement could
  # tell them apart. The table key `{name, arity}` was never the problem; the
  # LINE-level replacement matched the name whatever the call's shape.

  describe "exit/2" do
    defp exit2(source, line \\ 2) do
      UndefinedFunction.fix(source, %{
        severity: :error,
        message:
          "undefined function exit/2 (expected M to define such a function or for it to be imported, but none are available)",
        position: {line, 1}
      })
    end

    test "qualifies the two-argument call" do
      confirm_fix(
        exit2("""
        defmodule ExitTwo do
          def f(p), do: exit(p, :kill)
        end
        """),
        """
        defmodule ExitTwo do
          def f(p), do: Process.exit(p, :kill)
        end
        """
      )
    end

    test "leaves a one-argument exit alone" do
      source = """
      defmodule ExitOne do
        def f, do: exit(:normal)
      end
      """

      confirm_fix(exit2(source), source)
    end

    # The discriminating case. Stopping at the first match would decline the
    # whole line, because the arity that does not match comes first.
    test "on a line holding both, only the two-argument call is qualified" do
      confirm_fix(
        exit2("""
        defmodule ExitBoth do
          def f(p), do: {exit(:normal), exit(p, :kill)}
        end
        """),
        """
        defmodule ExitBoth do
          def f(p), do: {exit(:normal), Process.exit(p, :kill)}
        end
        """
      )
    end

    # Arity is counted from top-level commas, so a comma inside the argument's
    # own brackets must not raise the count. The line may not parse at all —
    # the file has a compile error by construction — which is why this is a
    # scan and not a parse.
    test "commas nested inside an argument do not change the arity" do
      confirm_fix(
        exit2("""
        defmodule ExitNested do
          def f(p), do: exit(p, {:shutdown, [1, 2]})
        end
        """),
        """
        defmodule ExitNested do
          def f(p), do: Process.exit(p, {:shutdown, [1, 2]})
        end
        """
      )
    end

    test "a comma inside a string is not an argument separator" do
      confirm_fix(
        exit2("""
        defmodule ExitString do
          def f(p), do: exit(p, "a, b")
        end
        """),
        """
        defmodule ExitString do
          def f(p), do: Process.exit(p, "a, b")
        end
        """
      )
    end
  end
end
