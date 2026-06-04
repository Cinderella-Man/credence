defmodule Credence.Pattern.NoCaseDestructureInPipeCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoCaseDestructureInPipe

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoCaseDestructureInPipe.check(ast, [])
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGGED — single-clause case in a pipe with an irrefutable variable
  # pattern (always matches → equivalent to then/1).
  # ═══════════════════════════════════════════════════════════════════

  describe "flags irrefutable single-clause case in pipe" do
    test "bare variable pattern" do
      code = """
      defmodule BadCase do
        def process(x) do
          x
          |> compute()
          |> case do
            value -> value + 1
          end
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_case_destructure_in_pipe
      assert issue.message =~ "then/1"
      assert issue.meta.line != nil
    end

    test "underscore wildcard pattern" do
      code = """
      defmodule BadCase do
        def process(x) do
          x
          |> compute()
          |> case do
            _ -> 42
          end
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "underscore-prefixed variable pattern" do
      code = """
      defmodule BadCase do
        def process(x) do
          x
          |> compute()
          |> case do
            _value -> 42
          end
        end
      end
      """

      assert length(check(code)) == 1
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NOT FLAGGED — refutable patterns are deliberately dropped. When the
  # piped value does not match, `case` raises CaseClauseError but
  # `then(fn pattern -> ... end)` raises FunctionClauseError, so the
  # rewrite is NOT answer-preserving on every input.
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag refutable single-clause case in pipe" do
    test "tuple destructure pattern" do
      code = """
      defmodule X do
        def process(list) do
          list
          |> reduce()
          |> case do
            {sum, count} -> sum / count
          end
        end
      end
      """

      assert check(code) == []
    end

    test "tagged-tuple pattern" do
      code = """
      defmodule X do
        def process(x) do
          x
          |> fetch()
          |> case do
            {:ok, result} -> result
          end
        end
      end
      """

      assert check(code) == []
    end

    test "literal atom pattern" do
      code = """
      defmodule X do
        def process(x) do
          x
          |> fetch()
          |> case do
            nil -> :none
          end
        end
      end
      """

      assert check(code) == []
    end

    test "guarded variable pattern" do
      code = """
      defmodule X do
        def process(x) do
          x
          |> compute()
          |> case do
            v when v > 0 -> v
          end
        end
      end
      """

      assert check(code) == []
    end

    test "pinned variable pattern" do
      code = """
      defmodule X do
        def process(x, expected) do
          x
          |> compute()
          |> case do
            ^expected -> :ok
          end
        end
      end
      """

      assert check(code) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NOT FLAGGED — structurally out of scope.
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag out-of-scope shapes" do
    test "multi-clause case in pipe (even with a variable first clause)" do
      code = """
      defmodule X do
        def process(x) do
          x
          |> compute()
          |> case do
            value -> value + 1
            other -> other
          end
        end
      end
      """

      assert check(code) == []
    end

    test "single-clause case NOT in a pipe" do
      code = """
      defmodule X do
        def process(x) do
          case x do
            value -> value + 1
          end
        end
      end
      """

      assert check(code) == []
    end

    test "then/1 already in pipe" do
      code = """
      defmodule X do
        def process(x) do
          x
          |> compute()
          |> then(fn value -> value + 1 end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
