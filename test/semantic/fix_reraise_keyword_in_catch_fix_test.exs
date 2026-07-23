defmodule Credence.Semantic.FixReraiseKeywordInCatchFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixReraiseKeywordInCatch

  defp fix(source, line \\ 1) do
    FixReraiseKeywordInCatch.fix(source, %{
      severity: :error,
      message: "undefined variable \"reraise\"",
      position: {line, 1}
    })
  end

  test "replaces bare reraise, keeping a literal :error kind as the raise argument" do
    input =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            :error, reason ->
              reraise
          end
        end
      end
      """

    expected =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            :error, reason ->
              :erlang.raise(:error, reason, __STACKTRACE__)
          end
        end
      end
      """

    confirm_fix(fix(input), expected)
  end

  test "multi-clause catch keeps each clause's own kind pattern and dispatch" do
    input =
      """
      defmodule M do
        def risky_call do
          try do
            :ok
          catch
            :error, reason ->
              Process.delete(:key)
              reraise
            :exit, reason ->
              reraise
          end
        end
      end
      """

    expected =
      """
      defmodule M do
        def risky_call do
          try do
            :ok
          catch
            :error, reason ->
              Process.delete(:key)
              :erlang.raise(:error, reason, __STACKTRACE__)

            :exit, reason ->
              :erlang.raise(:exit, reason, __STACKTRACE__)
          end
        end
      end
      """

    confirm_fix(fix(input), expected)
  end

  test "reuses a variable kind pattern as-is" do
    input =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            kind, reason ->
              reraise
          end
        end
      end
      """

    expected =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            kind, reason ->
              :erlang.raise(kind, reason, __STACKTRACE__)
          end
        end
      end
      """

    confirm_fix(fix(input), expected)
  end

  test "single-pattern clause (throw shorthand) re-raises with kind :throw" do
    input =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            value ->
              reraise
          end
        end
      end
      """

    expected =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            value ->
              :erlang.raise(:throw, value, __STACKTRACE__)
          end
        end
      end
      """

    confirm_fix(fix(input), expected)
  end

  test "literal atom reason is passed through as the same literal" do
    input =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            :exit, :normal ->
              reraise
          end
        end
      end
      """

    expected =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            :exit, :normal ->
              :erlang.raise(:exit, :normal, __STACKTRACE__)
          end
        end
      end
      """

    confirm_fix(fix(input), expected)
  end

  test "replaces bare reraise nested in an if inside the clause body" do
    input =
      """
      defmodule M do
        def f(x) do
          try do
            :ok
          catch
            :error, reason ->
              if x do
                :swallowed
              else
                reraise
              end
          end
        end
      end
      """

    expected =
      """
      defmodule M do
        def f(x) do
          try do
            :ok
          catch
            :error, reason ->
              if x do
                :swallowed
              else
                :erlang.raise(:error, reason, __STACKTRACE__)
              end
          end
        end
      end
      """

    confirm_fix(fix(input), expected)
  end

  test "bare reraise in a nested try's catch uses the inner clause's bindings" do
    input =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            :error, outer ->
              try do
                cleanup(outer)
              catch
                :exit, inner ->
                  reraise
              end
          end
        end
      end
      """

    expected =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            :error, outer ->
              try do
                cleanup(outer)
              catch
                :exit, inner ->
                  :erlang.raise(:exit, inner, __STACKTRACE__)
              end
          end
        end
      end
      """

    confirm_fix(fix(input), expected)
  end

  test "no fix for a clause with a guard (head cannot be read back safely)" do
    input =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            kind, reason when is_atom(reason) ->
              reraise
          end
        end
      end
      """

    confirm_fix(fix(input), input)
  end

  test "no fix for a composite reason pattern" do
    input =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            :error, {:badmatch, value} ->
              reraise
          end
        end
      end
      """

    confirm_fix(fix(input), input)
  end

  test "no fix for underscore patterns (bindings cannot be referenced)" do
    input =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            _, _reason ->
              reraise
          end
        end
      end
      """

    confirm_fix(fix(input), input)
  end

  test "no fix for bare reraise in a rescue clause" do
    input =
      """
      defmodule M do
        def f do
          try do
            :ok
          rescue
            e ->
              reraise
          end
        end
      end
      """

    confirm_fix(fix(input), input)
  end

  test "leaves a proper reraise/2 call in a catch clause untouched" do
    input =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            kind, reason ->
              reraise RuntimeError, __STACKTRACE__
          end
        end
      end
      """

    confirm_fix(fix(input), input)
  end

  test "no fix when the bare reraise is not inside a try/catch" do
    input =
      """
      defmodule M do
        def f do
          reraise
        end
      end
      """

    confirm_fix(fix(input), input)
  end

  test "fixed output is well-formed (parses)" do
    input =
      """
      defmodule M do
        def f do
          try do
            :ok
          catch
            :error, reason ->
              reraise
          end
        end
      end
      """

    assert valid_syntax?(fix(input))
  end

  test "end-to-end: the semantic phase dispatches the diagnostic to this rule" do
    input =
      """
      defmodule FixReraiseKeywordInCatchE2E do
        def f do
          try do
            :ok
          catch
            :error, reason ->
              reraise
          end
        end
      end
      """

    expected =
      """
      defmodule FixReraiseKeywordInCatchE2E do
        def f do
          try do
            :ok
          catch
            :error, reason ->
              :erlang.raise(:error, reason, __STACKTRACE__)
          end
        end
      end
      """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end
end
