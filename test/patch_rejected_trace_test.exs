defmodule Credence.PatchRejectedTraceTest do
  use ExUnit.Case, async: true

  alias Credence.{Issue, RuleHelpers}

  # C5. `apply_rule_fix/3` discards a fix whose patched output fails to parse or
  # perturbs the comment multiset. The finding is still REPORTED, so this is the
  # one exception to "every Pattern rule fixes what it finds" — and the caller
  # could not see it: the function returned `source`, which is byte-identical to
  # what a rule with nothing to do returns. No trace entry, no log line, no way
  # for the harness's bugfix lane to notice a rule that reports and never fixes.
  #
  # These fixtures are deliberately broken rules. Each produces patches that the
  # safety invariants must reject, one per invariant.

  defmodule NonParsingFixRule do
    @moduledoc false
    use Credence.Pattern.Rule

    @impl true
    def priority, do: 500

    @impl true
    def check(_ast, _opts), do: [%Issue{rule: :non_parsing_fix, message: "x", meta: %{line: 1}}]

    # Replaces the whole first line with an unbalanced delimiter, so the patched
    # source cannot parse and the invariant must drop it.
    @impl true
    def fix_patches(_ast, opts) do
      source = Keyword.fetch!(opts, :source)
      [first | _] = String.split(source, "\n")

      [
        %{
          range: %{start: [line: 1, column: 1], end: [line: 1, column: String.length(first) + 1]},
          change: "def broken( do"
        }
      ]
    end
  end

  defmodule CommentEatingFixRule do
    @moduledoc false
    use Credence.Pattern.Rule

    @impl true
    def priority, do: 500

    @impl true
    def check(_ast, _opts),
      do: [%Issue{rule: :comment_eating_fix, message: "x", meta: %{line: 2}}]

    # Rewrites the commented line to valid code WITHOUT the comment: the output
    # parses fine, so only the comment-multiset invariant catches it.
    @impl true
    def fix_patches(_ast, opts) do
      source = Keyword.fetch!(opts, :source)
      lines = String.split(source, "\n")
      target = Enum.find_index(lines, &String.contains?(&1, "# keep me")) + 1
      len = lines |> Enum.at(target - 1) |> String.length()

      [
        %{
          range: %{start: [line: target, column: 1], end: [line: target, column: len + 1]},
          change: "  y = 2"
        }
      ]
    end
  end

  defmodule CleanFixRule do
    @moduledoc false
    use Credence.Pattern.Rule

    @impl true
    def priority, do: 500

    @impl true
    def check(_ast, _opts), do: [%Issue{rule: :clean_fix, message: "x", meta: %{line: 2}}]

    @impl true
    def fix_patches(_ast, opts) do
      source = Keyword.fetch!(opts, :source)
      lines = String.split(source, "\n")
      target = Enum.find_index(lines, &String.contains?(&1, "y = 1")) + 1
      len = lines |> Enum.at(target - 1) |> String.length()

      [
        %{
          range: %{start: [line: target, column: 1], end: [line: target, column: len + 1]},
          change: "  y = 2"
        }
      ]
    end
  end

  @commented """
  defmodule Sample do
    # keep me
    def go, do: :ok
  end
  """

  @plain """
  defmodule Sample do
    y = 1
    def go, do: :ok
  end
  """

  describe "apply_rule_fix_with_status/3" do
    test "reports :patch_rejected when the patched output does not parse" do
      assert {:patch_rejected, unchanged} =
               RuleHelpers.apply_rule_fix_with_status(NonParsingFixRule, @plain)

      assert unchanged == @plain
    end

    test "reports :patch_rejected when the fix loses a comment" do
      assert {:patch_rejected, unchanged} =
               RuleHelpers.apply_rule_fix_with_status(CommentEatingFixRule, @commented)

      assert unchanged == @commented
    end

    test "reports :ok when the fix is kept" do
      assert {:ok, fixed} = RuleHelpers.apply_rule_fix_with_status(CleanFixRule, @plain)
      assert fixed =~ "y = 2"
    end

    test "reports :no_patches when the rule emits nothing" do
      defmodule QuietRule do
        @moduledoc false
        use Credence.Pattern.Rule
        @impl true
        def priority, do: 500
        @impl true
        def check(_ast, _opts), do: []
        @impl true
        def fix_patches(_ast, _opts), do: []
      end

      assert {:no_patches, unchanged} =
               RuleHelpers.apply_rule_fix_with_status(QuietRule, @plain)

      assert unchanged == @plain
    end

    # The compatibility guarantee: the old arity still returns a bare string, so
    # every rule test that asserts on post-fix bytes is unaffected.
    test "apply_rule_fix/3 still returns just the source" do
      assert RuleHelpers.apply_rule_fix(NonParsingFixRule, @plain) == @plain
      assert RuleHelpers.apply_rule_fix(CleanFixRule, @plain) =~ "y = 2"
    end
  end

  describe "the trace distinguishes a rejected patch from a no-op" do
    test "a rejected patch is recorded as {rule, :patch_rejected}" do
      {code, applied} =
        Credence.Pattern.fix_with_trace(@plain, rules: [NonParsingFixRule])

      assert code == @plain
      assert applied == [{NonParsingFixRule, :patch_rejected}]
    end

    test "a rule with nothing to do records nothing" do
      {code, applied} = Credence.Pattern.fix_with_trace(@plain, rules: [CleanFixRule])

      assert code =~ "y = 2"
      assert applied == [{CleanFixRule, 1}]
    end
  end
end
