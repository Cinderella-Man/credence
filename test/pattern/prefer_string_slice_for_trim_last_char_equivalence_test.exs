defmodule Credence.Pattern.PreferStringSliceForTrimLastCharEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). The fix replaces a verbose `case String.graphemes(str)`
  with `String.slice(str, 0..-2//1)`. Both remove the last character from the
  string, so the transformation is behaviour-preserving.

  Input set covers: empty string, single character, multi-character ASCII,
  precomposed accent, combining accent, multi-codepoint emoji, flag, and CJK.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferStringSliceForTrimLastChar

  test "fix preserves behaviour" do
    assert_equivalent(
      """
      case String.graphemes(str) do
        [] -> ""
        [_last] -> ""
        [_head | _tail] -> String.slice(str, 0, String.length(str) - 1)
      end
      """,
      rule: PreferStringSliceForTrimLastChar,
      vars: [:str],
      inputs: [
        "",
        "a",
        "abc",
        "hello world",
        "café",
        "café",
        "👨‍👩‍👧",
        "🇵🇱",
        "日本語"
      ]
    )
  end
end
