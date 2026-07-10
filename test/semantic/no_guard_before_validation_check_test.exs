defmodule Credence.Semantic.NoGuardBeforeValidationCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoGuardBeforeValidation

  @source ~S"""
  defmodule GuardBeforeValidationExample do
    def process(data, interval_ms, opts \\ [])
        when is_map(data) and is_integer(interval_ms) and interval_ms > 0 do
      agg = Keyword.get(opts, :agg, :sum)

      unless agg in [:sum, :count] do
        raise ArgumentError, "invalid agg mode: #{inspect(agg)}"
      end

      unless interval_ms > 0 do
        raise ArgumentError, "interval_ms must be positive, got: #{interval_ms}"
      end

      {data, interval_ms, agg}
    end
  end
  """

  @match_msg "guard duplicates body validation"

  setup do
    path =
      Path.join(System.tmp_dir!(), "credence_check_#{System.unique_integer([:positive])}.ex")

    File.write!(path, @source)
    on_exit(fn -> File.rm(path) end)
    %{source_path: path}
  end

  test "matches the diagnostic", %{source_path: path} do
    diag = %{severity: :warning, message: @match_msg, position: {3, 7}, file: path}
    assert NoGuardBeforeValidation.match?(diag)
  end

  test "ignores unrelated diagnostics", %{source_path: path} do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}, file: path}
    refute NoGuardBeforeValidation.match?(diag)
  end

  test "ignores when file has no guard-before-validation pattern" do
    source = ~S"""
    defmodule CleanExample do
      def process(data, interval_ms) when is_map(data) and is_integer(interval_ms) do
        unless interval_ms > 0 do
          raise ArgumentError, "interval_ms must be positive"
        end
        data
      end
    end
    """

    path =
      Path.join(System.tmp_dir!(), "credence_no_match_#{System.unique_integer([:positive])}.ex")

    File.write!(path, source)

    diag = %{severity: :warning, message: @match_msg, position: {2, 5}, file: path}
    refute NoGuardBeforeValidation.match?(diag)
    File.rm(path)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @match_msg, position: {3, 7}, file: "unused"}
    assert NoGuardBeforeValidation.to_issue(diag).rule == :no_guard_before_validation
  end

  test "sets the line in issue meta" do
    diag = %{severity: :warning, message: @match_msg, position: {42, 5}, file: "unused"}
    assert NoGuardBeforeValidation.to_issue(diag).meta.line == 42
  end
end
