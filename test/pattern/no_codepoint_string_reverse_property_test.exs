defmodule Credence.Pattern.NoCodepointStringReversePropertyTest do
  @moduledoc """
  The real safety proof for `no_codepoint_string_reverse` (decision 6b): under
  the `single_codepoint_graphemes` promise, manually reversing a string via its
  codepoints agrees with `String.reverse/1` across thousands of random
  promise-satisfying strings — for *both* reassemble functions.

  The `codepoints |> Enum.join` case is included on purpose: it is the misroute
  guard from decision 4 (that shape must belong to this promise rule, never to
  the always-safe graphemes rule).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Credence.AssumptionGenerators

  property "codepoints |> reverse |> Enum.join agrees with String.reverse under the promise" do
    check all(s <- AssumptionGenerators.single_codepoint_string()) do
      manual = s |> String.codepoints() |> Enum.reverse() |> Enum.join()
      assert manual == String.reverse(s)
    end
  end

  property "codepoints |> reverse |> IO.iodata_to_binary agrees with String.reverse under the promise" do
    check all(s <- AssumptionGenerators.single_codepoint_string()) do
      manual = s |> String.codepoints() |> Enum.reverse() |> IO.iodata_to_binary()
      assert manual == String.reverse(s)
    end
  end

  describe "known differences WITHOUT the promise (why the switch is necessary)" do
    test "decomposed accent: codepoint-reverse tears the grapheme apart" do
      nfd = "ab" <> "e" <> <<0x301::utf8>>
      manual = nfd |> String.codepoints() |> Enum.reverse() |> Enum.join()
      refute manual == String.reverse(nfd)
    end
  end
end
