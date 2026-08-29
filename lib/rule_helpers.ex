defmodule Credence.RuleHelpers do
  @moduledoc """
  Shared utilities used by all three Credence phases (Syntax, Semantic, Pattern).

  Provides rule discovery, safe compilation with diagnostics capture,
  diff computation, and change logging so the phase modules don't
  duplicate this plumbing.
  """

  require Logger

  @doc """
  Returns all modules implementing `behaviour`, sorted by priority
  (lower first) with module name as tiebreaker for determinism.

      iex> Credence.RuleHelpers.discover_rules(Credence.Pattern.Rule)
      [Credence.Pattern.SomeRule, ...]
  """
  @spec discover_rules(module()) :: [module()]
  def discover_rules(behaviour) do
    Application.spec(:credence, :modules)
    |> Enum.filter(&implements?(&1, behaviour))
    |> Enum.sort_by(&{&1.priority(), &1})
  end

  @doc """
  Returns `true` if `module` declares `behaviour` in its `@behaviour` attribute.
  """
  @spec implements?(module(), module()) :: boolean()
  def implements?(module, behaviour) do
    behaviour in Keyword.get(module.__info__(:attributes), :behaviour, [])
  end

  @doc """
  Returns the short name of a rule module for logging.

      iex> Credence.RuleHelpers.rule_name(Credence.Pattern.NoSortThenAt)
      "NoSortThenAt"
  """
  @spec rule_name(module()) :: String.t()
  def rule_name(module) do
    module |> Module.split() |> List.last()
  end

  @doc """
  Resolves the effective assumption settings from `opts`, folding the three
  layers (built-in defaults → `config :credence, :assumptions` → call `opts`),
  later wins. See `Credence.Assumptions` for the merge algebra. User-supplied
  layers are validated; an unknown switch name raises.
  """
  @spec effective_assumptions(keyword()) :: Credence.Assumptions.settings()
  def effective_assumptions(opts) do
    config = Application.get_env(:credence, :assumptions, %{})
    call = Keyword.get(opts, :assumptions, %{})

    validate_assumption_layer!(config)
    validate_assumption_layer!(call)

    merge_assumptions(Credence.Assumptions.defaults(), [config, call])
  end

  @doc """
  Pure merge algebra for assumption layers, independent of the registry.

  Starts from `defaults` and folds each layer on top: `:strict` forces every
  key off, `:default` resets every key to `defaults`, and a map patches only
  the keys it names (unmentioned keys keep the value from the layer below).
  """
  @spec merge_assumptions(Credence.Assumptions.settings(), [map() | :strict | :default]) ::
          Credence.Assumptions.settings()
  def merge_assumptions(defaults, layers) do
    Enum.reduce(layers, defaults, &apply_assumption_layer(&2, defaults, &1))
  end

  defp apply_assumption_layer(acc, _defaults, :strict),
    do: Map.new(acc, fn {k, _} -> {k, false} end)

  defp apply_assumption_layer(_acc, defaults, :default), do: defaults

  defp apply_assumption_layer(acc, _defaults, map) when is_map(map), do: Map.merge(acc, map)

  defp validate_assumption_layer!(value) when value in [:strict, :default], do: :ok
  defp validate_assumption_layer!(map) when is_map(map), do: Credence.Assumptions.validate!(map)

  defp validate_assumption_layer!(other) do
    raise ArgumentError,
          "invalid `:assumptions` value: #{inspect(other)}. " <>
            "Expected a map of switch settings, `:strict`, or `:default`."
  end

  @doc """
  The assumptions a `rule` needs that are **not** on under `effective` settings.
  An empty list means every needed promise holds. A switch the rule names that
  is unknown (not in `effective`) counts as off — an unsatisfiable promise.
  """
  @spec missing_assumptions(module(), Credence.Assumptions.settings()) :: [atom()]
  def missing_assumptions(rule, effective) do
    Enum.reject(rule.assumptions(), fn name -> Map.get(effective, name, false) == true end)
  end

  @doc """
  Keeps only the rules whose every needed promise is on under `opts`.

  A rule that names an unknown switch is treated as relying on a promise that
  can never be satisfied, so it is filtered out and a warning is logged. When
  `explicit_list?` is true (the caller passed an explicit `rules:` list), a
  rule filtered out for an *off* (but known) promise also logs a warning, since
  naming a rule and getting silence reads as "this rule is broken".
  """
  @spec filter_by_assumptions([module()], keyword(), boolean()) :: [module()]
  def filter_by_assumptions(rules, opts, explicit_list? \\ false) do
    effective = effective_assumptions(opts)

    Enum.filter(rules, fn rule ->
      case missing_assumptions(rule, effective) do
        [] ->
          true

        missing ->
          warn_filtered_rule(rule, missing, explicit_list?)
          false
      end
    end)
  end

  @doc "Whether `rule`'s every needed promise is on under `opts`."
  @spec rule_enabled?(module(), keyword()) :: boolean()
  def rule_enabled?(rule, opts) do
    missing_assumptions(rule, effective_assumptions(opts)) == []
  end

  defp warn_filtered_rule(rule, missing, explicit_list?) do
    name = rule_name(rule)
    {unknown, known_off} = Enum.split_with(missing, &(not Credence.Assumptions.known?(&1)))

    if unknown != [] do
      Logger.warning(
        "[credence] #{name} disabled: names unknown assumption(s) #{inspect(unknown)} — " <>
          "treated as never satisfiable. This is a rule bug; CI should catch it."
      )
    end

    if explicit_list? and known_off != [] do
      Logger.warning("[credence] #{name} skipped: needs #{inspect(known_off)}, which is off")
    end

    :ok
  end

  # A compile is an EXECUTION. `Code.compile_string/2` evaluates every top-level
  # expression in `source`, so analysing a file runs it — and the population this
  # linter exists for is LLM-generated code, which is exactly where a top-level
  # expression that never terminates is likely.
  #
  # This is not hypothetical. `Enum.flat_map(1..10, &Stream.cycle([&1]))` — the
  # *expected output* of one of `UndefinedFunction`'s own fix tests, harvested as
  # a witness candidate — takes this VM from 200 MB to 62 GB in about six
  # minutes. On 2026-07-28 the kernel OOM killer killed `beam.smp` seven times
  # for it, taking the editor down each time.
  #
  # So the compile runs in a throwaway process carrying a heap ceiling and a
  # deadline: a runaway now costs one process instead of the machine. Both
  # numbers are deliberately far above any legitimate compile — the entire
  # 9,911-test suite peaks at ~1.2 GB — because this bounds catastrophe rather
  # than tuning performance. Overridable via application env so the bounds
  # themselves can be tested; see `test/compile_bounds_test.exs`.
  @compile_max_heap_words 64_000_000
  @compile_timeout_ms 30_000

  @doc """
  Compiles `source` with `Code.with_diagnostics/1` and returns
  `{:ok, diagnostics}` or `{:error, diagnostics}`.

  Uses `:code.soft_purge/1` for cleanup so that compiling source
  which redefines a currently-executing module does not kill the BEAM
  (see `:code.purge/1` — it sends an unconditional kill signal to
  any process still running the old version of the module).

  **Compiling is running.** Top-level code in `source` executes, so the compile
  happens inside a bounded child process. Source that exhausts the heap ceiling,
  outruns the deadline, or exits the process is reported as `{:error, [_]}` with
  a synthesized diagnostic rather than being allowed to take the VM with it.
  `System.halt/0` remains outside anyone's reach.
  """
  @spec compile_and_capture(String.t()) :: {:ok, [map()]} | {:error, [map()]}
  def compile_and_capture(source) do
    with_module_lock(source, fn -> do_compile_and_capture(source) end)
  end

  # Compiling is a GLOBAL side effect: `Code.compile_string/2` loads the modules
  # into the code server, and `safe_cleanup_modules/1` deletes them again. Two
  # concurrent analyses of DIFFERENT files that happen to define the SAME module
  # name therefore race — one deletes the module the other is still working
  # with — and the loser silently reports **no issues at all**.
  #
  # Measured, and it is not marginal: two files each containing one unused
  # variable, analysed concurrently.
  #
  #     same module name       30 of 30 runs divergent
  #     different module names  0 of 30 runs divergent
  #
  # The divergence is a false NEGATIVE — `[]` where `[:unused_variable]` was
  # expected — which is the worst direction for a linter: it does not fail, it
  # quietly approves. It was found as a test flake (`pipeline_witness` reporting
  # a healthy rule as dead) but the flake was only the symptom; anything that
  # analyses files in parallel hits it, and `defmodule Example` is not a rare
  # name in generated code.
  #
  # The lock is keyed on the module names in the source rather than held
  # globally. Files defining different modules still compile concurrently, which
  # is the common case and the one that would otherwise pay for this. `:global`
  # is used because it needs no supervision tree — this library has none — and
  # `[node()]` keeps it local.
  defp with_module_lock(source, fun) do
    case module_key(source) do
      nil -> fun.()
      key -> :global.trans({{__MODULE__, key}, self()}, fun, [node()])
    end
  end

  # The module names a source defines, as one key. A cheap regex rather than a
  # parse: this runs before every compile, the answer only has to be *stable*
  # for a given source, and over-matching (a `defmodule` inside a string) costs
  # a little needless serialisation rather than a wrong answer.
  @defmodule ~r/^\s*defmodule\s+([A-Z][A-Za-z0-9_.]*)/m

  defp module_key(source) do
    case Regex.scan(@defmodule, source, capture: :all_but_first) do
      [] -> nil
      names -> names |> List.flatten() |> Enum.sort() |> Enum.uniq() |> Enum.join(",")
    end
  end

  defp do_compile_and_capture(source) do
    case bounded_compile(source) do
      {:ok, {result, diagnostics}} ->
        case result do
          # The compiler RAISED (e.g. CompileError "cannot invoke @/1 outside
          # module") rather than emitting a diagnostic, so `Code.with_diagnostics`
          # captured nothing. Synthesize an error diagnostic from the exception so
          # the semantic round can still match + fix it (without this, every such
          # error was a 0-diagnostic dead end). Append to any captured diagnostics.
          {:raised, e} ->
            {:error, diagnostics ++ [exception_diagnostic(e)]}

          modules when is_list(modules) ->
            safe_cleanup_modules(modules)
            {:ok, drop_phantom_redefinitions(diagnostics, source)}
        end

      {:aborted, why} ->
        Logger.warning("[credence] compile aborted: #{abort_reason_text(why)} — not analysed")

        {:error, [abort_diagnostic(why)]}
    end
  end

  # Runs the compile in a monitored child bounded by heap and wall clock.
  #
  # The child sends its result before exiting, so a `:DOWN` reaching us first
  # means it never got that far — it was killed by the heap ceiling, or the
  # source called `exit/1` on it. Either way the caller survives, which the
  # unwrapped version did not: a top-level `exit/1` used to take down whichever
  # process was running the pipeline.
  defp bounded_compile(source) do
    parent = self()
    {heap_words, timeout_ms} = compile_bounds()

    {pid, ref} =
      spawn_monitor(fn ->
        Process.flag(:max_heap_size, %{size: heap_words, kill: true, error_logger: false})

        captured =
          Code.with_diagnostics(fn ->
            try do
              Code.compile_string(source, "credence_check.ex")
            rescue
              e ->
                Logger.debug("[credence_fix] Code.compile_string raised: #{Exception.message(e)}")

                {:raised, e}
            end
          end)

        send(parent, {__MODULE__, :compiled, captured})
      end)

    receive do
      {__MODULE__, :compiled, captured} ->
        Process.demonitor(ref, [:flush])
        {:ok, captured}

      {:DOWN, ^ref, :process, _pid, :killed} ->
        {:aborted, :heap_limit}

      {:DOWN, ^ref, :process, _pid, reason} ->
        {:aborted, {:exited, reason}}
    after
      timeout_ms ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^ref, :process, _pid, _reason} -> :ok
        after
          1_000 -> :ok
        end

        {:aborted, :timeout}
    end
  end

  defp compile_bounds do
    {
      Application.get_env(:credence, :compile_max_heap_words, @compile_max_heap_words),
      Application.get_env(:credence, :compile_timeout_ms, @compile_timeout_ms)
    }
  end

  # Deliberately worded so no rule can plausibly key on it: this is credence
  # talking about itself, not a compiler diagnostic about the source. It is an
  # `:error` because "we could not compile this" and "this does not compile" are
  # the same answer to every caller that asks — notably `compiles?/1`, whose
  # `false` makes the Pattern round skip the file rather than guess.
  defp abort_diagnostic(why) do
    %{
      severity: :error,
      message: "credence: compilation aborted — #{abort_reason_text(why)}",
      position: 0,
      file: "credence_check.ex"
    }
  end

  # Each reason gets its own sentence because they are three different events,
  # and a message that calls an `exit/1` a "budget" is the kind of plausible
  # wrong sentence this project keeps finding in its own output.
  defp abort_reason_text(:heap_limit),
    do: "the source exceeded credence's compile heap ceiling"

  defp abort_reason_text(:timeout),
    do: "the source exceeded credence's compile time budget"

  defp abort_reason_text({:exited, reason}),
    do: "the source exited during compilation (#{inspect(reason)})"

  # `Code.compile_string/2` warns "redefining module M" whenever M is already
  # loaded in the calling VM. That is a property of the HOST PROCESS, not of the
  # source under analysis: the same source returns `{:ok, []}` on a cold VM and
  # a warning on a warm one.
  #
  # It matters because credence is normally called from a warm VM. The evolution
  # harness runs it via `mix run --no-compile` inside a persistent, already
  # compiled workspace, so this fired on essentially every row — and the
  # diagnostic was then offered to every Semantic rule's `match?/1`. At least one
  # evolved rule keyed on it, which is to say it was generated to repair a
  # "defect" that only exists inside the harness. It also produced findings on
  # clean files, which is how `credence check` came to exit 1 on the phantom
  # alone.
  #
  # It is not always phantom: source that genuinely defines the same module
  # twice earns the warning. The discriminator is the source rather than the
  # message — a module defined ONCE here cannot be redefining itself — so the
  # drop is conservative: if the source cannot be parsed, or the module name
  # cannot be resolved, the diagnostic is kept.
  defp drop_phantom_redefinitions(diagnostics, source) do
    if Enum.any?(diagnostics, &redefined_module/1) do
      counts = module_definition_counts(source)

      Enum.reject(diagnostics, fn d ->
        case redefined_module(d) do
          nil -> false
          name -> Map.get(counts, name, 0) == 1
        end
      end)
    else
      diagnostics
    end
  end

  @redefining_re ~r/redefining module ([A-Za-z_][A-Za-z0-9_.]*)/

  defp redefined_module(%{message: msg}) when is_binary(msg) do
    case Regex.run(@redefining_re, msg) do
      [_, name] -> name
      nil -> nil
    end
  end

  defp redefined_module(_), do: nil

  # How many times each module is defined in `source`, by written name. Returns
  # an empty map when the source does not parse, so nothing is dropped.
  defp module_definition_counts(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        ast
        |> Macro.prewalk([], fn
          {:defmodule, _, [{:__aliases__, _, parts} | _]} = node, acc ->
            {node, [Enum.map_join(parts, ".", &Atom.to_string/1) | acc]}

          node, acc ->
            {node, acc}
        end)
        |> elem(1)
        |> Enum.frequencies()

      {:error, _} ->
        %{}
    end
  end

  # Build a diagnostic map (same shape as `Code.with_diagnostics` entries) from a
  # raised compile exception, so semantic rules keyed on the message can match.
  defp exception_diagnostic(e) do
    line = if is_map(e) and is_integer(Map.get(e, :line)), do: Map.get(e, :line), else: 0
    %{severity: :error, message: Exception.message(e), position: line, file: "credence_check.ex"}
  end

  @doc """
  Returns `true` if `source` compiles without errors.

  Convenience wrapper around `compile_and_capture/1` for callers
  that only need a boolean (e.g., the Pattern phase compile gate).
  """
  @spec compiles?(String.t()) :: boolean()
  def compiles?(source) do
    match?({:ok, _}, compile_and_capture(source))
  end

  @doc """
  The set of compile *errors* `source` produces, each reduced to a signature.

  `:ok` means it compiled — the empty set. Warnings are excluded: `compiles?/1`
  has always accepted them, and a fix that trades one warning for another must
  not be reverted on that basis alone.

  A signature is `{message, occurrence}`, with no position. The occurrence
  preserves multiplicity, so adding the same error at a second location is a
  regression. Positions stay excluded because a fix may legitimately move an
  existing error from line 7 to line 6.
  """
  @spec compile_errors(String.t()) :: MapSet.t()
  def compile_errors(source) do
    case compile_and_capture(source) do
      {:ok, _diagnostics} ->
        MapSet.new()

      {:error, diagnostics} ->
        diagnostics
        |> Enum.filter(&(Map.get(&1, :severity) == :error))
        |> Enum.map(&to_string(Map.get(&1, :message, "")))
        |> Enum.frequencies()
        |> Enum.flat_map(fn {message, count} ->
          Enum.map(1..count, &{message, &1})
        end)
        |> MapSet.new()
    end
  end

  @doc """
  Whether `fixed` compiles no worse than the source that produced it, given that
  source's `baseline` error signatures (from `compile_errors/1`).

  ## Why this replaced `compiles?(fixed)`

  The Pattern round used to demand that a fixed file compile outright, and skip
  the entire round when the input did not. Both halves came from the same
  assumption, and the consequence was measured: **625 of 1,724 Pattern test
  fixtures parse but do not compile, and 292 of those have at least one Pattern
  rule firing that the pipeline refuses to run.** A single undefined helper —
  `&even?/1` with no `def even?` anywhere, which is what LLM-generated code looks
  like before anyone has written the rest of the module — disabled all 156 rules
  for that file.

  Demanding an absolute property (`it compiles`) of a repair to a file that
  never compiled is asking the wrong question. The right one is relative: did
  this fix make anything worse? So a fix is accepted when its errors are a
  subset of the errors that were already there.

  **On input that compiles this is exactly the old behaviour** — the baseline is
  empty, so the output's error set must also be empty, which is `compiles?/1`.
  The generalisation costs nothing on the path that already worked, which is why
  it is safe to make.

  It is deliberately conservative in one direction: a fix that *removes* one
  error and *introduces* a different one is rejected, even though the error
  count went down. Trading one compile error for another is not a repair the
  Pattern round is allowed to make on its own — that is the Semantic round's
  job, and it has already run by this point.
  """
  @spec compiles_no_worse?(String.t(), MapSet.t()) :: boolean()
  def compiles_no_worse?(fixed, baseline) do
    MapSet.subset?(compile_errors(fixed), baseline)
  end

  defp safe_cleanup_modules(modules) do
    for {mod, _binary} <- modules do
      # soft_purge any pre-existing old code so that delete can proceed
      # (delete fails if old code exists and cannot be purged)
      :code.soft_purge(mod)
      :code.delete(mod)
      :code.soft_purge(mod)
    end
  end

  @doc """
  Computes a line-by-line diff between two strings.

  Returns a list of `{:removed, line_no, text}` and `{:added, line_no, text}`
  tuples for every line that changed. `:removed` line numbers index `before`,
  `:added` line numbers index `after_fix`.

  ## Why a real diff, not positional pairing

  This paired the two files by INDEX — line 1 against line 1, and so on — so a
  single inserted line shifted everything after it and the whole file rendered as
  changed. That is not a cosmetic problem:

    * it **fabricated bug reports**. A correct module reorder was reported to the
      evolution harness as a "catastrophic replacement" (escalation ledger row
      181), and a human then spent the row investigating a rule that had done
      nothing wrong.
    * it was the thing **blowing the log budget**. `log_diff/3` prints this for
      every rule that changes the source, and Elixir's Logger truncates a message
      at 8096 bytes — so a whole-file render pushed the `APPLIED_RULES:` line,
      printed last, out of the log entirely (ledger row 120).

  `List.myers_difference/2` reports only the lines that actually differ. It also
  drops the old `Enum.at/2`-in-a-loop, which was quadratic in the file length.
  """
  @spec diff_lines(String.t(), String.t()) :: [
          {:removed, pos_integer(), String.t()} | {:added, pos_integer(), String.t()}
        ]
  def diff_lines(before, after_fix) do
    before_lines = String.split(before, "\n")
    after_lines = String.split(after_fix, "\n")

    {changes, _before_no, _after_no} =
      before_lines
      |> List.myers_difference(after_lines)
      |> Enum.reduce({[], 1, 1}, fn
        {:eq, lines}, {acc, before_no, after_no} ->
          {acc, before_no + length(lines), after_no + length(lines)}

        {:del, lines}, {acc, before_no, after_no} ->
          {prepend(acc, lines, before_no, :removed), before_no + length(lines), after_no}

        {:ins, lines}, {acc, before_no, after_no} ->
          {prepend(acc, lines, after_no, :added), before_no, after_no + length(lines)}
      end)

    Enum.reverse(changes)
  end

  defp prepend(acc, lines, first_no, tag) do
    lines
    |> Enum.with_index(first_no)
    |> Enum.reduce(acc, fn {text, line_no}, inner -> [{tag, line_no, text} | inner] end)
  end

  @doc """
  Invokes a Pattern rule's fix on `source`: parses to a Sourceror tree,
  calls the rule's `fix_patches/2`, applies the returned patches with
  `Sourceror.patch_string/2`, and strips per-line trailing whitespace.
  An empty patch list returns `source` unchanged.

  Used by both the orchestrator (`Credence.Pattern.run_fixable_rules/3`)
  and rule tests, so test assertions on the post-fix source string run
  through the exact bytes the pipeline ships.
  """
  @spec apply_rule_fix(module(), String.t(), keyword()) :: String.t()
  def apply_rule_fix(rule, source, opts \\ []) do
    {_status, code} = apply_rule_fix_with_status(rule, source, opts)
    code
  end

  @doc """
  Like `apply_rule_fix/3`, but says *why* the source came back unchanged.

    * `{:ok, fixed}`             — patches applied and kept
    * `{:no_patches, source}`    — the rule produced no patches for this source
    * `{:patch_rejected, source}` — patches were produced and then **discarded**
      by the safety invariants below

  That third case is the one worth naming (C5). It is the single undocumented
  exception to "every Pattern rule fixes what it finds": the finding is
  reported, the fix is dropped, and the caller sees `fixed == source` — exactly
  what a rule that simply had nothing to do looks like. The DSL gate avoids this
  by suppressing the finding whose fix it drops; this path had no such
  counterpart, so a rule could report an issue it silently never fixed and
  nothing downstream could tell.

  `Credence.Pattern.fix_with_trace/2` records it as `{rule, :patch_rejected}`,
  the sibling of `:reverted`, so the harness's bugfix lane can consume it.
  """
  @spec apply_rule_fix_with_status(module(), String.t(), keyword()) ::
          {:ok | :no_patches | :patch_rejected, String.t()}
  def apply_rule_fix_with_status(rule, source, opts \\ []) do
    opts = Keyword.put(opts, :source, source)
    ast = Sourceror.parse_string!(source)

    case drop_dsl_patches(rule.fix_patches(ast, opts), rule, ast, opts) do
      [] ->
        {:no_patches, source}

      patches when is_list(patches) ->
        fixed =
          source
          |> Sourceror.patch_string(patches)
          |> strip_trailing_ws_per_line(source)

        # Safety invariants: a fix must never ship source that does not parse,
        # and must preserve the source's comments *exactly*. A patch can
        # occasionally render invalid code (a Sourceror range that under-counts a
        # spaced operator call and strands a delimiter); it can also lose a
        # comment that sat on a rewritten/removed node (the replacement AST is
        # rendered fresh) OR duplicate one (a comment carried into the
        # re-rendered replacement while the original line, outside the patch
        # range, survives — yielding two copies). In any of these cases discard
        # the fix rather than emit broken, lossy, or doubled output — the finding
        # is still reported, it just goes unfixed. Rules that carry comments
        # through the rewrite faithfully (multiset unchanged) keep their fix.
        if parses?(fixed) and not comments_changed?(source, fixed) do
          {:ok, fixed}
        else
          {:patch_rejected, source}
        end
    end
  end

  # DSL gate, fix side: keep only the patches that do NOT land inside a macro
  # block whose semantics this rule's fix cannot preserve (`unsafe_in_dsl/0`).
  # Only the intersecting patches are dropped — a fix on plain code elsewhere in
  # the same file still lands. A rule with no DSL sensitivity skips the work.
  defp drop_dsl_patches(patches, rule, ast, opts) when is_list(patches) do
    {kept, _dropped} = dsl_partition(rule, patches, ast, opts)
    kept
  end

  defp drop_dsl_patches(other, _rule, _ast, _opts), do: other

  @doc """
  The patch ranges this rule's fix would have **dropped** inside its
  `unsafe_in_dsl/0` blocks — i.e. the regions where a finding has no surviving
  fix. The analyze-side gate (`Credence.Pattern.analyze/2`) suppresses a finding
  exactly when its line falls in one of these ranges, so a finding is reported
  iff its fix is applied. Computed from the same `fix_patches/2`,
  `DslGuard.block_ranges/2` and `DslGuard.patch_blocked?/3` the fix-side gate
  drops on, so the two gates can never disagree.
  """
  @spec dsl_dropped_ranges(module(), Macro.t(), keyword()) :: [map()]
  def dsl_dropped_ranges(rule, ast, opts) do
    # A DSL-safe rule (the large majority) can never drop a patch, so skip the
    # `fix_patches/2` computation entirely — `analyze/2` calls this for every
    # rule and would otherwise pay the fix cost on the ~9-in-10 rules that
    # declare no DSL sensitivity. `dsl_partition/4` short-circuits on the same
    # `[]`, so this only hoists that check ahead of the expensive call.
    case dsl_unsafe_families(rule) do
      [] ->
        []

      _families ->
        patches =
          try do
            rule.fix_patches(ast, opts)
          rescue
            _ -> []
          end

        {_kept, dropped} = dsl_partition(rule, List.wrap(patches), ast, opts)
        dropped
    end
  end

  # Single shared decision for both gates: split a rule's patches into the ones
  # that survive and the ranges of the ones blocked by an unsafe-family DSL block.
  defp dsl_partition(rule, patches, ast, opts) when is_list(patches) do
    case dsl_unsafe_families(rule) do
      [] ->
        {patches, []}

      families ->
        blocks = Credence.DslGuard.block_ranges(ast, opts)

        {dropped, kept} =
          Enum.split_with(patches, &Credence.DslGuard.patch_blocked?(&1, blocks, families))

        {kept, dropped |> Enum.map(&Map.get(&1, :range)) |> Enum.reject(&is_nil/1)}
    end
  end

  defp dsl_unsafe_families(rule) do
    if function_exported?(rule, :unsafe_in_dsl, 0), do: rule.unsafe_in_dsl(), else: []
  end

  # `Code.string_to_quoted/1` emits a tokenizer warning (e.g. deprecated
  # single-quoted charlists) when the source contains one. These gate checks
  # only care about the {:ok | :error} result, not the warnings — and they run
  # on every fix — so collect diagnostics instead of printing them.
  defp parses?(source) do
    {result, _diagnostics} = Code.with_diagnostics(fn -> Code.string_to_quoted(source) end)
    match?({:ok, _}, result)
  end

  # True when the fix changed the source's comment multiset in *either*
  # direction: dropped a comment (count fell — silent information loss when a
  # rewritten/removed node is re-rendered from the bare AST) or duplicated one
  # (count rose — a comment carried into a re-rendered replacement while the
  # original line outside the patch range survives). A faithful fix leaves the
  # comment multiset identical; anything else self-reverts in `apply_rule_fix`.
  defp comments_changed?(before, after_) do
    comment_multiset(before) != comment_multiset(after_)
  end

  defp comment_multiset(src) do
    {result, _diagnostics} =
      Code.with_diagnostics(fn -> Code.string_to_quoted_with_comments(src) end)

    case result do
      {:ok, _ast, comments} -> comments |> Enum.map(&String.trim(&1.text)) |> Enum.frequencies()
      _ -> %{}
    end
  end

  # `Sourceror.patch_string` re-indents multi-line replacements to match the
  # patch's start column, which can turn empty blank lines in the replacement
  # into whitespace-only lines. Collapse those all-whitespace lines to empty —
  # but ONLY the ones the patch actually introduced. A blanket whole-file pass
  # would also strip pre-existing whitespace-only lines that the patch never
  # touched, including content lines *inside* a multi-line string/heredoc
  # literal (e.g. a blank line in a doctest's expected output) far from the
  # edit — a silent content mutation. We diff the patched output against the
  # original line-by-line and normalise only inserted lines, leaving every
  # unchanged (`:eq`) line byte-for-byte.
  defp strip_trailing_ws_per_line(text, original) do
    original
    |> String.split("\n")
    |> List.myers_difference(String.split(text, "\n"))
    |> Enum.flat_map(fn
      {:eq, lines} ->
        lines

      {:del, _lines} ->
        []

      {:ins, lines} ->
        Enum.map(lines, fn line -> if String.trim(line) == "", do: "", else: line end)
    end)
    |> Enum.join("\n")
  end

  @doc """
  Returns the value bound to `:do` in a Sourceror-shaped keyword list
  (`[{{:__block__, _, [:do]}, body} | _]`).

  Returns `{:ok, body}` when present, `:error` otherwise.
  """
  @spec extract_do_body(list()) :: {:ok, term()} | :error
  def extract_do_body(kw) when is_list(kw) do
    Enum.find_value(kw, :error, fn
      {{:__block__, _, [:do]}, body} -> {:ok, body}
      _ -> nil
    end)
  end

  def extract_do_body(_), do: :error

  @doc """
  Replaces the value bound to `:do` in a Sourceror-shaped keyword list
  (`[{{:__block__, _, [:do]}, body} | _]`) with `new_body`. Returns the
  list unchanged if no `:do` entry is found.
  """
  @spec replace_do_body(list(), term()) :: list()
  def replace_do_body(kw_list, new_body) when is_list(kw_list) do
    Enum.map(kw_list, fn
      {{:__block__, _, [:do]} = k, _} -> {k, new_body}
      other -> other
    end)
  end

  @doc """
  Unwraps a Sourceror list-literal node (`{:__block__, meta, [list]}`).

  Returns `{:ok, elements, original_node}` — the second value is the
  wrapper itself so the caller can pass it to `rewrap_list/2` later to
  preserve bracket-position metadata on a rewrite.
  """
  @spec unwrap_list(term()) :: {:ok, list(), term()} | :error
  def unwrap_list({:__block__, _, [elements]} = node) when is_list(elements),
    do: {:ok, elements, node}

  def unwrap_list(_), do: :error

  @doc """
  Re-wraps a list of elements in a Sourceror `:__block__` wrapper, reusing
  the original wrapper's meta so bracket-position metadata survives the
  rewrite. Paired with `unwrap_list/1` for list-literal AST surgery.
  """
  @spec rewrap_list(term(), list()) :: term()
  def rewrap_list({:__block__, meta, [_]}, new_elements),
    do: {:__block__, meta, [new_elements]}

  @doc """
  Mechanical migration helper for rules that today do
  `source |> Sourceror.parse_string!() |> Macro.postwalk(matcher) |>
  Sourceror.to_string()`.

  Applies the `matcher` via `Macro.postwalk/2` to build a transformed
  AST, then diffs the original against the transformed and emits one
  patch per *outermost* changed subtree. Non-overlapping by construction
  — nested matches are subsumed by the outer patch.

  The rule's `fix_patches/2` becomes a one-line delegation:

      def fix_patches(ast, _opts) do
        Credence.RuleHelpers.patches_from_postwalk(ast, fn
          {target_pattern, _, _} = node -> build_replacement(node)
          node -> node
        end)
      end
  """
  @spec patches_from_postwalk(Macro.t(), (Macro.t() -> Macro.t())) :: [map()]
  def patches_from_postwalk(ast, matcher) when is_function(matcher, 1) do
    transformed = Macro.postwalk(ast, matcher)
    diff_patches(ast, transformed)
  end

  @doc """
  Emits patches by AST-diffing `original` against a pre-computed
  `transformed` AST. Use when the transformation can't be expressed
  as a single `Macro.postwalk/2` matcher — e.g. it prunes nodes,
  reorders siblings, or needs cross-clause information.

  The transformed AST should be built by walking `original` (so that
  unchanged subtrees retain their Sourceror metadata for range lookup);
  replacement subtrees can be freshly synthesized without metadata —
  the diff uses the *original* node's range.
  """
  @spec patches_from_diff(Macro.t(), Macro.t()) :: [map()]
  def patches_from_diff(original, transformed) do
    diff_patches(original, transformed)
  end

  @doc """
  Applies an AST-to-AST `transform_fn`, then emits patches via
  AST-diff between the original AST and a *re-parsed* version of the
  rendered output.

  The re-parse step gives the transformed AST clean Sourceror metadata
  (literal wrappers, ranges) so the diff lines up structurally with
  the original. This is needed when a rule's transformation produces
  fresh subtrees with bare-literal shape that wouldn't otherwise match
  the original Sourceror-wrapped shape.

  Returns `[]` if the transformation produced an identical AST.
  Falls back to a whole-source patch when re-parsing fails (rare —
  typically signals the transform produced invalid code).
  """
  @spec patches_from_ast_transform(Macro.t(), String.t(), (Macro.t() -> Macro.t())) :: [map()]
  def patches_from_ast_transform(ast, source, transform_fn) when is_function(transform_fn, 1) do
    transformed = transform_fn.(ast)

    if transformed == ast do
      []
    else
      rendered = Sourceror.to_string(transformed)

      case Sourceror.parse_string(rendered) do
        {:ok, fresh_ast} -> diff_patches(ast, fresh_ast)
        {:error, _} -> whole_source_patch(source, rendered)
      end
    end
  end

  # Walks original and transformed ASTs in parallel. When the structural
  # shape matches, recurses into children. When the shape diverges (or
  # values differ at a leaf), emits a single patch covering the original
  # node's range. Result: patches at the *outermost* point of divergence,
  # never nested.

  # Skip any node whose structure is unchanged ignoring metadata: it differs only
  # in layout (the transform re-rendered it via `Sourceror.to_string`), so leaving
  # it untouched preserves its original source rather than reformatting code the
  # rule never meant to change.
  defp diff_patches(orig, modified) do
    if orig == modified or strip_all_meta(orig) == strip_all_meta(modified) do
      []
    else
      diff_patches_structural(orig, modified)
    end
  end

  # `:__block__` wrappers around a single literal leaf (string, atom,
  # number) carry no source position of their own beyond the wrapper.
  # If the wrapped value changed, the patch must land at the wrapper's
  # range — recursing into the args list would drop us at a bare literal
  # with no range, losing the patch.
  defp diff_patches_structural(
         {:__block__, _, [val_o]} = orig,
         {:__block__, _, [val_m]} = modified
       )
       when val_o != val_m and not is_tuple(val_o) and not is_list(val_o) do
    case node_range(orig) do
      nil -> []
      range -> [%{range: range, change: render_replacement(modified, range)}]
    end
  end

  # A `:__block__` wrapping a *list* literal. Only the wrapper carries the
  # bracket positions — `line`/`column` for `[`, `closing` for `]`. The bare
  # list underneath has no metadata of its own, so `node_range/1` synthesizes
  # its range from its first and last elements and it comes out
  # bracket-*exclusive*, while `Sourceror.to_string/1` renders a list
  # bracket-*inclusive*. Recursing to the bare list and patching there
  # therefore writes the brackets a second time:
  #
  #     call(:name, [:a, :b, :c])  ->  call(:name, [[:a, :c]])
  #
  # which parses and preserves every comment, so the safety invariants in
  # `apply_rule_fix_with_status/3` pass it straight through (docs/22 T5.10).
  #
  # Same-length lists still recurse: each element carries its own range, so
  # element-wise patches are tighter and leave the surrounding layout alone.
  # Only when the shape changes — an element added or removed, or the list
  # replaced by a non-list — must the patch cover the list as a whole, and
  # then it has to land at the *wrapper's* bracket-inclusive range.
  defp diff_patches_structural(
         {:__block__, _, [val_o]} = orig,
         {:__block__, _, [val_m]} = modified
       )
       when is_list(val_o) do
    if is_list(val_m) and length(val_o) == length(val_m) do
      diff_patches(val_o, val_m)
    else
      whole_node_patch(orig, modified)
    end
  end

  # Same 3-tuple shape with same arity — recurse into args. (Form must
  # be deeply equal too: an atom-form vs tuple-form is structurally
  # different and should patch the whole node.)
  defp diff_patches_structural({form, _, args_o}, {form, _, args_m})
       when is_list(args_o) and is_list(args_m) and length(args_o) == length(args_m) do
    args_o
    |> Enum.zip(args_m)
    |> Enum.flat_map(fn {o, m} -> diff_patches(o, m) end)
  end

  # A `:__block__` whose statement count changed — a sibling statement/def was
  # added or removed (e.g. a rule that deletes a `defp` or de-duplicates a
  # clause). Align the structurally-equal siblings and patch only what changed,
  # instead of re-rendering — and thereby reformatting (comment indentation,
  # blank lines, `def ..., do:` layout) — the whole block. Restricted to blocks
  # because their statements are line-occupying, so a removed one can be deleted
  # whole-line; inline sibling lists (call args, tuples) fall through to the
  # whole-node render below, which is small and already correct. Falls back for
  # anything that can't be aligned cleanly.
  defp diff_patches_structural({:__block__, _, args_o} = orig, {:__block__, _, args_m} = modified)
       when is_list(args_o) and is_list(args_m) do
    case aligned_patches(args_o, args_m) do
      {:ok, patches} -> patches
      :fallback -> whole_node_patch(orig, modified)
    end
  end

  # Lists of the same length — zip and recurse.
  defp diff_patches_structural([_ | _] = orig, [_ | _] = modified)
       when length(orig) == length(modified) do
    orig
    |> Enum.zip(modified)
    |> Enum.flat_map(fn {o, m} -> diff_patches(o, m) end)
  end

  # 2-tuples (keyword pair etc.) — recurse on each side.
  defp diff_patches_structural({a_o, b_o}, {a_m, b_m}) do
    diff_patches(a_o, a_m) ++ diff_patches(b_o, b_m)
  end

  # Structures diverge here — emit one patch covering the original
  # node's range. Skip if the original is a leaf without a range
  # (Sourceror can't pinpoint bare literals/atoms).
  defp diff_patches_structural(orig, modified) do
    case node_range(orig) do
      nil ->
        []

      range ->
        [%{range: range, change: render_replacement(modified, range)}]
    end
  end

  defp whole_node_patch(orig, modified) do
    case node_range(orig) do
      nil -> []
      range -> [%{range: range, change: render_replacement(modified, range)}]
    end
  end

  # Align two same-form-but-different-length sibling lists by structural
  # (metadata-insensitive) equality and emit minimal patches: recurse into
  # siblings changed in place, delete removed ones whole-line. Returns
  # `:fallback` for any shape we can't place safely (net insertions, rangeless
  # nodes, or an unexpected error) so the caller re-renders the whole parent.
  defp aligned_patches(orig, modified) do
    stripped_o = Enum.map(orig, &strip_all_meta/1)
    stripped_m = Enum.map(modified, &strip_all_meta/1)

    stripped_o
    |> List.myers_difference(stripped_m)
    |> walk_ops(orig, modified, 0, 0, [])
  rescue
    _ -> :fallback
  end

  defp walk_ops([], _orig, _modified, _io, _im, acc), do: {:ok, acc}

  defp walk_ops([{:eq, els} | rest], orig, modified, io, im, acc) do
    n = length(els)
    walk_ops(rest, orig, modified, io + n, im + n, acc)
  end

  # A deletion immediately followed by an insertion. Only an *equal-count* gap is
  # an unambiguous in-place modification — pair the siblings positionally and
  # recurse. An unequal gap mixes modifications with deletions/insertions whose
  # correspondence a sequence diff can't resolve (it has no unchanged sibling to
  # anchor on), so positional pairing would mis-align; fall back to a whole-node
  # render there.
  defp walk_ops([{:del, dl}, {:ins, il} | rest], orig, modified, io, im, acc) do
    dn = length(dl)
    inn = length(il)

    if dn == inn do
      paired =
        Enum.flat_map(0..(dn - 1)//1, fn i ->
          diff_patches(Enum.at(orig, io + i), Enum.at(modified, im + i))
        end)

      walk_ops(rest, orig, modified, io + dn, im + dn, acc ++ paired)
    else
      # An N→1 collapse (several function clauses folded into one `Enum.reduce`):
      # replace just the changed span — the deleted originals' combined source
      # range — with the single replacement node, so sibling statements outside
      # the span keep their exact source (no whole-block re-render/reformat).
      # Other unequal gaps (N→M, M>1) need inter-statement spacing that only a
      # full re-render reproduces, so they fall back.
      if inn == 1 do
        case span_patch(Enum.slice(orig, io, dn), Enum.at(modified, im)) do
          {:ok, patch} -> walk_ops(rest, orig, modified, io + dn, im + inn, acc ++ [patch])
          :fallback -> :fallback
        end
      else
        :fallback
      end
    end
  end

  defp walk_ops([{:del, dl} | rest], orig, modified, io, im, acc) do
    case deletion_patches(Enum.slice(orig, io..(io + length(dl) - 1)//1)) do
      {:ok, dels} -> walk_ops(rest, orig, modified, io + length(dl), im, acc ++ dels)
      :fallback -> :fallback
    end
  end

  # A bare insertion — fall back (no safe anchor to place it at).
  defp walk_ops([{:ins, _} | _], _orig, _modified, _io, _im, _acc), do: :fallback

  # Replace the combined source range of `del_nodes` with `ins_node` rendered,
  # leaving everything else (including the blank line after the span) untouched.
  # `:fallback` if the span has no resolvable range.
  defp span_patch(del_nodes, ins_node) do
    case range_from(List.first(del_nodes), List.last(del_nodes)) do
      nil -> :fallback
      range -> {:ok, %{range: range, change: render_replacement(ins_node, range)}}
    end
  end

  # Delete each node by removing its whole line span (from column 1 of its first
  # line through column 1 of the line after its last) so no blank-but-indented
  # remnant is left. Falls back if any node lacks a range.
  defp deletion_patches(nodes) do
    Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, acc} ->
      case node_range(node) do
        %Sourceror.Range{start: s, end: e} ->
          patch = %{
            range: %{start: [line: s[:line], column: 1], end: [line: e[:line] + 1, column: 1]},
            change: ""
          }

          {:cont, {:ok, [patch | acc]}}

        _ ->
          {:halt, :fallback}
      end
    end)
    |> case do
      {:ok, patches} -> {:ok, Enum.reverse(patches)}
      other -> other
    end
  end

  defp strip_all_meta(node) do
    Macro.prewalk(node, fn
      {form, meta, args} when is_list(meta) -> {form, [], args}
      other -> other
    end)
  end

  defp node_range(node) when is_tuple(node) and tuple_size(node) == 3 do
    case Sourceror.get_range(node) do
      %Sourceror.Range{} = r -> r
      _ -> nil
    end
  end

  # Lists and 2-tuples have no Sourceror metadata of their own, but we
  # can synthesize a range from their first and last children. Needed
  # when `diff_patches` hits a divergence at a list pattern (e.g. a
  # `case` clause's `[a, b, c]` rewritten to `[_, _, _] = items`).
  defp node_range([_ | _] = list) do
    range_from(List.first(list), List.last(list))
  end

  defp node_range({a, b}) do
    range_from(a, b)
  end

  defp node_range(_), do: nil

  defp range_from(first, last) do
    case {node_range(first), node_range(last)} do
      {%Sourceror.Range{} = f, %Sourceror.Range{} = l} ->
        %Sourceror.Range{start: f.start, end: l.end}

      _ ->
        nil
    end
  end

  defp whole_source_patch(original_source, new_source) do
    lines = String.split(original_source, "\n")
    end_line = max(length(lines), 1)
    end_col = (lines |> List.last() |> byte_size()) + 1

    [
      %{
        range: %{start: [line: 1, column: 1], end: [line: end_line, column: end_col]},
        change: new_source
      }
    ]
  end

  @doc """
  Renders a replacement subtree as source text suitable for patching
  back into the original source at `original_range`'s position.

  Uses Sourceror's default `line_length: 98`. Pass `:line_length` to
  override — e.g. when a rule wants to force a multi-line replacement
  to mirror a multi-line original (the original Issue 4 trick).

  `original_range` is currently unused but reserved as a hint for
  future rule-specific budget heuristics.
  """
  @spec render_replacement(Macro.t(), map(), keyword()) :: String.t()
  def render_replacement(new_ast, _original_range, opts \\ []) do
    new_ast
    |> strip_layout_meta()
    |> Sourceror.to_string(opts)
  end

  @doc """
  Does this expression provably evaluate to a boolean?

  Conservative on purpose: `true` only for shapes whose result is a boolean for
  every input — comparison and strict-equality operators, `and`/`or` over two
  boolean operands, `not`, `is_nil/1`, `match?/2`, and the boolean-returning
  `Enum` predicates (`all?`, `any?`, `empty?`) in both call and piped form.
  Anything else, including a bare variable or a user function, is `false`.

  A rule uses this before rewriting an `if` whose branches are `true`/`false`
  into its own condition: the rewrite is only equivalent when the condition
  already *is* a boolean, since `if` treats every non-`nil`/`false` value as
  truthy and would otherwise turn, say, `0` or `""` into `true`.

  Extracted from `NoIfTrueFalse` and `PreferNegateIfTrueFalse`, which carried
  byte-identical 69-line private copies (docs/12 C11). Their sibling predicate
  `boolean_expr?/1` was copied the same way and has since **drifted** — the
  original grew a clause for a nested `if`, the copy did not, while a comment
  in the copy still claimed the two mirror each other.
  """
  @spec boolean_condition?(Macro.t()) :: boolean()
  def boolean_condition?({:__block__, _, [expr]}), do: boolean_condition?(expr)

  def boolean_condition?({op, _, [_, _]})
      when op in [:==, :!=, :<, :>, :<=, :>=, :===, :!==, :match?],
      do: true

  def boolean_condition?({op, _, [left, right]}) when op in [:and, :or],
    do: boolean_condition?(left) and boolean_condition?(right)

  def boolean_condition?({:not, _, [inner]}), do: boolean_condition?(inner)
  def boolean_condition?({:is_nil, _, [_]}), do: true

  def boolean_condition?({{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, _})
      when fun in [:all?, :any?, :empty?],
      do: true

  def boolean_condition?({:|>, _, [_, {{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, _}]})
      when fun in [:all?, :any?, :empty?],
      do: true

  def boolean_condition?(_), do: false

  @doc """
  The comments stored on `node`'s Sourceror metadata under `key`
  (`:leading_comments` or `:trailing_comments`); `[]` for a node without them.
  """
  @spec node_comments(Macro.t(), :leading_comments | :trailing_comments) :: list()
  def node_comments({_form, meta, _args}, key) when is_list(meta), do: Keyword.get(meta, key, [])
  def node_comments(_node, _key), do: []

  @doc """
  A whole-line deletion patch for `node` — removes its full line span (column 1
  of its first line through column 1 of the line after its last), so no
  blank-but-indented remnant is left. Returns `nil` if `node` has no range. Use
  for a fix that removes a statement/clause without re-rendering its siblings.
  """
  @spec deletion_patch(Macro.t()) :: map() | nil
  def deletion_patch(node) do
    case node_range(node) do
      %Sourceror.Range{start: s, end: e} ->
        %{
          range: %{start: [line: s[:line], column: 1], end: [line: e[:line] + 1, column: 1]},
          change: ""
        }

      _ ->
        nil
    end
  end

  @doc """
  Every comment (leading and trailing, at any depth) within `node`'s subtree, in
  roughly document order. Use to rescue the comments of a node a fix discards.
  """
  @spec collect_comments(Macro.t()) :: list()
  def collect_comments(node) do
    {_node, acc} =
      Macro.prewalk(node, [], fn
        {_form, meta, _args} = n, acc when is_list(meta) ->
          {n,
           acc ++
             Keyword.get(meta, :leading_comments, []) ++
             Keyword.get(meta, :trailing_comments, [])}

        n, acc ->
          {n, acc}
      end)

    acc
  end

  @doc """
  Carry comments onto `node`: `leading` is prepended to its leading comments,
  `trailing` appended to its trailing comments. Used when a fix replaces one or
  more nodes with `node` and must not drop the comments that sat on them. A node
  without metadata (a bare literal) is returned unchanged.
  """
  @spec carry_comments(Macro.t(), list(), list()) :: Macro.t()
  def carry_comments({form, meta, args}, leading, trailing) when is_list(meta) do
    # Carried comments keep their original (now-stale) line, which Sourceror uses
    # to position them — re-line them just before/after the target so leading
    # renders before it and trailing after.
    line = Keyword.get(meta, :line)
    leading = reline(leading, line && line - 1)
    trailing = reline(trailing, line && line + 1)

    meta =
      meta
      |> Keyword.update(:leading_comments, leading, &(leading ++ &1))
      |> Keyword.update(:trailing_comments, trailing, &(&1 ++ trailing))

    {form, meta, args}
  end

  def carry_comments(node, _leading, _trailing), do: node

  defp reline(comments, nil), do: comments
  defp reline(comments, line), do: Enum.map(comments, &Map.put(&1, :line, line))

  # Sourceror infers layout (single-line vs. multi-line) from each node's
  # `line`/`column` metadata — a wide line span forces multi-line. When
  # a rule builds a replacement subtree by reusing original subnodes
  # (with their original line positions) inside a freshly-synthesized
  # outer node (no line meta), Sourceror sees a wide span and wraps
  # unnecessarily. Stripping just `:line` and `:column` lets Sourceror
  # fall back to length-based layout, while preserving `:end_of_expression`
  # (blank-line spacing) and `:closing` (bracket positions).
  defp strip_layout_meta(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} when is_list(meta) ->
        # Sourceror positions comments by line, so a node carrying a comment must
        # keep its :line/:column or the comment is silently dropped on render.
        # Such nodes are inherently multi-line anyway, so keeping their position
        # does not cause the spurious wrapping the strip is meant to avoid.
        to_drop =
          if has_comments?(meta),
            do: [:closing, :last, :end],
            else: [:line, :column, :closing, :last, :end]

        {form, Keyword.drop(meta, to_drop), args}

      other ->
        other
    end)
  end

  defp has_comments?(meta) do
    Keyword.get(meta, :leading_comments, []) != [] or
      Keyword.get(meta, :trailing_comments, []) != []
  end

  @doc """
  Logs a before/after diff under a `[credence_fix]` prefix.

  Shows every changed line — the diff is never truncated so that the
  full extent of each fix is visible in the log output.
  """
  @spec log_diff(String.t(), String.t(), String.t()) :: :ok
  def log_diff(label, before, after_fix) do
    changes = diff_lines(before, after_fix)

    change_summary =
      Enum.map_join(changes, "\n", fn
        {:removed, line_no, text} -> "  L#{line_no} - #{String.trim_trailing(text)}"
        {:added, line_no, text} -> "  L#{line_no} + #{String.trim_trailing(text)}"
      end)

    Logger.debug("[credence_fix] #{label}: source CHANGED:\n#{change_summary}")
  end
end
