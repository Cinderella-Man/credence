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

  @doc ~s[Conventional path of a rule's test file for `kind` ("check" | "fix" | ...).]
  def test_path(rule, kind), do: rule |> RuleName.from_module() |> RuleName.test_path(kind)

  @doc "Conventional path of the rule's own implementation file."
  def rule_path(rule), do: rule |> RuleName.from_module() |> Map.fetch!(:rule_path)

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

  # Canonical form: `confirm_fix(fix(Rule, A), B)` where B is not structurally A.
  def transform?({:confirm_fix, _, [a, b]}) do
    cond do
      fix_call?(a) -> fix_arg(a) != src(b)
      fix_call?(b) -> fix_arg(b) != src(a)
      true -> false
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

  # --- equivalence-DIMENSION predicates (EquivalenceDimensionMetaTest) --------
  #
  # C2.2. An equivalence test is only evidence if its inputs can *see* the
  # divergence the rule's own operation class produces. The operation class is
  # read off the RULE source (which stdlib call does it match or emit?); the
  # coverage is read off the TEST's actual `inputs:` VALUES, not their names — a
  # hand-rolled list counts exactly as much as an `EquivalenceInputs` dimension.

  # Order- and identity-sensitive collection calls. Erlang term order compares
  # `1` and `1.0` EQUAL (so a sort ties them) while every map / MapSet / `===`
  # path treats them as DISTINCT. That pair is the whole trap.
  @value_kind_ops ~w(sort sort_by min max min_by max_by uniq uniq_by dedup dedup_by
                     frequencies frequencies_by group_by member?)

  @value_kind_mods ~w(Enum List Map MapSet Keyword Stream)

  # Calls whose answer depends on where a grapheme boundary falls.
  @grapheme_ops ~w(graphemes codepoints length at first last slice reverse
                   split_at next_grapheme to_charlist)

  @scanned_mods ~w(Enum List Map MapSet Keyword Tuple Stream String)

  @doc """
  The stdlib `{module, callee}` pairs a rule *matches or emits* in USER code, as
  `MapSet` of `{"Enum", "sort"}`-shaped tuples.

  Read off the rule source in the one position that is unambiguous: an
  `__aliases__` **literal** — `{:__aliases__, _, [:Enum]}` — which appears only
  in a quoted pattern the rule matches on or a quoted node it builds. A rule's
  own housekeeping (`Keyword.get(opts, …)`, `Enum.sort_by(issues, …)`) is a real
  call, never an alias literal, so it contributes nothing here. Two callee forms
  are recognised:

    * a literal callee — `{:__aliases__, _, [:Enum]}, :sort]`;
    * a variable callee constrained by a membership guard —
      `[{:__aliases__, _, [:Enum]}, fun]` … `when fun in [:min, :max]`, the shape
      several multi-callee rules use (e.g. `NoIfEmptyForEnumMinMax`).

  Whitespace is normalised first, so line breaks in the pattern do not matter.
  """
  def rule_stdlib_callees(source) when is_binary(source) do
    flat = String.replace(source, ~r/\s+/, "")
    mods = Enum.join(@scanned_mods, "|")

    literal =
      ~r/\[:(#{mods})\]\},:([a-z_][A-Za-z_0-9]*[?!]?)\]/
      |> Regex.scan(flat)
      |> Enum.map(fn [_, mod, fun] -> {mod, fun} end)

    guarded =
      ~r/\[:(#{mods})\]\},([a-z_][A-Za-z_0-9]*)\]/
      |> Regex.scan(flat)
      |> Enum.flat_map(fn [_, mod, var] ->
        case Regex.run(~r/#{Regex.escape(var)}in\[([^\]]*)\]/, flat) do
          [_, body] ->
            ~r/:([a-z_][A-Za-z_0-9]*[?!]?)/
            |> Regex.scan(body)
            |> Enum.map(fn [_, fun] -> {mod, fun} end)

          nil ->
            []
        end
      end)

    MapSet.new(literal ++ guarded)
  end

  @doc "Does the rule match or emit an order- / identity-sensitive collection call?"
  def value_kind_sensitive?(callees) do
    Enum.any?(callees, fn {mod, fun} ->
      mod in @value_kind_mods and fun in @value_kind_ops
    end)
  end

  @doc "Does the rule match or emit a `String` grapheme / codepoint call?"
  def grapheme_sensitive?(callees) do
    Enum.any?(callees, fn {mod, fun} -> mod == "String" and fun in @grapheme_ops end)
  end

  @doc """
  Every individual value passed via `inputs:` in an equivalence test, flattened
  across all `inputs:` options in the file and **evaluated**.

  Module attributes (`@numbers`) are substituted from the same file and `alias
  Credence.EquivalenceInputs, as: B` is expanded, so `inputs: B.term_lists()`
  and `inputs: @numbers` both resolve. Returns `:error` when any `inputs:`
  expression cannot be evaluated standalone (one that depends on test-local
  state); a caller must then decline to judge rather than guess.
  """
  def equivalence_input_values(ast) do
    attrs = module_attributes(ast)
    aliases = alias_table(ast)

    ast
    |> collect(fn
      {{:__block__, _, [:inputs]}, value} -> [value]
      _ -> []
    end)
    |> Enum.map(&(&1 |> substitute_attributes(attrs) |> expand_aliases(aliases)))
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, acc} ->
      case eval_data(node) do
        {:ok, list} when is_list(list) -> {:cont, {:ok, acc ++ list}}
        {:ok, other} -> {:cont, {:ok, acc ++ [other]}}
        :error -> {:halt, :error}
      end
    end)
  end

  @doc """
  Does any single input carry the value-kind trap — an integer and a float that
  are `==` but not `===`, at any depth inside the *same* input?

  Same input, not merely the same battery: a sort/uniq/`member?` divergence
  needs both kinds present in one collection to be observable.
  """
  def value_kind_tie?(inputs) do
    Enum.any?(inputs, fn input ->
      nums = input |> subterms() |> Enum.filter(&is_number/1)
      ints = Enum.filter(nums, &is_integer/1)
      floats = Enum.filter(nums, &is_float/1)

      Enum.any?(ints, fn i -> Enum.any?(floats, fn f -> i == f end) end)
    end)
  end

  @doc "Is there a number anywhere in the input set (else the value-kind trap is unconstructible)?"
  def any_number?(inputs),
    do: Enum.any?(inputs, &Enum.any?(subterms(&1), fn v -> is_number(v) end))

  @doc "Is there a string anywhere in the input set (else the grapheme trap is unconstructible)?"
  def any_string?(inputs),
    do: Enum.any?(inputs, &Enum.any?(subterms(&1), fn v -> is_binary(v) end))

  @doc """
  Does any input contain a string with a **multi-codepoint grapheme** — a
  decomposed accent, a ZWJ emoji, a regional-indicator flag? Measured, not
  named: the string's grapheme count differs from its codepoint count.
  """
  def multi_codepoint_grapheme?(inputs) do
    Enum.any?(inputs, fn input ->
      Enum.any?(subterms(input), fn v ->
        is_binary(v) and String.valid?(v) and
          String.length(v) != length(String.to_charlist(v))
      end)
    end)
  end

  # Every subterm of a runtime value, including the value itself. Handles
  # improper lists (`[1 | 2]`, a real fixture in `RedundantListGuard`).
  defp subterms([h | t]), do: [[h | t] | subterms(h) ++ subterms(t)]
  defp subterms([]), do: [[]]
  defp subterms(v) when is_tuple(v), do: [v | Enum.flat_map(Tuple.to_list(v), &subterms/1)]

  defp subterms(v) when is_map(v) and not is_struct(v),
    do: [v | Enum.flat_map(Map.to_list(v), fn {k, val} -> subterms(k) ++ subterms(val) end)]

  defp subterms(v), do: [v]

  # Collect `fun.(node)`'s contributions over the whole tree.
  defp collect(ast, fun) do
    {_, acc} = Macro.prewalk(ast, [], fn node, acc -> {node, acc ++ fun.(node)} end)
    acc
  end

  # `@name <literal>` at module level -> %{name => quoted}.
  defp module_attributes(ast) do
    ast
    |> collect(fn
      {:@, _, [{name, _, [value]}]} when is_atom(name) -> [{name, value}]
      _ -> []
    end)
    |> Map.new()
  end

  defp substitute_attributes(node, attrs) do
    Macro.prewalk(node, fn
      {:@, _, [{name, _, ctx}]} = n when is_atom(name) and is_atom(ctx) ->
        Map.get(attrs, name, n)

      n ->
        n
    end)
  end

  # `alias A.B.C, as: D` / `alias A.B.C` -> %{D => A.B.C}.
  defp alias_table(ast) do
    ast
    |> collect(fn
      {:alias, _, [{:__aliases__, _, parts}]} ->
        [{List.last(parts), parts}]

      {:alias, _, [{:__aliases__, _, parts}, [{{:__block__, _, [:as]}, as}]]} ->
        case as do
          {:__aliases__, _, [short]} -> [{short, parts}]
          _ -> [{List.last(parts), parts}]
        end

      _ ->
        []
    end)
    |> Map.new()
  end

  defp expand_aliases(node, table) do
    Macro.prewalk(node, fn
      {:__aliases__, meta, [short]} = n ->
        case Map.fetch(table, short) do
          {:ok, parts} -> {:__aliases__, meta, parts}
          :error -> n
        end

      n ->
        n
    end)
  end

  defp eval_data(node) do
    {value, _binding} = Code.eval_quoted(node, [], __ENV__)
    {:ok, value}
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

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

  # Canonical form: `confirm_fix(fix(A, …), B)` where `src(A) != src(B)`.
  def fix_source_transform?({:confirm_fix, _, [a, b]}) do
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

            # `confirm_fix(fix(Rule, input), expected)` — the `expected` (2nd arg) is
            # a fixture; the `input` is collected via the inner `fix(...)` verb call.
            {:confirm_fix, _, [_actual, expected]} ->
              if stringish?(expected), do: [expected], else: []

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
    cond do
      # a literal `"""` in the value can't be a heredoc or a plain string — leave it
      String.contains?(String.replace(s, "\\\"", "\""), "\"\"\"") -> true
      # a heredoc is canonical ONLY when multi-line; a single-content-line heredoc
      # must be a plain `"…"` / `~S'…'`
      Keyword.get(m, :delimiter) == "\"\"\"" -> multi_content_line?(s)
      # a plain `"…"` is canonical when it needs neither a heredoc nor escaping
      true -> single_line_plain?(s)
    end
  end

  def fixture_ok?({:<<>>, m, parts}),
    do: Keyword.get(m, :delimiter) == "\"\"\"" or not multiline_interp?(parts)

  def fixture_ok?({sg, m, [{:<<>>, _, [b]}, _]})
      when sg in [:sigil_s, :sigil_S] and is_binary(b),
      do:
        Keyword.get(m, :delimiter) == "\"\"\"" or String.contains?(b, "\"\"\"") or
          (Keyword.get(m, :delimiter) == "'" and not has_newline?(b))

  def fixture_ok?({sg, m, [{:<<>>, _, parts}, _]}) when sg in [:sigil_s, :sigil_S],
    do: Keyword.get(m, :delimiter) == "\"\"\"" or not multiline_interp?(parts)

  def fixture_ok?({:<>, _, _}), do: false
  def fixture_ok?(_), do: false

  # A plain `"…"` needs neither a heredoc nor escaping iff its value has no
  # newline and no inner double-quote.
  defp single_line_plain?(s), do: not has_newline?(s) and not String.contains?(s, "\"")

  defp has_newline?(s), do: String.contains?(s, "\n") or String.contains?(s, "\\n")

  # A heredoc value (real newlines) with ≥2 content lines — an internal newline
  # beyond the structural trailing one a heredoc always carries.
  defp multi_content_line?(s), do: String.contains?(String.trim_trailing(s, "\n"), "\n")

  defp multiline_interp?(parts) do
    lit = parts |> Enum.filter(&is_binary/1) |> Enum.join()

    (String.contains?(lit, "\\n") or String.contains?(lit, "\n")) and
      not String.contains?(lit, "\"\"\"")
  end
end
