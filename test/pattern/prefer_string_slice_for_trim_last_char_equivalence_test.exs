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
  alias Credence.RuleHelpers

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

  test "does not rewrite when the empty-list case is missing" do
    source =
      fixture(TrimMissingEmptyClauseFixture, """
      case String.graphemes(str) do
        [_last] -> ""
        [_head | _tail] -> String.slice(str, 0, String.length(str) - 1)
      end
      """)

    assert_same_outcome_after_fix(
      source,
      TrimMissingEmptyClauseFixture,
      "",
      {:raised, CaseClauseError}
    )
  end

  test "does not rewrite when a named catch-all shadows the subject" do
    source =
      fixture(TrimNamedShadowFixture, """
      case String.graphemes(str) do
        [] -> ""
        str -> String.slice(str, 0, String.length(str) - 1)
      end
      """)

    assert_same_outcome_after_fix(
      source,
      TrimNamedShadowFixture,
      "ab",
      {:raised, FunctionClauseError}
    )
  end

  test "does not rewrite when a cons binding shadows the subject" do
    source =
      fixture(TrimConsShadowFixture, """
      case String.graphemes(str) do
        [] -> ""
        [_last] -> ""
        [str | tail] -> String.slice(str, 0, String.length(str) - 1)
      end
      """)

    assert_same_outcome_after_fix(source, TrimConsShadowFixture, "abc", {:returned, ""})
  end

  defp fixture(module, expression) do
    """
    defmodule #{inspect(module)} do
      def run(str) do
        #{expression}
      end
    end
    """
  end

  defp assert_same_outcome_after_fix(source, module, input, expected_outcome) do
    emitted = RuleHelpers.apply_rule_fix(PreferStringSliceForTrimLastChar, source)

    assert emitted == source
    assert runtime_outcome(source, module, input) == expected_outcome
    assert runtime_outcome(emitted, module, input) == expected_outcome
  end

  defp runtime_outcome(source, module, input) do
    parent = self() |> :erlang.pid_to_list() |> List.to_string()

    executable =
      source <>
        """
        outcome =
          try do
            {:returned, #{inspect(module)}.run(#{inspect(input)})}
          rescue
            error -> {:raised, error.__struct__}
          end

        send(:erlang.list_to_pid(~c"#{parent}"), {#{inspect(module)}, outcome})
        """

    {:ok, _diagnostics} = RuleHelpers.compile_and_capture(executable)

    receive do
      {^module, outcome} -> outcome
    end
  end
end
