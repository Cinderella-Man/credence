defmodule Credence.Semantic.NoCaptureAsBitwiseAndCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoCaptureAsBitwiseAnd

  # The real diagnostic Elixir emits for `x & 1` when the surrounding code
  # parses (the `&` is read as the capture operator). Verified against the
  # compiler — see the integration tests below.
  @real_message "capture argument &1 must be used within the capture operator &"

  describe "match?/1" do
    test "matches the capture-argument error" do
      diag = %{severity: :error, message: @real_message, position: {3, 11}}
      assert NoCaptureAsBitwiseAnd.match?(diag)
    end

    test "matches a multi-digit capture argument" do
      diag = %{
        severity: :error,
        message: "capture argument &2 must be used within the capture operator &",
        position: {5, 7}
      }

      assert NoCaptureAsBitwiseAnd.match?(diag)
    end

    # Regression: the previous attempt keyed off the cascading "token missing"
    # parse error, which matched *any* malformed source and turned the suite
    # red. This rule must NOT fire on a generic terminator error.
    test "does not match a generic missing-terminator parse error" do
      diag = %{
        severity: :error,
        message: "token missing on credence_check.ex:1:27:\n    error: missing terminator: }",
        position: 1
      }

      refute NoCaptureAsBitwiseAnd.match?(diag)
    end

    test "does not match an unrelated error" do
      diag = %{
        severity: :error,
        message: "undefined function foo/0",
        position: {2, 5}
      }

      refute NoCaptureAsBitwiseAnd.match?(diag)
    end

    test "does not match a warning with the same text" do
      diag = %{severity: :warning, message: @real_message, position: {3, 11}}
      refute NoCaptureAsBitwiseAnd.match?(diag)
    end
  end

  describe "to_issue/1" do
    test "builds issue with correct rule and line" do
      diag = %{severity: :error, message: @real_message, position: {3, 11}}
      issue = NoCaptureAsBitwiseAnd.to_issue(diag)
      assert issue.rule == :no_capture_as_bitwise_and
      assert issue.meta.line == 3
    end

    test "handles bare integer position" do
      diag = %{severity: :error, message: @real_message, position: 3}
      assert NoCaptureAsBitwiseAnd.to_issue(diag).meta.line == 3
    end
  end

  describe "integration through Credence.Semantic" do
    test "detects `x & 1` misused as bitwise AND" do
      source = """
      defmodule CaptureAndCheckInteg1 do
        def low_bit(n) do
          n & 1
        end
      end
      """

      issues = Credence.Semantic.analyze(source)
      matched = Enum.filter(issues, &(&1.rule == :no_capture_as_bitwise_and))
      refute Enum.empty?(matched)
    end

    test "no issue when Bitwise.band is used correctly" do
      source = """
      defmodule CaptureAndCheckInteg2 do
        def low_bit(n) do
          Bitwise.band(n, 1)
        end
      end
      """

      issues = Credence.Semantic.analyze(source)
      matched = Enum.filter(issues, &(&1.rule == :no_capture_as_bitwise_and))
      assert matched == []
    end

    test "detects bare &1 in pipe step" do
      source = """
      defmodule CapturePipeCheckInteg1 do
        def update(state, key, val) do
          state
          |> Map.put(key, Map.get(&1, key, val))
        end
      end
      """

      issues = Credence.Semantic.analyze(source)
      matched = Enum.filter(issues, &(&1.rule == :no_capture_as_bitwise_and))
      refute Enum.empty?(matched)
    end
  end
end
