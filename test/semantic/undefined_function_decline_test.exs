defmodule Credence.Semantic.UndefinedFunctionDeclineTest do
  use ExUnit.Case, async: true

  alias Credence.Semantic.UndefinedFunction

  @moduledoc """
  docs/22 T3.6, escalation ledger row 296 — the catch-all claimed diagnostics it
  could not repair.

  `match?/1` accepts every `undefined function …` message, but the repair is a
  lookup in the replacement tables. A call the tables have never heard of — a
  `Plug` import missing from the file, say — matched, returned the source
  byte-identical, and the row was reported against a rule that had done nothing.
  """

  defp diag(msg, severity \\ :error) do
    %{severity: severity, message: msg, position: 3, file: "x.ex"}
  end

  describe "should_report?/2" do
    test "declines a call the replacement tables do not cover" do
      source = """
      defmodule NotificationPoller do
        def run(conn) do
          send_resp(conn, 200, "ok")
        end
      end
      """

      d =
        diag(
          "undefined function send_resp/2 (expected NotificationPoller to define such a function)"
        )

      refute UndefinedFunction.should_report?(d, source)
    end

    test "reports a call it can repair" do
      source = """
      defmodule M do
        def run(list) do
          len(list)
        end
      end
      """

      d = diag("undefined function len/1 (expected M to define such a function)")

      assert UndefinedFunction.should_report?(d, source)
    end

    # The property that keeps the guard honest: it IS the fix, so it can never
    # disagree with what `fix/2` will do. A guard that approximates the fix is a
    # second implementation of the same decision, and drifts from it.
    test "the guard agrees with fix/2 by construction" do
      source = """
      defmodule M do
        def run(l), do: len(l)
      end
      """

      d = diag("undefined function len/1 (expected M to define such a function)")

      assert UndefinedFunction.should_report?(d, source) ==
               (UndefinedFunction.fix(source, d) != source)
    end
  end

  # The end-to-end consequence: an unfixable diagnostic must not surface as an
  # issue attributed to this rule.
  describe "through Semantic.analyze/2" do
    test "an uncovered undefined function yields no UndefinedFunction issue" do
      source = """
      defmodule DeclineProbe do
        def run(conn), do: send_resp(conn, 200, "ok")
      end
      """

      issues = Credence.Semantic.analyze(source)

      refute Enum.any?(issues, &(&1.rule == :undefined_function))
    end
  end
end
