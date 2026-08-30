defmodule Credence.Pattern.PreferStringSliceForTrimLastCharCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringSliceForTrimLastChar
  alias Credence.RuleHelpers

  @equivalence_inputs ["", "a", "ab", "abc", "é", "é", "👨‍👩‍👧", "a👨‍👩‍👧", "日本語"]

  test "equivalence fixtures use the bounded compiler" do
    source = File.read!(__ENV__.file)
    unsafe_call = Regex.compile!("call_" <> "fixed\\(")

    assert Regex.scan(unsafe_call, source) == []
  end

  test "equivalence inputs include a decomposed combining sequence" do
    decomposed = Enum.filter(@equivalence_inputs, &(String.codepoints(&1) == ["e", "́"]))

    assert decomposed == ["é"]
  end

  test "flags the anti-pattern" do
    assert flagged?(PreferStringSliceForTrimLastChar, """
           defmodule Example do
             def trim_last_char(str) when is_binary(str) do
               case String.graphemes(str) do
                 [] -> ""
                 [_last] -> ""
                 [_head | _tail] -> String.slice(str, 0, String.length(str) - 1)
               end
             end
           end
           """)
  end

  test "leaves good code alone" do
    assert clean?(PreferStringSliceForTrimLastChar, """
           defmodule Example do
             def trim_last_char(str) when is_binary(str) do
               String.slice(str, 0..-2//1)
             end
           end
           """)
  end

  test "does not flag a case with different patterns" do
    assert clean?(PreferStringSliceForTrimLastChar, """
           case String.graphemes(str) do
             [] -> :empty
             _ -> :non_empty
           end
           """)
  end

  test "does not flag a case with different subject" do
    assert clean?(PreferStringSliceForTrimLastChar, """
           case some_function(str) do
             [] -> ""
             [_last] -> ""
             [_head | _tail] -> String.slice(str, 0, String.length(str) - 1)
           end
           """)
  end

  test "does not flag a case with different body in third clause" do
    assert clean?(PreferStringSliceForTrimLastChar, """
           case String.graphemes(str) do
             [] -> ""
             [_last] -> ""
             [_head | _tail] -> String.slice(str, 0, String.length(str) - 2)
           end
           """)
  end

  # ── D6/C12(c): the SHAPE half of over-fitting ──────────────────────────
  #
  # The matcher was positional — exactly three clauses, in one order, under
  # `String.graphemes` — so it fired on the single example its author wrote and
  # missed the other spellings of the same function. Each variant below was
  # proven equivalent to `String.slice(str, 0..-2//1)` by EXECUTION over
  # combining characters, ZWJ emoji and CJK before the matcher was widened.
  describe "other spellings of the same idiom" do
    test "the two-clause form with a wildcard is detected" do
      assert flagged?(PreferStringSliceForTrimLastChar, """
             defmodule TrimTwo do
               def f(str) do
                 case String.graphemes(str) do
                   [] -> ""
                   _ -> String.slice(str, 0, String.length(str) - 1)
                 end
               end
             end
             """)
    end

    test "String.codepoints is detected as well as String.graphemes" do
      assert flagged?(PreferStringSliceForTrimLastChar, """
             defmodule TrimCp do
               def f(str) do
                 case String.codepoints(str) do
                   [] -> ""
                   [_last] -> ""
                   [_h | _t] -> String.slice(str, 0, String.length(str) - 1)
                 end
               end
             end
             """)
    end

    # The boundary, pinned. A leading slice clause is EQUIVALENT — that was
    # measured — but it makes the trailing clauses unreachable, which is a
    # separate finding belonging to a separate rule. Rewriting the case away
    # would take that finding with it silently.
    test "a leading slice clause is deliberately left alone" do
      refute flagged?(PreferStringSliceForTrimLastChar, """
             defmodule TrimReordered do
               def f(str) do
                 case String.graphemes(str) do
                   [_h | _t] -> String.slice(str, 0, String.length(str) - 1)
                   [_last] -> ""
                   [] -> ""
                 end
               end
             end
             """)
    end

    # And the guard that makes widening safe: a leading bare `_ -> ""` sends
    # every input to the empty string. That is a different function, not this
    # idiom written differently.
    test "a leading catch-all returning empty is not this idiom" do
      refute flagged?(PreferStringSliceForTrimLastChar, """
             defmodule TrimAlwaysEmpty do
               def f(str) do
                 case String.graphemes(str) do
                   _ -> ""
                   [] -> ""
                 end
               end
             end
             """)
    end

    test "a single-clause case is not enough to be this idiom" do
      refute flagged?(PreferStringSliceForTrimLastChar, """
             defmodule TrimOne do
               def f(str) do
                 case String.graphemes(str) do
                   _ -> String.slice(str, 0, String.length(str) - 1)
                 end
               end
             end
             """)
    end

    test "each newly-matched spelling rewrites to a function that behaves identically" do
      two_clause = """
      defmodule TrimEqTwo do
        def f(str) do
          case String.graphemes(str) do
            [] -> ""
            _ -> String.slice(str, 0, String.length(str) - 1)
          end
        end
      end
      """

      codepoints = """
      defmodule TrimEqCp do
        def f(str) do
          case String.codepoints(str) do
            [] -> ""
            [_l] -> ""
            [_h | _t] -> String.slice(str, 0, String.length(str) - 1)
          end
        end
      end
      """

      for {source, mod} <- [{two_clause, TrimEqTwo}, {codepoints, TrimEqCp}] do
        fixed = fix(PreferStringSliceForTrimLastChar, source)
        assert fixed != source, "expected this spelling to be rewritten:\n#{source}"

        for input <- @equivalence_inputs do
          for candidate <- [source, fixed] do
            assertion = """

            unless #{inspect(mod)}.f(#{inspect(input)}) === String.slice(#{inspect(input)}, 0..-2//1) do
              raise #{inspect("diverged on #{inspect(input)}")}
            end
            """

            assert {:ok, []} = RuleHelpers.compile_and_capture(candidate <> assertion)
          end
        end
      end
    end
  end
end
