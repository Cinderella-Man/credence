defmodule Credence.Semantic.FixPinAtomInExceptionCaseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixPinAtomInExceptionCase

  @message "the following clause will never match:\n\n    ^exception\n\nbecause it attempts to match on the result of:\n\n    e\n\nwhich has type:\n\n    %{..., __exception__: true, __struct__: atom()}\n\nwhere \"exception\" was given the type:\n\n    # type: ArgumentError\n    # from: credence_check.ex:3:15\n    exception = ArgumentError\n"

  defp fix(source, message \\ @message, line \\ 13) do
    FixPinAtomInExceptionCase.fix(source, %{severity: :warning, message: message, position: {line, 1}})
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

    confirm_fix(fix(input), expected)
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

    confirm_fix(fix(input, @message, 8), expected)
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

    assert valid_syntax?(fix(input, @message, 8))
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

    confirm_fix(fix(input, @message, 8), input)
  end
end
