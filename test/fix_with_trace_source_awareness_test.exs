defmodule Credence.Pattern.FixWithTraceSourceAwarenessTest do
  use ExUnit.Case

  alias Credence.Pattern.NoTrailingNewlineInDoc
  alias Credence.Pattern.PreferHeredocForMultiLineDoc

  defp fmt(s), do: s |> Code.format_string!() |> IO.iodata_to_binary()

  # Heredoc handling: Sourceror records the string delimiter (`"""` vs `"`)
  # in the `:__block__` metadata, so `check/2` can tell heredocs apart from
  # escape-string docs purely from the AST — no `:source` needed.

  describe "check does not false-flag heredocs (delimiter from AST meta)" do
    test "PreferHeredocForMultiLineDoc skips multi-line heredoc" do
      code = ~S'''
      defmodule Example do
        @doc """
        Summary line.

        ## Details

        More explanation here.
        """
        def foo, do: :ok
      end
      '''

      ast = Sourceror.parse_string!(code)

      assert PreferHeredocForMultiLineDoc.check(ast, []) == []
      assert PreferHeredocForMultiLineDoc.check(ast, source: code) == []
    end

    test "NoTrailingNewlineInDoc skips single-line heredoc" do
      code = ~S'''
      defmodule Example do
        @moduledoc """
        Just one line of module docs.
        """
        def foo, do: :ok
      end
      '''

      ast = Sourceror.parse_string!(code)

      assert NoTrailingNewlineInDoc.check(ast, []) == []
      assert NoTrailingNewlineInDoc.check(ast, source: code) == []
    end
  end

  # ── Confirm fix_with_trace passes :source so checks don't false-trigger ──

  describe "fix_with_trace passes :source to rule checks" do
    test "PreferHeredocForMultiLineDoc not in applied list for multi-line heredoc" do
      code = ~S'''
      defmodule Example do
        @doc """
        Summary line.

        ## Details

        More explanation here.
        """
        def foo, do: :ok
      end
      '''

      {fixed, applied} =
        Credence.Pattern.fix_with_trace(code,
          rules: [PreferHeredocForMultiLineDoc]
        )

      assert fixed == code

      assert applied == [],
             "Expected no rules applied but got: #{inspect(applied)}"
    end

    test "NoTrailingNewlineInDoc not in applied list for single-line heredoc" do
      code = ~S'''
      defmodule Example do
        @moduledoc """
        Just one line of module docs.
        """
        def foo, do: :ok
      end
      '''

      {fixed, applied} =
        Credence.Pattern.fix_with_trace(code,
          rules: [NoTrailingNewlineInDoc]
        )

      assert fixed == code

      assert applied == [],
             "Expected no rules applied but got: #{inspect(applied)}"
    end

    test "still fixes actual single-line string issues alongside heredocs" do
      code = ~S'''
      defmodule Example do
        @moduledoc """
        Multi-line heredoc.

        Should not be touched.
        """

        @doc "Function doc with trailing newline.\n"
        def foo, do: :ok
      end
      '''

      {fixed, applied} =
        Credence.Pattern.fix_with_trace(code,
          rules: [
            NoTrailingNewlineInDoc,
            PreferHeredocForMultiLineDoc
          ]
        )

      # The single-line @doc trailing \n is fixed; the heredoc is untouched.
      expected = ~S'''
      defmodule Example do
        @moduledoc """
        Multi-line heredoc.

        Should not be touched.
        """

        @doc "Function doc with trailing newline."
        def foo, do: :ok
      end
      '''

      assert fmt(fixed) == fmt(expected)

      # Only NoTrailingNewlineInDoc should appear in applied
      applied_rules = Enum.map(applied, fn {rule, _} -> rule end)
      assert NoTrailingNewlineInDoc in applied_rules
      refute PreferHeredocForMultiLineDoc in applied_rules
    end
  end
end
