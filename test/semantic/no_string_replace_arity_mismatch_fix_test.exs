defmodule Credence.Semantic.NoStringReplaceArityMismatchFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoStringReplaceArityMismatch

  @real_message "no function clause matching in String.replace/4"

  defp fix(source, message, line \\ 1) do
    NoStringReplaceArityMismatch.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "rewrites String.replace to Regex.replace for multi-arity callback" do
    input = """
    defmodule EmailMasker do
      def mask_email(str) do
        String.replace(
          str,
          ~r/([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})/,
          fn full, local, domain ->
            masked_local =
              case local do
                <<first>> <> rest -> <<first>> <> String.duplicate("*", String.length(rest))
                _ -> "***"
              end

            masked_local <> "@" <> domain
          end
        )
      end
    end
    """

    expected = """
    defmodule EmailMasker do
      def mask_email(str) do
        Regex.replace(
          ~r/([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})/,
          str,
          fn full, local, domain ->
            masked_local =
              case local do
                <<first>> <> rest -> <<first>> <> String.duplicate("*", String.length(rest))
                _ -> "***"
              end

            masked_local <> "@" <> domain
          end
        )
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule EmailMasker do
      def mask_email(str) do
        String.replace(
          str,
          ~r/([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})/,
          fn full, local, domain ->
            local <> "@" <> domain
          end
        )
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when String.replace has 1-arity fn" do
    input = """
    defmodule OneArity do
      def replace(str) do
        String.replace(str, ~r/(a)/, fn match -> "b" end)
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged when already using Regex.replace" do
    input = """
    defmodule AlreadyCorrect do
      def mask(str) do
        Regex.replace(~r/(.+)@(.+)/, str, fn _full, local, domain -> local <> "@" <> domain end)
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged when no String.replace call" do
    input = """
    defmodule Clean do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
