defmodule Credence.Semantic.FixHallucinatedMapPutArityCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixHallucinatedMapPutArity

  @put5_message "Map.put/5 is undefined or private. Did you mean:\n\n    * put/3\n"
  @put2_message "Map.put/2 is undefined or private. Did you mean:\n\n    * put/3\n"

  test "matches the real Map.put/5 diagnostic" do
    diag = %{severity: :warning, message: @put5_message, position: {3, 9}}
    assert FixHallucinatedMapPutArity.match?(diag)
  end

  test "matches Map.put/7 diagnostic" do
    diag = %{
      severity: :warning,
      message: "Map.put/7 is undefined or private",
      position: {1, 1}
    }

    assert FixHallucinatedMapPutArity.match?(diag)
  end

  test "matches Map.put/2 diagnostic" do
    diag = %{severity: :warning, message: @put2_message, position: {3, 9}}
    assert FixHallucinatedMapPutArity.match?(diag)
  end

  test "ignores Map.put/4 (dangling key, no unambiguous repair)" do
    diag = %{
      severity: :warning,
      message: "Map.put/4 is undefined or private",
      position: {1, 1}
    }

    refute FixHallucinatedMapPutArity.match?(diag)
  end

  test "ignores Map.put/6 (even arity)" do
    diag = %{
      severity: :warning,
      message: "Map.put/6 is undefined or private",
      position: {1, 1}
    }

    refute FixHallucinatedMapPutArity.match?(diag)
  end

  test "ignores Map.put/1" do
    diag = %{
      severity: :warning,
      message: "Map.put/1 is undefined or private",
      position: {1, 1}
    }

    refute FixHallucinatedMapPutArity.match?(diag)
  end

  test "ignores Map.put/3 (correct arity, some other issue)" do
    diag = %{
      severity: :warning,
      message: "Map.put/3 is undefined or private",
      position: {1, 1}
    }

    refute FixHallucinatedMapPutArity.match?(diag)
  end

  test "ignores a user module whose path ends in Map (alias shadowing)" do
    diag = %{
      severity: :warning,
      message: "MyApp.Map.put/5 is undefined or private",
      position: {1, 1}
    }

    refute FixHallucinatedMapPutArity.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixHallucinatedMapPutArity.match?(diag)
  end

  test "ignores generic compile error wrapper" do
    diag = %{
      severity: :error,
      message: "credence_check.ex: cannot compile module CsvImporter (errors have been logged)",
      position: 0,
      file: "credence_check.ex"
    }

    refute FixHallucinatedMapPutArity.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @put5_message, position: {3, 9}}
    assert FixHallucinatedMapPutArity.to_issue(diag).rule == :fix_hallucinated_map_put_arity
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @put5_message, position: {42, 10}}
    assert FixHallucinatedMapPutArity.to_issue(diag).meta.line == 42
  end

  test "should_report? is true when the fix would rewrite the source" do
    source = """
    defmodule HallucinatedMapPut do
      def build do
        Map.put(%{}, :type, :missing_required, :path, [:a])
      end
    end
    """

    diag = %{severity: :warning, message: @put5_message, position: {3, 9}}
    assert FixHallucinatedMapPutArity.should_report?(diag, source)
  end

  test "should_report? is false for shapes the fix will not touch" do
    source = """
    defmodule Piped do
      def build(m) do
        m |> Map.put(:a, 1, :b, 2)
      end
    end
    """

    diag = %{severity: :warning, message: @put5_message, position: {3, 14}}
    refute FixHallucinatedMapPutArity.should_report?(diag, source)
  end
end
