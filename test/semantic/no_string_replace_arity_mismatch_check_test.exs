defmodule Credence.Semantic.NoStringReplaceArityMismatchCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoStringReplaceArityMismatch

  # Real Elixir 1.20.2 message: `String.replace/4` guards on
  # `is_function(replacement, 1)`, so a multi-arity callback raises
  # `FunctionClauseError`. When the call is evaluated at compile time (module
  # attribute, macro body) the raise aborts compilation and reaches the
  # semantic round as an error diagnostic.
  @real_message "no function clause matching in String.replace/4"

  defp diag(message \\ @real_message, position \\ {6, 7}) do
    %{severity: :error, message: message, position: position}
  end

  describe "match?/1" do
    test "matches the diagnostic" do
      assert NoStringReplaceArityMismatch.match?(diag())
    end

    test "ignores unrelated diagnostics" do
      refute NoStringReplaceArityMismatch.match?(diag("unrelated", {1, 1}))
    end

    test "ignores unrelated String.replace errors" do
      refute NoStringReplaceArityMismatch.match?(diag("String.replace/3 is undefined", {1, 1}))
    end

    test "ignores a non-binary message" do
      refute NoStringReplaceArityMismatch.match?(%{severity: :error, position: 1})
    end
  end

  describe "should_report?/2 — reports only what fix/2 rewrites" do
    test "reports a regex literal with a multi-arity callback" do
      source = """
      defmodule A do
        def f(s), do: String.replace(s, ~r/(a)(b)/, fn full, a, b -> full <> a <> b end)
      end
      """

      assert NoStringReplaceArityMismatch.should_report?(diag(), source)
    end

    test "reports the compile-time (module attribute) form" do
      source = """
      defmodule A do
        @masked String.replace("ab", ~r/(a)(b)/, fn full, a, b -> full <> a <> b end)
        def masked, do: @masked
      end
      """

      assert NoStringReplaceArityMismatch.should_report?(diag(), source)
    end

    test "reports a guarded multi-arity callback" do
      source = """
      defmodule A do
        def f(s), do: String.replace(s, ~r/(a)(b)/, fn full, a, _b when a != "" -> full end)
      end
      """

      assert NoStringReplaceArityMismatch.should_report?(diag(), source)
    end

    # `Regex.replace/3` requires a `%Regex{}` first argument, so rewriting a
    # binary pattern would swap one FunctionClauseError for another.
    test "no issue for a binary pattern" do
      source = """
      defmodule A do
        def f(s), do: String.replace(s, "ab", fn full, a -> full <> a end)
      end
      """

      refute NoStringReplaceArityMismatch.should_report?(diag(), source)
    end

    test "no issue when the pattern is a variable" do
      source = """
      defmodule A do
        def f(s, re), do: String.replace(s, re, fn full, a -> full <> a end)
      end
      """

      refute NoStringReplaceArityMismatch.should_report?(diag(), source)
    end

    test "no issue when the pattern is a module attribute" do
      source = """
      defmodule A do
        @re ~r/(a)/
        def f(s), do: String.replace(s, @re, fn full, a -> full <> a end)
      end
      """

      refute NoStringReplaceArityMismatch.should_report?(diag(), source)
    end

    # `String.replace/4` options are not `Regex.replace/4` options
    # (`:insert_replaced` has no counterpart), so the 4-argument form is left alone.
    test "no issue for the 4-argument form" do
      source = """
      defmodule A do
        def f(s), do: String.replace(s, ~r/(a)/, fn full, a -> full <> a end, global: false)
      end
      """

      refute NoStringReplaceArityMismatch.should_report?(diag(), source)
    end

    test "no issue for a 1-arity callback" do
      source = """
      defmodule A do
        def f(s), do: String.replace(s, ~r/(a)/, fn m -> m end)
      end
      """

      refute NoStringReplaceArityMismatch.should_report?(diag(), source)
    end

    test "no issue for the piped form" do
      source = """
      defmodule A do
        def f(s), do: s |> String.replace(~r/(a)/, fn full, a -> full <> a end)
      end
      """

      refute NoStringReplaceArityMismatch.should_report?(diag(), source)
    end

    # The same message is emitted for every failed `String.replace` guard —
    # a non-binary subject among them — and this rule fixes none of those.
    test "no issue when the message came from a non-binary subject" do
      source = """
      defmodule A do
        @x String.replace(:atom, "a", "b")
        def x, do: @x
      end
      """

      refute NoStringReplaceArityMismatch.should_report?(diag(), source)
    end

    test "no issue when there is no String.replace call at all" do
      source = """
      defmodule A do
        def hello, do: :world
      end
      """

      refute NoStringReplaceArityMismatch.should_report?(diag(), source)
    end
  end

  describe "to_issue/1" do
    test "attributes the issue to this rule" do
      assert NoStringReplaceArityMismatch.to_issue(diag()).rule ==
               :no_string_replace_arity_mismatch
    end

    test "sets the line in issue meta" do
      assert NoStringReplaceArityMismatch.to_issue(diag(@real_message, {42, 10})).meta.line == 42
    end

    test "sets the line from a bare integer position" do
      assert NoStringReplaceArityMismatch.to_issue(diag(@real_message, 7)).meta.line == 7
    end
  end
end
