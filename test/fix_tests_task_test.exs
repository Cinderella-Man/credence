defmodule Credence.FixTestsTaskTest do
  # async: false — fix_file/1 runs the rule (compiles/loads modules).
  use ExUnit.Case, async: false

  alias Mix.Tasks.Credence.FixTests

  # A fix test whose `expected` is WRONG (the LLM guessed). UseMapJoin rewrites
  # `Enum.map(..) |> Enum.join(sep)` → `Enum.map_join(.., sep, ..)`.
  @wrong_expected ~S'''
  defmodule Credence.Pattern.UseMapJoinFixTest do
    use Credence.RuleCase, async: true

    test "rewrites map then join" do
      input = """
      defmodule Example do
        def f(xs) do
          Enum.map(xs, &Integer.to_string/1) |> Enum.join(", ")
        end
      end
      """

      expected = """
      WRONG PLACEHOLDER
      """

      assert fix(UseMapJoin, input) == expected
    end
  end
  '''

  defp in_temp(content, fun) do
    dir =
      Path.join(System.tmp_dir!(), "fixtests_#{System.unique_integer([:positive])}/test/pattern")

    File.mkdir_p!(dir)
    path = Path.join(dir, "use_map_join_fix_test.exs")
    File.write!(path, content)

    try do
      fun.(path)
    after
      File.rm_rf!(Path.dirname(Path.dirname(Path.dirname(path))))
    end
  end

  test "canonicalizes a wrong `expected` to the rule's real output" do
    in_temp(@wrong_expected, fn path ->
      FixTests.fix_file(path)
      out = File.read!(path)

      refute out =~ "WRONG PLACEHOLDER"
      assert out =~ "Enum.map_join(xs, \", \", &Integer.to_string/1)"
      # still well-formed + still a whole-string == assertion (FixMetaTest-clean)
      assert match?({:ok, _}, Sourceror.parse_string(out))
      assert out =~ "assert fix(UseMapJoin, input) == expected"
    end)
  end

  # The `=~` shape: `result = fix(...)` then a run of `assert/refute result =~ …`.
  @tilde_shape ~S'''
  defmodule Credence.Pattern.UseMapJoinFixTest do
    use Credence.RuleCase, async: true

    test "rewrites map then join" do
      input = """
      defmodule Example do
        def f(xs) do
          Enum.map(xs, &Integer.to_string/1) |> Enum.join(", ")
        end
      end
      """

      result = fix(UseMapJoin, input)

      assert result =~ "Enum.map_join"
      refute result =~ "Enum.join"
      assert valid_syntax?(result)
    end
  end
  '''

  test ~s[collapses a `result =~ …` run into one inline `fix(...) == """…"""`] do
    in_temp(@tilde_shape, fn path ->
      FixTests.fix_file(path)
      out = File.read!(path)

      refute out =~ "result =~"
      assert out =~ "assert fix(UseMapJoin, input) == "
      assert out =~ "Enum.map_join(xs, \", \", &Integer.to_string/1)"
      assert match?({:ok, _}, Sourceror.parse_string(out))
    end)
  end

  test "is idempotent — a correct fix test is left unchanged" do
    in_temp(@wrong_expected, fn path ->
      FixTests.fix_file(path)
      once = File.read!(path)
      FixTests.fix_file(path)
      assert File.read!(path) == once
    end)
  end

  # ── escaping (escalation ledger row 134) ──────────────────────────────────
  #
  # A rule whose output contains a backslash. `PreferSigilCharlist` rewrites the
  # charlist `'say "hi"'` to `~c"say \"hi\""`, so its real output holds two
  # literal backslash bytes — and the emitted fixture has to survive being read
  # back by ExUnit, which decodes heredoc escapes.
  #
  # This was filed against PreferSigilCharlist itself. The rule was right; the
  # emitter that recorded it was not.
  @escaping_fixture ~S'''
  defmodule Credence.Pattern.PreferSigilCharlistFixTest do
    use Credence.RuleCase, async: true

    test "rewrites a quoted charlist" do
      input = """
      defmodule Example do
        def f, do: 'say "hi"'
      end
      """

      expected = """
      WRONG PLACEHOLDER
      """

      assert fix(PreferSigilCharlist, input) == expected
    end
  end
  '''

  defp in_temp_named(content, basename, fun) do
    dir =
      Path.join(System.tmp_dir!(), "fixtests_#{System.unique_integer([:positive])}/test/pattern")

    File.mkdir_p!(dir)
    path = Path.join(dir, basename)
    File.write!(path, content)

    try do
      fun.(path)
    after
      File.rm_rf!(Path.dirname(Path.dirname(Path.dirname(path))))
    end
  end

  # The value the rewritten `expected` heredoc actually has once ExUnit reads the
  # file — which is the only value that decides whether the test passes.
  defp expected_runtime_value(src) do
    {:ok, ast} = Sourceror.parse_string(src)

    node =
      ast
      |> Macro.prewalk([], fn
        {:=, _, [{:expected, _, ctx}, node]} = n, acc when is_atom(ctx) ->
          {n, [node | acc]}

        n, acc ->
          {n, acc}
      end)
      |> elem(1)
      |> List.first()

    case node do
      {:__block__, meta, [value]} when is_binary(value) ->
        if Keyword.get(meta, :delimiter) == ~s("""),
          do: Macro.unescape_string(value),
          else: :not_a_literal

      _ ->
        :not_a_literal
    end
  end

  test "reading an expected value does not evaluate an arbitrary expression" do
    Process.delete(:fix_tests_expected_expression_ran)

    source = """
    defmodule Credence.FixTestsExpectedExpressionFixture do
      expected = Process.put(:fix_tests_expected_expression_ran, true)
    end
    """

    assert expected_runtime_value(source) == :not_a_literal
    refute Process.get(:fix_tests_expected_expression_ran)
  end

  test "an emitted fixture whose value contains a backslash reads back unchanged" do
    in_temp_named(@escaping_fixture, "prefer_sigil_charlist_fix_test.exs", fn path ->
      FixTests.fix_file(path)
      out = File.read!(path)

      assert match?({:ok, _}, Sourceror.parse_string(out))
      refute out =~ "WRONG PLACEHOLDER"

      real =
        Credence.RuleHelpers.apply_rule_fix(
          Credence.Pattern.PreferSigilCharlist,
          """
          defmodule Example do
            def f, do: 'say "hi"'
          end
          """
        )

      # The rule's output really does carry backslashes — otherwise this test
      # would pass for the wrong reason.
      assert real =~ ~S|~c"say \"hi\""|

      assert expected_runtime_value(out) == real,
             """
             The emitted `expected` heredoc does not read back as the rule's output.

               rule output : #{inspect(real)}
               reads back  : #{inspect(expected_runtime_value(out))}

             `heredoc/1` must escape `\\` and `#{}` on the way out, and
             `heredoc_value/1` must unescape on the way in, or the recorded fixture
             is a different string from the one the rule produced.
             """
    end)
  end

  @interpolation_fixture ~S'''
  defmodule Credence.Pattern.UseMapJoinFixTest do
    use Credence.RuleCase, async: true

    test "rewrites map then join without activating source interpolation" do
      input = """
      defmodule Credence.UseMapJoinInterpolationInput do
        def f(pairs) do
          pairs
          |> Enum.map(fn {k, v} -> "\#{k}=\#{v}" end)
          |> Enum.join("&")
        end
      end
      """

      expected = """
      WRONG PLACEHOLDER
      """

      assert fix(UseMapJoin, input) == expected
    end
  end
  '''

  test "an emitted fixture escapes interpolation markers and reads back unchanged" do
    in_temp_named(@interpolation_fixture, "use_map_join_fix_test.exs", fn path ->
      FixTests.fix_file(path)
      out = File.read!(path)

      real =
        Credence.RuleHelpers.apply_rule_fix(
          Credence.Pattern.UseMapJoin,
          """
          defmodule Credence.UseMapJoinInterpolationInput do
            def f(pairs) do
              pairs
              |> Enum.map(fn {k, v} -> "\#{k}=\#{v}" end)
              |> Enum.join("&")
            end
          end
          """
        )

      assert real ==
               ~S'''
               defmodule Credence.UseMapJoinInterpolationInput do
                 def f(pairs) do
                   pairs
                   |> Enum.map_join("&", fn {k, v} -> "#{k}=#{v}" end)
                 end
               end
               '''

      assert expected_runtime_value(out) == real
    end)
  end

  # The other half of row 134, and the half a round-trip test cannot see. Sourceror
  # parses with `unescape: false`, so the INPUT heredoc the tool hands the rule was
  # the raw source bytes rather than the value ExUnit passes. Here the input's
  # decoded value contains `\n` (backslash, n) inside a charlist; raw, it is `\\n`.
  # The rule's output differs accordingly — `~c"a\nb"` against `~c"a\\nb"` — so the
  # recorded `expected` was one the running test could never match.
  @escaped_input_fixture ~S'''
  defmodule Credence.Pattern.PreferSigilCharlistFixTest do
    use Credence.RuleCase, async: true

    test "rewrites a charlist holding an escape" do
      input = """
      defmodule Example do
        def f, do: 'a\\nb'
      end
      """

      expected = """
      WRONG PLACEHOLDER
      """

      assert fix(PreferSigilCharlist, input) == expected
    end
  end
  '''

  test "the rule is run on the input's decoded value, not its raw source bytes" do
    in_temp_named(@escaped_input_fixture, "prefer_sigil_charlist_fix_test.exs", fn path ->
      FixTests.fix_file(path)
      out = File.read!(path)

      assert match?({:ok, _}, Sourceror.parse_string(out))

      decoded_input = "defmodule Example do\n  def f, do: 'a\\nb'\nend\n"

      real =
        Credence.RuleHelpers.apply_rule_fix(Credence.Pattern.PreferSigilCharlist, decoded_input)

      # Guard against the test passing for the wrong reason: the two inputs really
      # do drive the rule to different output.
      raw_input = "defmodule Example do\n  def f, do: 'a\\\\nb'\nend\n"

      on_raw =
        Credence.RuleHelpers.apply_rule_fix(Credence.Pattern.PreferSigilCharlist, raw_input)

      refute on_raw == real, "raw and decoded input no longer diverge — this test is vacuous"

      assert expected_runtime_value(out) == real,
             """
             The recorded `expected` matches the rule's output on the RAW heredoc bytes,
             not on the value ExUnit actually passes.

               on decoded input (correct): #{inspect(real)}
               on raw bytes              : #{inspect(on_raw)}
               recorded                  : #{inspect(expected_runtime_value(out))}

             `heredoc_value/1` must unescape what Sourceror hands it (`unescape: false`).
             """
    end)
  end

  test "a fixture containing a backslash is still idempotent on a second pass" do
    in_temp_named(@escaping_fixture, "prefer_sigil_charlist_fix_test.exs", fn path ->
      FixTests.fix_file(path)
      once = File.read!(path)
      FixTests.fix_file(path)

      assert File.read!(path) == once,
             "a correctly-escaped fixture was rewritten again — heredoc/1 and " <>
               "heredoc_value/1 are not inverses, so every run re-churns the file."
    end)
  end
end
