defmodule Credence.Semantic.FixReraiseKeywordInCatchFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixReraiseKeywordInCatch

  defp fix(source, message, line \\ 1) do
    FixReraiseKeywordInCatch.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  @message "undefined variable \"reraise\""

  test "replaces bare reraise with :erlang.raise in single catch clause" do
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
            kind, reason ->
              :erlang.raise(kind, reason, __STACKTRACE__)
          end
        end
      end
      """

    confirm_fix(fix(input, @message), expected)
  end

  test "replaces bare reraise in multi-clause catch" do
    input =
      """
      defmodule FixReraiseKeywordInCatch do
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
      defmodule FixReraiseKeywordInCatch do
        def risky_call do
          try do
            :ok
          catch
            kind, reason ->
              Process.delete(:key)
              :erlang.raise(kind, reason, __STACKTRACE__)

            kind, reason ->
              :erlang.raise(kind, reason, __STACKTRACE__)
          end
        end
      end
      """

    confirm_fix(fix(input, @message), expected)
  end

  test "preserves catch clause with variable kind" do
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

    confirm_fix(fix(input, @message), expected)
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

    assert valid_syntax?(fix(input, @message))
  end
end
