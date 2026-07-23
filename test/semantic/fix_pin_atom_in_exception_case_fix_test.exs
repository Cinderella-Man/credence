defmodule Credence.Semantic.FixPinAtomInExceptionCaseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.RuleHelpers
  alias Credence.Semantic.FixPinAtomInExceptionCase

  # Real message captured from `Code.with_diagnostics` on Elixir 1.20 for a
  # bare `^exception ->` clause matched against a rescued exception.
  @message """
  the following clause will never match:

      ^exception ->

  because it attempts to match on the result of:

      e

  which has type:

      %{..., __exception__: term(), __struct__: atom()}

  where "exception" was given the type:

      # type: ArgumentError
      # from: nofile:3:15
      exception = ArgumentError
  """

  defp fix(source, position) do
    FixPinAtomInExceptionCase.fix(source, %{
      severity: :warning,
      message: @message,
      position: position
    })
  end

  test "fixes ^exception to %^exception{} in case inside rescue" do
    input = """
    defmodule AssertHelpers do
      @moduledoc false

      defmacro assert_raises_message(exception, needle, fun) do
        quote bind_quoted: [exception: exception, needle: needle, fun: fun] do
          try do
            fun.()

            ExUnit.Assertions.flunk("expected")
          rescue
            e ->
              case e do
                ^exception ->
                  message = Exception.message(e)

                  if String.contains?(message, needle) do
                    :ok
                  else
                    ExUnit.Assertions.flunk("wrong message")
                  end

                _ ->
                  ExUnit.Assertions.flunk("wrong exception")
              end
          end
        end
      end
    end
    """

    expected = """
    defmodule AssertHelpers do
      @moduledoc false

      defmacro assert_raises_message(exception, needle, fun) do
        quote bind_quoted: [exception: exception, needle: needle, fun: fun] do
          try do
            fun.()

            ExUnit.Assertions.flunk("expected")
          rescue
            e ->
              case e do
                %^exception{} ->
                  message = Exception.message(e)

                  if String.contains?(message, needle) do
                    :ok
                  else
                    ExUnit.Assertions.flunk("wrong message")
                  end

                _ ->
                  ExUnit.Assertions.flunk("wrong exception")
              end
          end
        end
      end
    end
    """

    confirm_fix(fix(input, {13, 13}), expected)
  end

  test "fixes a simple case with pin in rescue" do
    input = """
    defmodule Simple do
      def test(exception) do
        try do
          :ok
        rescue
          e ->
            case e do
              ^exception ->
                :matched
              _ ->
                :not_matched
            end
        end
      end
    end
    """

    expected = """
    defmodule Simple do
      def test(exception) do
        try do
          :ok
        rescue
          e ->
            case e do
              %^exception{} ->
                :matched

              _ ->
                :not_matched
            end
        end
      end
    end
    """

    confirm_fix(fix(input, {8, 11}), expected)
  end

  test "a bare integer position targets the same line as a tuple" do
    input = """
    defmodule Simple do
      def test(exception) do
        try do
          :ok
        rescue
          e ->
            case e do
              ^exception ->
                :matched
              _ ->
                :not_matched
            end
        end
      end
    end
    """

    confirm_fix(fix(input, 8), fix(input, {8, 11}))
  end

  test "rewrites only the flagged variable's clause on a shared line" do
    input = """
    defmodule OneLiner do
      def test(e, e2, exception) do
        case e do ^e2 -> :exact; ^exception -> :module; _ -> :other end
      end
    end
    """

    expected = """
    defmodule OneLiner do
      def test(e, e2, exception) do
        case e do
          ^e2 -> :exact
          %^exception{} -> :module
          _ -> :other
        end
      end
    end
    """

    confirm_fix(fix(input, {3, 30}), expected)
  end

  test "leaves a pin of a different variable untouched" do
    input = """
    defmodule Other do
      def test(other) do
        try do
          :ok
        rescue
          e ->
            case e do
              ^other ->
                :matched
              _ ->
                :not_matched
            end
        end
      end
    end
    """

    confirm_fix(fix(input, {8, 11}), input)
  end

  test "leaves a matching pin on a different line untouched" do
    input = """
    defmodule Simple do
      def test(exception) do
        try do
          :ok
        rescue
          e ->
            case e do
              ^exception ->
                :matched
              _ ->
                :not_matched
            end
        end
      end
    end
    """

    confirm_fix(fix(input, {9, 11}), input)
  end

  test "returns source unchanged when no ^var pattern on target line" do
    input = """
    defmodule Simple do
      def test(exception) do
        try do
          :ok
        rescue
          e ->
            case e do
              _ ->
                :not_matched
            end
        end
      end
    end
    """

    confirm_fix(fix(input, {8, 11}), input)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Simple do
      def test(exception) do
        try do
          :ok
        rescue
          e ->
            case e do
              ^exception ->
                :matched
              _ ->
                :not_matched
            end
        end
      end
    end
    """

    assert valid_syntax?(fix(input, {8, 11}))
  end

  test "the fix resolves the live compiler diagnostic" do
    buggy = """
    defmodule CredencePinAtomFixRepro do
      def run(fun) do
        exception = ArgumentError

        try do
          fun.()
        rescue
          e ->
            case e do
              ^exception -> :expected
              _ -> :other
            end
        end
      end
    end
    """

    {:ok, diags} = RuleHelpers.compile_and_capture(buggy)
    [diag] = Enum.filter(diags, &FixPinAtomInExceptionCase.match?/1)

    fixed = FixPinAtomInExceptionCase.fix(buggy, diag)
    assert fixed != buggy

    {:ok, remaining} = RuleHelpers.compile_and_capture(fixed)
    refute Enum.any?(remaining, &FixPinAtomInExceptionCase.match?/1)
  end
end
