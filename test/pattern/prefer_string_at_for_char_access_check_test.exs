defmodule Credence.Pattern.PreferStringAtForCharAccessCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringAtForCharAccess

  test "flags the anti-pattern: List.to_string([codepoint]) round-trip" do
    assert flagged?(PreferStringAtForCharAccess, """
           defmodule M do
             def f(code) do
               letter = List.to_string([code])
               letter
             end
           end
           """)
  end

  test "flags multiple occurrences in one block" do
    assert flagged?(PreferStringAtForCharAccess, """
           defmodule M do
             def f(a, b) do
               la = List.to_string([a])
               lb = List.to_string([b])
               {la, lb}
             end
           end
           """)
  end

  test "flags inside a for comprehension" do
    assert flagged?(PreferStringAtForCharAccess, """
           defmodule M do
             def f(range) do
               for x <- range do
                 ch = List.to_string([x])
                 ch
               end
             end
           end
           """)
  end

  test "leaves good code alone" do
    assert clean?(PreferStringAtForCharAccess, """
           defmodule M do
             def f(x) do
               <<x::utf8>>
             end
           end
           """)
  end

  test "leaves List.to_integer alone" do
    assert clean?(PreferStringAtForCharAccess, """
           defmodule M do
             def f(x) do
               List.to_integer([x])
             end
           end
           """)
  end
end
