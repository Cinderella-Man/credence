defmodule Credence.Pattern.FixWithTraceSourceAwarenessTest do
  use ExUnit.Case

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

      assert Credence.Pattern.PreferHeredocForMultiLineDoc.check(ast, []) == []
      assert Credence.Pattern.PreferHeredocForMultiLineDoc.check(ast, source: code) == []
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

      assert Credence.Pattern.NoTrailingNewlineInDoc.check(ast, []) == []
      assert Credence.Pattern.NoTrailingNewlineInDoc.check(ast, source: code) == []
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
          rules: [Credence.Pattern.PreferHeredocForMultiLineDoc]
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
          rules: [Credence.Pattern.NoTrailingNewlineInDoc]
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
            Credence.Pattern.NoTrailingNewlineInDoc,
            Credence.Pattern.PreferHeredocForMultiLineDoc
          ]
        )

      # The single-line @doc trailing \n should be fixed
      refute fixed =~ ~S|"Function doc with trailing newline.\n"|
      assert fixed =~ ~S|"Function doc with trailing newline."|

      # The heredoc should be untouched
      assert fixed =~ "Should not be touched."

      # Only NoTrailingNewlineInDoc should appear in applied
      applied_rules = Enum.map(applied, fn {rule, _} -> rule end)
      assert Credence.Pattern.NoTrailingNewlineInDoc in applied_rules
      refute Credence.Pattern.PreferHeredocForMultiLineDoc in applied_rules
    end
  end
end
