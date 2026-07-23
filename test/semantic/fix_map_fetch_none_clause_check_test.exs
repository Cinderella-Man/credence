defmodule Credence.Semantic.FixMapFetchNoneClauseCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixMapFetchNoneClause

  # Real message captured from `Code.with_diagnostics` on Elixir 1.20 for a
  # `:none ->` clause in a `case Map.fetch(map, key)`.
  @real_message """
  the following clause will never match:

      :none ->

  because it attempts to match on the result of:

      Map.fetch(map, key)

  which has type:

      dynamic(:error or {:ok, term()})
  """

  test "matches the real never-match diagnostic for :none on Map.fetch" do
    diag = %{severity: :warning, message: @real_message, position: 4}
    assert FixMapFetchNoneClause.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixMapFetchNoneClause.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {1, 1}}
    refute FixMapFetchNoneClause.match?(diag)
  end

  test "ignores never-match diagnostics for clauses other than :none" do
    msg = String.replace(@real_message, ":none ->", "%{} ->")
    diag = %{severity: :warning, message: msg, position: 4}
    refute FixMapFetchNoneClause.match?(diag)
  end

  test "ignores never-match diagnostics for non-Map.fetch subjects" do
    msg = String.replace(@real_message, "Map.fetch(map, key)", "Keyword.fetch(opts, key)")
    diag = %{severity: :warning, message: msg, position: 4}
    refute FixMapFetchNoneClause.match?(diag)
  end

  test "ignores the generic empty-clause-body warning" do
    # A bare `:none ->` also emits this parser warning, but it fires for ANY
    # empty `->` body anywhere (fn, cond, receive). The rule deliberately keys
    # on the type-checker diagnostic instead, which proves the :none clause is
    # dead code on a Map.fetch subject.
    diag = %{
      severity: :warning,
      message:
        "an expression is always required on the right side of ->. Please provide a value after ->",
      position: {5, 13}
    }

    refute FixMapFetchNoneClause.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: 4}
    assert FixMapFetchNoneClause.to_issue(diag).rule == :fix_map_fetch_none_clause
  end

  test "sets the line in issue meta from a bare integer position" do
    diag = %{severity: :warning, message: @real_message, position: 4}
    assert FixMapFetchNoneClause.to_issue(diag).meta.line == 4
  end

  test "sets the line in issue meta from a {line, col} position" do
    diag = %{severity: :warning, message: @real_message, position: {42, 5}}
    assert FixMapFetchNoneClause.to_issue(diag).meta.line == 42
  end

  test "should_report? is true when the fix would rewrite the source" do
    source = """
    defmodule ShouldReportNone do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    diag = %{severity: :warning, message: @real_message, position: 4}
    assert FixMapFetchNoneClause.should_report?(diag, source)
  end

  test "should_report? is false when an :error clause already exists" do
    source = """
    defmodule ShouldReportShadow do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> :a
          :error -> :b
          {:ok, value} -> value
        end
      end
    end
    """

    diag = %{severity: :warning, message: @real_message, position: 4}
    refute FixMapFetchNoneClause.should_report?(diag, source)
  end

  test "should_report? is false when a catch-all clause exists" do
    source = """
    defmodule ShouldReportCatchAll do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> :a
          {:ok, value} -> value
          _ -> :other
        end
      end
    end
    """

    diag = %{severity: :warning, message: @real_message, position: 4}
    refute FixMapFetchNoneClause.should_report?(diag, source)
  end

  test "reported end-to-end by the semantic phase" do
    source = """
    defmodule CredenceNoneClauseE2eCheck do
      def find(map, key) do
        case Map.fetch(map, key) do
          :none -> {:error, :not_found}
          {:ok, value} -> {:ok, value}
        end
      end
    end
    """

    issues = Credence.Semantic.analyze(source)
    assert Enum.any?(issues, &(&1.rule == :fix_map_fetch_none_clause))
  end
end
