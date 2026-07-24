defmodule Credence.Syntax.FixInlineKeywordIfInWithClauseAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixInlineKeywordIfInWithClause

  defp analyze(code), do: FixInlineKeywordIfInWithClause.analyze(code)

  describe "flags a keyword `if` bound with `<-`" do
    test "when the binding is followed by another one" do
      code = """
      defmodule M do
        def run(list, opts) do
          with {:ok, items} <- parse(list),
               ref <- if item_ref(opts), do: item_ref(opts), else: nil,
               parent <- if parent_ref(opts), do: parent_ref(opts), else: nil do
            {:ok, items, ref, parent}
          else
            _ -> {:error, :invalid}
          end
        end
      end
      """

      assert [%Issue{rule: :fix_inline_keyword_if_in_with_clause, meta: %{line: 4}}] =
               analyze(code)
    end

    test "when it is the last binding, terminated by the block's do" do
      code = """
      defmodule M do
        def run(a) do
          with {:ok, v} <- fetch(a),
               ref <- if v, do: 1, else: 2 do
            ref
          end
        end
      end
      """

      assert [%Issue{rule: :fix_inline_keyword_if_in_with_clause, meta: %{line: 4}}] =
               analyze(code)
    end

    test "when the `if` has no else" do
      code = """
      defmodule M do
        def run(a) do
          with ref <- if a, do: 1,
               {:ok, v} <- fetch(a) do
            {ref, v}
          end
        end
      end
      """

      assert [%Issue{rule: :fix_inline_keyword_if_in_with_clause}] = analyze(code)
    end

    test "in a `for` generator, which errors the same way" do
      code = """
      defmodule M do
        def run(xs) do
          for x <- if xs, do: xs, else: [],
              y <- [1] do
            {x, y}
          end
        end
      end
      """

      assert [%Issue{rule: :fix_inline_keyword_if_in_with_clause}] = analyze(code)
    end
  end

  describe "no issue" do
    test "code that parses" do
      code = """
      defmodule M do
        def run(list, opts) do
          with {:ok, items} <- parse(list) do
            ref = if item_ref(opts), do: item_ref(opts), else: nil
            {:ok, items, ref}
          else
            _ -> {:error, :invalid}
          end
        end
      end
      """

      assert analyze(code) == []
    end

    test "an already-parenthesised binding (nothing left to wrap)" do
      code = """
      defmodule M do
        def run(a) do
          with ref <- (if a, do: 1, else: 2),
               {:ok, v} <- fetch(a) do
            {ref, v}
          end
        end
      end
      """

      assert analyze(code) == []
    end

    test "the same parse error with no `<-` binding in sight" do
      assert analyze("foo(1, key: 2, 3)") == []
      assert analyze("foo bar 1, key: 2, other") == []
    end

    test "a keyword list that belongs to something other than `if`" do
      code = """
      defmodule M do
        def run(a) do
          with ref <- case(a), do: 1, else: 2,
               {:ok, v} <- fetch(a) do
            {ref, v}
          end
        end
      end
      """

      assert analyze(code) == []
    end

    # Deliberately dropped: the `if`'s span cannot be proven from the parser's
    # anchors, so the rule stays silent rather than guess where to close.
    test "an `if` continued on the line after the `<-`" do
      code = """
      defmodule M do
        def run(a) do
          with ref <-
                 if a, do: 1, else: 2,
               z <- f(a) do
            {ref, z}
          end
        end
      end
      """

      assert analyze(code) == []
    end

    test "a last binding with a trailing comment after `do`" do
      code = """
      defmodule M do
        def run(a) do
          with {:ok, v} <- fetch(a),
               ref <- if v, do: 1, else: 2 do # note
            ref
          end
        end
      end
      """

      assert analyze(code) == []
    end

    test "`if(cond), do:` — parentheses around the span would not repair it" do
      code = """
      defmodule M do
        def run(a) do
          with ref <- if(a), do: 1, else: 2,
               z <- f(a) do
            {ref, z}
          end
        end
      end
      """

      assert analyze(code) == []
    end

    test "the bad shape quoted inside a heredoc, with the real error elsewhere" do
      code = """
      defmodule M do
        @moduledoc \"\"\"
        Bad:

            with ref <- if a, do: 1, else: 2,
                 z <- f(a) do
              {ref, z}
            end
        \"\"\"

        def broken(x) do
          x +
        end
      end
      """

      assert analyze(code) == []
    end
  end
end
