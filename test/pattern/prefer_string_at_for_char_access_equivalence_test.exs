defmodule Credence.Pattern.PreferStringAtForCharAccessEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). The fix replaces `letter = List.to_string([code])` with
  `<<code::utf8>>` (removing the intermediate variable). Both produce the same
  binary from a codepoint integer, so the transformation is behaviour-preserving.

  Input set covers: ASCII letters, digits as codepoints, non-ASCII codepoint,
  and edge cases.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferStringAtForCharAccess

  test "letter = List.to_string([code]) -> <<code::utf8>> preserves the string" do
    assert_equivalent(
      """
      letter = List.to_string([code])
      letter
      """,
      rule: PreferStringAtForCharAccess,
      vars: [:code],
      inputs: [65, 90, 49, 233, 9731, 128_512]
    )
  end
end
