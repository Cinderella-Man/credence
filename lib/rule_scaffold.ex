defmodule Credence.RuleScaffold do
  @moduledoc """
  Pure templates for a new rule and its test files. `files/2` returns
  `[{path, content}]` for a type — no disk I/O — so it is testable in memory and
  reused by both the Mix task (`mix credence.gen.rule`) that writes the files and
  the pin (`Credence.GeneratorMetaTest`) that proves the output passes every
  structural gate.

  The emitted tests are **intentionally red**: each carries a real positive /
  transform assertion that fails against the inert stub, alongside the negative /
  fixpoint / attribution *shapes* the structural gates require — so the gates pass
  while the rule is unmistakably unfinished. Single-line fixtures are plain `"…"`
  strings in canonical form (the test healer's convention) and use parseable
  placeholders (`foo(bar)` / `baz(qux)`), so the parser never crashes on them at
  runtime; fix tests compare with `confirm_fix/2`.

  Templates carry `__TQ__` for a `\"""` heredoc delimiter (so the template strings
  themselves — e.g. moduledocs — don't nest heredocs) and `__RULE_MODULE__` /
  `__TEST_MODULE__` / `__RULE__` / `__SNAKE__` name slots, all filled by `render/3`
  from `Credence.RuleName`.
  """

  alias Credence.RuleName

  @doc "File plans (`[{path, content}]`) for a new `name` rule of `type`."
  @spec files(String.t(), RuleName.rule_type()) :: [{String.t(), String.t()}]
  def files(name, type) do
    d = RuleName.derive(name, type)

    case type do
      :pattern -> pattern_files(d)
      :syntax -> syntax_files(d)
      :semantic -> semantic_files(d)
    end
  end

  # ---------------------------------------------------------------- pattern ----

  defp pattern_files(d) do
    [
      {d.rule_path, render(pattern_rule(), d, nil)},
      {RuleName.test_path(d, "check"), render(pattern_check(), d, "check")},
      {RuleName.test_path(d, "fix"), render(pattern_fix(), d, "fix")},
      {RuleName.test_path(d, "equivalence"), render(pattern_equivalence(), d, "equivalence")}
    ]
  end

  defp pattern_rule do
    ~S"""
    defmodule __RULE_MODULE__ do
      @moduledoc __TQ__
      TODO: one sentence saying what this rule detects and fixes.

      TODO: the rest of the explanation, if it needs one.

      ## Bad

          # TODO: example of the flagged code

      ## Good

          # TODO: example of the rewritten code
      __TQ__
      use Credence.Pattern.Rule

      @impl true
      def check(_ast, _opts) do
        # TODO: walk the AST and return issues, e.g.:
        #   [%Issue{rule: :__SNAKE__, message: "...", meta: %{line: line}}]
        []
      end

      @impl true
      def fix_patches(_ast, _opts) do
        # TODO: emit patches, e.g. via Credence.RuleHelpers.patches_from_postwalk/2
        []
      end

      # Rule Standard item 5 (docs/19). Declare this DELIBERATELY, even when the
      # answer is `[]` — at runtime a considered `[]` and the inherited default are
      # the same value, so this declaration is the only place the decision exists.
      # List the macro-DSL families your FIX is not behaviour-preserving inside:
      # `:ash_expr`, `:ecto_query`, `:nx_defn`, or `:all`. See the
      # `Credence.DslGuard` moduledoc for what each family reinterprets — e.g.
      # inside `Ash.Expr.expr/1` a `!` is not `not`, and inside an `Nx` `defn`
      # arithmetic and `if` are element-wise tensor ops.
      #
      # TODO: decide, then delete this comment. `test/dsl_static_scan_test.exs`
      # fails if you leave a construct-touching fix unclassified.
      @impl true
      def unsafe_in_dsl, do: []
    end
    """
  end

  defp pattern_check do
    ~S"""
    defmodule __TEST_MODULE__ do
      use Credence.RuleCase, async: true

      alias __RULE_MODULE__

      test "flags the anti-pattern" do
        # TODO: replace with real code the rule should flag
        assert flagged?(__RULE__, "foo(bar)")
      end

      test "leaves good code alone" do
        # TODO: replace with real code the rule should ignore
        assert clean?(__RULE__, "baz(qux)")
      end
    end
    """
  end

  defp pattern_fix do
    ~S"""
    defmodule __TEST_MODULE__ do
      use Credence.RuleCase, async: true

      alias __RULE_MODULE__

      test "rewrites the anti-pattern" do
        # TODO: replace input/expected with a real before/after pair
        input = "foo(bar)"

        expected = "baz(qux)"

        confirm_fix(fix(__RULE__, input), expected)
      end
    end
    """
  end

  defp pattern_equivalence do
    ~S"""
    defmodule __TEST_MODULE__ do
      use Credence.RuleCase, async: true

      alias __RULE_MODULE__

      test "fix preserves behaviour" do
        # TODO: replace with a real before-expression the rule fires on, its free
        # variables, and inputs (see Credence.EquivalenceInputs, e.g. B.term_lists()).
        assert_equivalent(
          "foo(bar)",
          rule: __RULE__,
          vars: [:bar],
          inputs: [1, 2, 3]
        )
      end
    end
    """
  end

  # ----------------------------------------------------------------- syntax ----

  defp syntax_files(d) do
    [
      {d.rule_path, render(syntax_rule(), d, nil)},
      {RuleName.test_path(d, "analyze"), render(syntax_analyze(), d, "analyze")},
      {RuleName.test_path(d, "fix"), render(syntax_fix(), d, "fix")}
    ]
  end

  defp syntax_rule do
    ~S"""
    defmodule __RULE_MODULE__ do
      @moduledoc __TQ__
      TODO: one sentence saying what this rule repairs.

      TODO: the rest of the explanation, if it needs one.

      ## Bad (does not parse)

          # TODO: the exact bytes this rule rewrites. NOT optional for a Syntax
          # rule: `self_corruption_test.exs` runs this rule's own `fix/1` over
          # this file, and this block is the adversarial input it needs.

      ## Good

          # TODO: the repaired form
      __TQ__
      use Credence.Syntax.Rule

      @impl true
      def analyze(_source) do
        # TODO: scan the source and return issues, e.g.:
        #   [%Credence.Issue{rule: :__SNAKE__, message: "...", meta: %{line: line}}]
        []
      end

      @impl true
      def fix(source) do
        # TODO: return the repaired source
        source
      end
    end
    """
  end

  defp syntax_analyze do
    ~S"""
    defmodule __TEST_MODULE__ do
      use ExUnit.Case

      alias Credence.Issue
      alias __RULE_MODULE__

      defp analyze(code), do: __RULE__.analyze(code)

      test "flags the unparseable code" do
        # TODO: replace with real code the rule should flag
        assert [%Issue{rule: :__SNAKE__}] = analyze("foo(bar)")
      end

      test "leaves good code alone" do
        # TODO: replace with real code the rule should ignore
        assert analyze("baz(qux)") == []
      end
    end
    """
  end

  defp syntax_fix do
    ~S"""
    defmodule __TEST_MODULE__ do
      use ExUnit.Case

      import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

      alias __RULE_MODULE__

      defp analyze(code), do: __RULE__.analyze(code)
      defp fix(code), do: __RULE__.fix(code)

      test "fixes the syntax error" do
        # TODO: replace input/expected with a real before/after pair
        input = "foo(bar)"

        expected = "baz(qux)"

        confirm_fix(fix(input), expected)
      end

      test "fixed output no longer flags" do
        # TODO: replace with real code the rule should flag, then fix to clean
        assert analyze(fix("foo(bar)")) == []
      end

      test "fixed output is well-formed (parses)" do
        # the repaired source must be valid Elixir
        assert valid_syntax?(fix("foo(bar)"))
      end
    end
    """
  end

  # --------------------------------------------------------------- semantic ----

  defp semantic_files(d) do
    [
      {d.rule_path, render(semantic_rule(), d, nil)},
      {RuleName.test_path(d, "check"), render(semantic_check(), d, "check")},
      {RuleName.test_path(d, "fix"), render(semantic_fix(), d, "fix")}
    ]
  end

  defp semantic_rule do
    ~S"""
    defmodule __RULE_MODULE__ do
      @moduledoc __TQ__
      TODO: one sentence saying what this rule repairs.

      TODO: quote the compiler diagnostic this rule matches, verbatim.

      ## Bad (compiles with error)

          # TODO: example of the flagged code

      ## Good

          # TODO: example of the repaired code
      __TQ__
      use Credence.Semantic.Rule

      alias Credence.Issue

      @impl true
      def match?(_diagnostic) do
        # TODO: return true for the diagnostics this rule handles
        false
      end

      @impl true
      def to_issue(diagnostic) do
        # TODO: build the issue this rule reports
        %Issue{rule: :__SNAKE__, message: "TODO", meta: %{line: line(diagnostic)}}
      end

      @impl true
      def fix(source, _diagnostic) do
        # TODO: return the repaired source
        source
      end

      defp line(%{position: {line, _col}}), do: line
      defp line(%{position: line}) when is_integer(line), do: line
    end
    """
  end

  defp semantic_check do
    ~S"""
    defmodule __TEST_MODULE__ do
      use ExUnit.Case

      alias __RULE_MODULE__

      test "matches the diagnostic" do
        # TODO: replace with a diagnostic this rule should handle
        diag = %{severity: :warning, message: "TODO matching message", position: {1, 1}}
        assert __RULE__.match?(diag)
      end

      test "ignores unrelated diagnostics" do
        diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
        refute __RULE__.match?(diag)
      end

      test "attributes the issue to this rule" do
        diag = %{severity: :warning, message: "TODO matching message", position: {1, 1}}
        assert __RULE__.to_issue(diag).rule == :__SNAKE__
      end
    end
    """
  end

  defp semantic_fix do
    ~S"""
    defmodule __TEST_MODULE__ do
      use ExUnit.Case

      import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

      alias __RULE_MODULE__

      defp fix(source, message, line \\ 1) do
        __RULE__.fix(source, %{severity: :warning, message: message, position: {line, 1}})
      end

      test "fixes the source" do
        # TODO: replace input/expected/message with a real case
        input = "foo(bar)"

        expected = "baz(qux)"

        message = "TODO matching message"
        confirm_fix(fix(input, message), expected)
      end

      test "fixed output is well-formed (parses)" do
        # the repaired source must be valid Elixir
        message = "TODO matching message"

        assert valid_syntax?(fix("foo(bar)", message))
      end
    end
    """
  end

  # ------------------------------------------------------------------ render ----

  defp render(template, d, kind) do
    test_module = if kind, do: inspect(RuleName.test_module(d, kind)), else: ""

    template
    |> String.replace("__TQ__", ~s["""])
    |> String.replace("__RULE_MODULE__", inspect(d.rule_module))
    |> String.replace("__TEST_MODULE__", test_module)
    |> String.replace("__RULE__", d.pascal)
    |> String.replace("__SNAKE__", d.snake)
  end
end
