defmodule Credence.MetaTestSupport do
  @moduledoc """
  Shared machinery for the structural per-rule test-file gates — `CheckMetaTest`,
  `FixMetaTest`, `EquivalenceMetaTest`, `FixtureStringEscapingTest`,
  `NoParserCallsInRuleTestsTest`, `RuleTestCompletenessTest`, the Syntax/Semantic
  meta tests, and the generator pin (`GeneratorMetaTest`). Each gate walks a rule's
  test file(s) and asserts they are real and substantive — not hollow, not testing
  the wrong rule, not a stub.

  The predicates live here (rather than private to each gate) so the generator pin
  and the real gates assert against the **same** code: the generator cannot drift
  from the contract without a gate or the pin going red. Names and paths are
  derived through `Credence.RuleName`, the one naming source of truth.

  Test files are introspected with **Sourceror**, like everything else in this
  project (no `Code.string_to_quoted`). Because heredoc fixtures are string
  literals in the tree, code *inside* them (a `check`, a `=~`, an `Enum.count`)
  is invisible to these walks — only real test-logic nodes are seen.
  """

  alias Credence.RuleName

  # --- discovery -------------------------------------------------------------

  @doc "Every discovered Pattern rule."
  def rules, do: Credence.RuleHelpers.discover_rules(Credence.Pattern.Rule)

  @doc "Every discovered Syntax rule."
  def syntax_rules, do: Credence.RuleHelpers.discover_rules(Credence.Syntax.Rule)

  @doc "Every discovered Semantic rule."
  def semantic_rules, do: Credence.RuleHelpers.discover_rules(Credence.Semantic.Rule)

  # --- names & paths (via RuleName) ------------------------------------------

  @doc "The rule's short name, e.g. `NoManualFind`."
  def short(rule), do: rule |> Module.split() |> List.last()

  @doc "Conventional path of a rule's test file for `kind` (\"check\" | \"fix\" | ...)."
  def test_path(rule, kind), do: rule |> RuleName.from_module() |> RuleName.test_path(kind)

  @doc "Conventionally-named test module for a rule's `kind` file, e.g. `…CheckTest`."
  def test_module(rule, kind), do: rule |> RuleName.from_module() |> RuleName.test_module(kind)

  # --- parsing & generic walks -----------------------------------------------

  @doc "Parse the file at `path` with Sourceror; `:error` if it is absent."
  def load_ast(path) do
    if File.exists?(path),
      do: {:ok, path |> File.read!() |> Sourceror.parse_string!()},
      else: :error
  end

  @doc "Parse a source `string` with Sourceror (for in-memory content, e.g. the pin)."
  def parse(string), do: Sourceror.parse_string!(string)

  @doc "True if `pred` holds for any node in `ast`."
  def walk_any?(ast, pred) do
    {_, found} = Macro.prewalk(ast, false, fn node, acc -> {node, acc or pred.(node)} end)
    found
  end

  @doc "Count the nodes in `ast` for which `pred` is true."
  def count_nodes(ast, pred) do
    {_, n} =
      Macro.prewalk(ast, 0, fn node, acc -> {node, if(pred.(node), do: acc + 1, else: acc)} end)

    n
  end

  @doc "Does `ast` contain a bare (unqualified) call to any name in `names`?"
  def calls_any?(ast, names) do
    walk_any?(ast, fn
      {name, _, args} when is_atom(name) and is_list(args) -> name in names
      _ -> false
    end)
  end

  @doc """
  Does any module reference (`__aliases__`) end in `last_atom`? Catches both
  `alias Credence.Pattern.NoFoo` and a bare `NoFoo` use. The test module's own
  name ends in `NoFooCheckTest`/`NoFooFixTest`, so it never matches the rule atom.
  """
  def references_rule?(ast, last_atom) do
    walk_any?(ast, fn
      {:__aliases__, _, parts} when is_list(parts) -> List.last(parts) == last_atom
      _ -> false
    end)
  end

  @doc "Does `ast` contain `defmodule <module> do ... end`?"
  def defines_module?(ast, module) do
    parts = module |> Module.split() |> Enum.map(&String.to_atom/1)

    walk_any?(ast, fn
      {:defmodule, _, [{:__aliases__, _, ^parts} | _]} -> true
      _ -> false
    end)
  end

  @doc "Render a node back to source text (for value comparisons)."
  def src(node), do: Macro.to_string(node)

  @doc "Is `node` an `==` comparison with an empty-list operand (`x == []`)?"
  def equals_empty_list?({:==, _, [a, b]}), do: src(a) == "[]" or src(b) == "[]"
  def equals_empty_list?(_), do: false

  def bullets(entries, line), do: Enum.map_join(entries, "\n", &("  - " <> line.(&1)))

  # --- check-test predicates (CheckMetaTest) ---------------------------------

  @doc "Assertion verbs a check test must use."
  def check_fns, do: [:check, :flagged?, :clean?]

  @doc """
  A positive (rule-fires) assertion: an explicit `flagged?`, or a `check(...)`
  result used as anything other than `== []`.
  """
  def has_positive?(ast) do
    calls_any?(ast, [:flagged?]) or
      count_nodes(ast, &check_call?/1) > count_nodes(ast, &check_eq_empty?/1)
  end

  @doc "A negative (rule-stays-quiet) assertion: an explicit `clean?`, or `check(...) == []`."
  def has_negative?(ast) do
    calls_any?(ast, [:clean?]) or count_nodes(ast, &check_eq_empty?/1) > 0
  end

  def check_call?({:check, _, args}) when is_list(args), do: true
  def check_call?(_), do: false

  def check_eq_empty?({:==, _, [a, b]} = node),
    do: equals_empty_list?(node) and (check_call?(a) or check_call?(b))

  def check_eq_empty?(_), do: false

  # --- fix-test predicates (FixMetaTest) -------------------------------------

  def fix_call?({:fix, _, [_rule | [_code | _]]}), do: true
  def fix_call?(_), do: false

  @doc """
  A partial / normalized comparison banned in fix tests: `=~`, an
  AST-normalizing round-trip, or a qualified `String`/`Regex` substring matcher.
  """
  def partial_match?({:=~, _, _}), do: true

  def partial_match?({{:., _, [{:__aliases__, _, mods}, :normalize_sourceror_ast]}, _, _})
      when is_list(mods),
      do: true

  def partial_match?({{:., _, [{:__aliases__, _, [mod]}, fun]}, _, _})
      when mod in [:String, :Regex] and fun in [:contains?, :starts_with?, :ends_with?, :match?],
      do: true

  def partial_match?(_), do: false

  @doc "`fix(Rule, A) == B` where B is not structurally A — i.e. the fix changed something."
  def transform?({:==, _, [a, b]}) do
    case {fix_call?(a), fix_call?(b)} do
      {true, _} -> fix_arg(a) != src(b)
      {_, true} -> fix_arg(b) != src(a)
      _ -> false
    end
  end

  def transform?(_), do: false

  def fix_arg({:fix, _, [_rule, code | _]}), do: src(code)

  # --- no-parser predicate (NoParserCallsInRuleTestsTest) --------------------

  @doc "A bare `Code` / `Sourceror` module reference."
  def parser_ref?({:__aliases__, _, [mod]}), do: mod in [:Code, :Sourceror]
  def parser_ref?(_), do: false

  # --- equivalence-test predicates (EquivalenceMetaTest) ---------------------

  @doc "The real behaviour-equivalence assertions."
  def assert_fns,
    do: [:assert_equivalent, :assert_equivalent_module, :assert_effect_trace_equivalent]

  @doc "The explicit equivalence opt-out marks."
  def mark_fns,
    do: [:mark_equivalence_cosmetic, :mark_equivalence_unconstructible, :mark_equivalence_repair]

  # --- syntax/semantic substance predicates ----------------------------------
  #
  # Syntax/Semantic tests call the rule either bare (via a local `defp analyze/fix`
  # wrapper) or qualified (`Rule.analyze(...)`), so these match both forms.

  @doc "A bare `name(...)` or qualified `Mod.name(...)` call."
  def call_to?({{:., _, [_, n]}, _, a}, name) when is_list(a), do: n == name
  def call_to?({n, _, a}, name) when is_atom(n) and is_list(a), do: n == name
  def call_to?(_, _), do: false

  def analyze_call?(node), do: call_to?(node, :analyze)
  def fix_call1?(node), do: call_to?(node, :fix)
  def match_call?(node), do: call_to?(node, :match?)

  def analyze_eq_empty?({:==, _, [a, b]} = node),
    do: equals_empty_list?(node) and (analyze_call?(a) or analyze_call?(b))

  def analyze_eq_empty?(_), do: false

  @doc "An `analyze(...)` result used as non-empty (anything other than `== []`)."
  def analyze_positive?(ast),
    do: count_nodes(ast, &analyze_call?/1) > count_nodes(ast, &analyze_eq_empty?/1)

  @doc "An `analyze(...) == []` assertion (the rule stays quiet)."
  def analyze_negative?(ast), do: count_nodes(ast, &analyze_eq_empty?/1) > 0

  @doc "`fix(A, ...) == B` where `src(A) != src(B)` — the fix rewrote its source."
  def fix_source_transform?({:==, _, [a, b]}) do
    cond do
      fix_call1?(a) -> fix_first_arg(a) != src(b)
      fix_call1?(b) -> fix_first_arg(b) != src(a)
      true -> false
    end
  end

  def fix_source_transform?(_), do: false

  defp fix_first_arg({:fix, _, [arg | _]}), do: src(arg)
  defp fix_first_arg({{:., _, [_, :fix]}, _, [arg | _]}), do: src(arg)

  @doc "An `analyze(fix(...)) == []` fixpoint assertion (the fix clears its own flag)."
  def fixpoint?({:==, _, [a, b]} = node),
    do: equals_empty_list?(node) and (analyze_of_fix?(a) or analyze_of_fix?(b))

  def fixpoint?(_), do: false

  defp analyze_of_fix?({:analyze, _, [arg]}), do: walk_any?(arg, &fix_call1?/1)
  defp analyze_of_fix?({{:., _, [_, :analyze]}, _, [arg]}), do: walk_any?(arg, &fix_call1?/1)
  defp analyze_of_fix?(_), do: false

  @doc """
  A `valid_syntax?(fix(...))` assertion — the fix's *output* is well-formed code
  (it parses), so a fix that corrupts the source into unparseable garbage is
  caught. (We use `valid_syntax?` for both rounds rather than `compiles?`: it is
  uniform, side-effect-free, and works on fragment fixtures — `compiles?` is false
  for correct fixes whose fixtures are bare `def`/expression fragments or need a
  running ExUnit context.)
  """
  def fix_output_valid?({:valid_syntax?, _, [arg]}), do: walk_any?(arg, &fix_call1?/1)

  def fix_output_valid?({{:., _, [_, :valid_syntax?]}, _, [arg]}),
    do: walk_any?(arg, &fix_call1?/1)

  def fix_output_valid?(_), do: false

  @doc "Does the ast `assert` a `match?(...)` (positive — the rule matches a diagnostic)?"
  def asserts_match?(ast) do
    walk_any?(ast, fn
      {:assert, _, [arg]} -> walk_any?(arg, &match_call?/1)
      _ -> false
    end)
  end

  @doc "Does the ast `refute` a `match?(...)` (negative — the rule ignores a diagnostic)?"
  def refutes_match?(ast) do
    walk_any?(ast, fn
      {:refute, _, [arg]} -> walk_any?(arg, &match_call?/1)
      _ -> false
    end)
  end

  @doc "Does the literal atom `atom` appear in `ast` (Sourceror wraps literals in `:__block__`)?"
  def references_atom?(ast, atom) do
    walk_any?(ast, fn
      {:__block__, _, [^atom]} -> true
      ^atom -> true
      _ -> false
    end)
  end

  # --- fixture predicates (FixtureStringEscapingTest) ------------------------

  @verbs MapSet.new([
           :check,
           :flagged?,
           :clean?,
           :fix,
           :valid_syntax?,
           :compiles?,
           :analyze,
           :assert_equivalent,
           :assert_equivalent_module,
           :assert_effect_trace_equivalent
         ])

  @fvars MapSet.new([:code, :input, :expected, :source, :fixed, :snippet, :before, :after])

  @doc "Collect string-like nodes sitting in a fixture position within `ast`."
  def fixtures(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn node, acc ->
        add =
          case node do
            {op, _, [l, r]} when op in [:==, :!=] ->
              if verb_call?(l) or verb_call?(r), do: Enum.filter([l, r], &stringish?/1), else: []

            {:=, _, [{var, _, ctx}, rhs]} when is_atom(var) and is_atom(ctx) ->
              if MapSet.member?(@fvars, var) and stringish?(rhs), do: [rhs], else: []

            {v, _, args} when is_atom(v) and is_list(args) ->
              if MapSet.member?(@verbs, v), do: verb_fixtures(args), else: []

            _ ->
              []
          end

        {node, add ++ acc}
      end)

    Enum.uniq(acc)
  end

  # Pick the code-fixture argument(s) of a verb call.
  #
  # Rule-first verbs (`check(Rule, code)`, `fix(Rule, code)`) name the rule as an
  # inline alias FIRST; the code fixture(s) follow, so we check the rest.
  #
  # Source-first verbs (`fix(source, diagnostic)`, `analyze(code)`,
  # `valid_syntax?(code)`, `assert_equivalent(before, opts)`) put the source
  # FIRST — any LATER string arg is a diagnostic / opt / reason, NOT code (a
  # semantic rule's diagnostic-message arg is not a fixture). So only the first
  # arg can be a code fixture, and it's caught here only when written inline; a
  # source bound to a var is checked at its `=` assignment instead.
  defp verb_fixtures([{:__aliases__, _, _} | rest]), do: Enum.filter(rest, &stringish?/1)
  defp verb_fixtures([first | _]), do: Enum.filter([first], &stringish?/1)
  defp verb_fixtures([]), do: []

  defp stringish?({:__block__, m, [s]}) when is_binary(s), do: Keyword.get(m, :delimiter) != nil
  defp stringish?({:<<>>, _, _}), do: true
  defp stringish?({sg, _, _}) when sg in [:sigil_s, :sigil_S], do: true
  defp stringish?({:<>, _, [l, r]}), do: stringish?(l) and stringish?(r)
  defp stringish?(_), do: false

  defp verb_call?({v, _, a}) when is_atom(v) and is_list(a), do: MapSet.member?(@verbs, v)
  defp verb_call?(_), do: false

  @doc """
  Is fixture node `node` acceptable — a heredoc, an interpolated single-line
  string/sigil, or code carrying `\"""` (which a heredoc can't nest)?
  """
  def fixture_ok?({:__block__, m, [s]}) when is_binary(s) do
    Keyword.get(m, :delimiter) == "\"\"\"" or
      String.contains?(String.replace(s, "\\\"", "\""), "\"\"\"")
  end

  def fixture_ok?({:<<>>, m, parts}),
    do: Keyword.get(m, :delimiter) == "\"\"\"" or not multiline_interp?(parts)

  def fixture_ok?({sg, m, [{:<<>>, _, [b]}, _]})
      when sg in [:sigil_s, :sigil_S] and is_binary(b),
      do: Keyword.get(m, :delimiter) == "\"\"\"" or String.contains?(b, "\"\"\"")

  def fixture_ok?({sg, m, [{:<<>>, _, parts}, _]}) when sg in [:sigil_s, :sigil_S],
    do: Keyword.get(m, :delimiter) == "\"\"\"" or not multiline_interp?(parts)

  def fixture_ok?({:<>, _, _}), do: false
  def fixture_ok?(_), do: false

  defp multiline_interp?(parts) do
    lit = parts |> Enum.filter(&is_binary/1) |> Enum.join()

    (String.contains?(lit, "\\n") or String.contains?(lit, "\n")) and
      not String.contains?(lit, "\"\"\"")
  end
end
