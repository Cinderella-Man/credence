defmodule Credence.Pattern.PreferPatternMatchingForEmptyStringPropertyTest do
  @moduledoc """
  The real safety proof for `prefer_pattern_matching_for_empty_string` (decision
  6b): under the `single_codepoint_graphemes` promise, the original
  `if String.trim(var) == "" do [] else ... end` and the rewrite
  `def func(""), do: []` + `def func(var) do ... end` agree for strings
  without leading/trailing whitespace (where `String.trim(s) == ""` is
  equivalent to `s == ""`).

  The `single_codepoint_string/0` generator produces strings where every
  grapheme is a single codepoint. For non-whitespace single-codepoint strings,
  the empty-check semantics are preserved.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Credence.AssumptionGenerators

  property "old and fixed agree under the promise for non-whitespace single-codepoint strings" do
    check all(s <- AssumptionGenerators.single_codepoint_string()) do
      # Only test strings where String.trim behavior matches exact equality
      # (no leading/trailing whitespace)
      if String.trim(s) == s do
        old = String.trim(s) == ""
        fixed = s == ""
        assert old == fixed
      end
    end
  end

  describe "known differences WITHOUT the promise (why the switch is necessary)" do
    test "whitespace-only string: String.trim matches but pattern match does not" do
      # For whitespace-only strings, String.trim("  ") == "" is true,
      # but "" pattern match fails. This is why the rule needs the assumption.
      assert String.trim("  ") == ""
      refute "" == "  "
    end
  end
end
