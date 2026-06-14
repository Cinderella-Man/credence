defmodule Credence.Semantic.AvoidBinaryMidPatternCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.AvoidBinaryMidPattern

  test "matches the diagnostic" do
    diag = %{
      severity: :error,
      message:
        "a binary field without size is only allowed at the end of a binary pattern, at the right side of binary concatenation and never allowed in binary generators. The following examples are invalid:\n\n    rest <> \"foo\"\n    <<rest::binary, \"foo\">>\n\nThey are invalid because there is a bits/bitstring component not at the end. However, the \"reverse\" would work:\n\n    \"foo\" <> rest\n    <<\"foo\", rest::binary>>\n\n",
      position: {3, 18},
      file: "credence_check.ex"
    }

    assert AvoidBinaryMidPattern.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute AvoidBinaryMidPattern.match?(diag)
  end

  test "ignores error diagnostics without binary field message" do
    diag = %{severity: :error, message: "some other error", position: {1, 1}}
    refute AvoidBinaryMidPattern.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{
      severity: :error,
      message: "a binary field without size is only allowed at the end of a binary pattern",
      position: {3, 18}
    }

    assert AvoidBinaryMidPattern.to_issue(diag).rule == :avoid_binary_mid_pattern
  end

  test "to_issue includes the line number from the diagnostic" do
    diag = %{
      severity: :error,
      message: "a binary field without size is only allowed at the end of a binary pattern",
      position: {5, 10}
    }

    issue = AvoidBinaryMidPattern.to_issue(diag)
    assert issue.meta.line == 5
  end
end
