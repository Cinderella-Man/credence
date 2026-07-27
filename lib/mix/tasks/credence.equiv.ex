defmodule Mix.Tasks.Credence.Equiv do
  @shortdoc "Classify a before/after rewrite: EQUIVALENT | REPAIR | DIVERGES"

  @moduledoc """
  Classify-time behavioural-equivalence pre-check (Tunex `07` §3.11, `08` T1.4).

  Given a `before` expression and a proposed `after` expression (the rewrite,
  NOT a whole module — this is the expression-level / T1 check, the dominant
  case and where ~all `followup.md` divergences live), run both over a curated
  adversarial battery and emit a **trichotomy** verdict:

      MIX_ENV=test mix credence.equiv --before b.exs --after a.exs --vars s

    * **EQUIVALENT** — same outcome (strict `===`, or same exception class) on
      every admitted input. With `--minimal-set`, also reports the minimal
      assumption switch set that makes it so (`[]` = no-promise / strict-safe).
    * **REPAIR** — `before` *raises on every* input and `after` returns a value
      on ≥1. The before has no valid output, so the fix is a correction, not a
      behaviour change (the `mark_equivalence_repair` family). Prints the
      exception class + `N/N raised` for the implementer's reason string.
    * **DIVERGES** — `before` produced a valid value on some input that `after`
      disagrees with (a real behaviour change), or `after` does not compile.

  ## Run env

  🔴 **Must run under `MIX_ENV=test`** — it reuses `Credence.BehaviourEquivalence`
  (`eval_outcome/2`) + the curated `Credence.EquivalenceInputs` battery, both of
  which live in `test/support/` (compiled only under `:test`). The task aborts
  with guidance otherwise. (Dynamic dispatch is used for those two modules so the
  task still *compiles* clean under `:dev`.)

  ## Options

    * `--before FILE` / `--after FILE` — the two expression snippets (required).
    * `--vars a,b` — ordered free-var names of the expression (required).
    * `--dim d1,d2` — `EquivalenceInputs` dimension(s) to run (default: all that
      fit the var count). Names: term_lists, signed_integers, unicode_strings,
      single_codepoint_strings, multi_codepoint_strings, stability_lists, maps,
      keyword_lists, tuples, mixed_numeric.
    * `--inputs-file FILE` — an Elixir term (a list) overriding the battery; for
      multi-var, each element is a tuple/list of positional args. (The escape
      hatch for the unresolved multi-var input-set question.)
    * `--assumptions a,b` — run in that admitted domain (filters the battery).
    * `--minimal-set` — report the minimal switch set making before ≡ after.
    * `--compare-messages` — compare exception messages too (default: class only).

  Determinism: fixed battery, never StreamData. Names no rule.
  """

  use Mix.Task

  @switches [
    before: :string,
    after: :string,
    vars: :string,
    dim: :string,
    inputs_file: :string,
    assumptions: :string,
    minimal_set: :boolean,
    compare_messages: :boolean
  ]

  # Dimensions that carry multi-codepoint graphemes — dropped from the admitted
  # domain when `single_codepoint_graphemes` is promised.
  @multi_codepoint_dims [:multi_codepoint_strings, :unicode_strings]
  @all_string_dims [:unicode_strings, :single_codepoint_strings, :multi_codepoint_strings]
  # C2.1. `maps`/`keyword_lists`/`tuples`/`mixed_numeric` close the gaps the
  # original battery left: the Map-vs-Keyword duplicate-key divergence, tuple
  # arity, and the int/float traps that survive `==`. C2.2's dimension-mapping
  # meta-test keys on this list, and H3's `--dim` inference reads it.
  @collection_dims [:maps, :keyword_lists, :tuples, :mixed_numeric]
  @all_dims [:term_lists, :signed_integers, :stability_lists] ++
              @all_string_dims ++ @collection_dims

  @impl Mix.Task
  def run(argv) do
    ensure_test_env!()
    # We reuse the test/support eval primitive + a capture_io-based warning
    # silencer; both need ExUnit's CaptureServer running. Start it WITHOUT
    # autorun so no test suite kicks off at task exit.
    ExUnit.start(autorun: false)
    {opts, _, _} = OptionParser.parse(argv, strict: @switches)

    before = File.read!(req(opts, :before))
    after_src = File.read!(req(opts, :after))
    vars = req(opts, :vars) |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    compare_messages? = Keyword.get(opts, :compare_messages, false)

    base_inputs = base_inputs(opts, vars)

    if Keyword.get(opts, :minimal_set, false) do
      run_minimal_set(before, after_src, vars, base_inputs, compare_messages?)
    else
      dims_or_inputs = filter_for_assumptions(base_inputs, parse_assumptions(opts))
      verdict = classify(before, after_src, vars, dims_or_inputs, compare_messages?)
      Mix.shell().info(format(verdict))
    end
  end

  # ── Verdict ───────────────────────────────────────────────────────────

  # Returns one of:
  #   :equivalent
  #   {:repair, exc_module, n_raised, n_total}
  #   {:diverges, input, before_outcome, after_outcome}
  #   {:diverges_compile, reason}
  defp classify(before, after_src, vars, inputs, compare_messages?) do
    with {:ok, before_fn} <- compile_fn(vars, before),
         {:ok, after_fn} <- compile_fn(vars, after_src) do
      pairs =
        for input <- inputs do
          args = to_args(input, vars)
          ob = eval(fn -> apply(before_fn, args) end, compare_messages?)
          oa = eval(fn -> apply(after_fn, args) end, compare_messages?)
          {input, ob, oa}
        end

      cond do
        Enum.all?(pairs, fn {_i, ob, oa} -> ob === oa end) ->
          :equivalent

        repair?(pairs) ->
          raised = Enum.filter(pairs, fn {_i, ob, _oa} -> match?({:raise, _}, ob) end)
          {:raise, exc} = elem(hd(raised), 1)
          {:repair, exc, length(raised), length(pairs)}

        true ->
          {input, ob, oa} = Enum.find(pairs, fn {_i, ob, oa} -> ob !== oa end)
          {:diverges, input, ob, oa}
      end
    else
      {:error, reason} -> {:diverges_compile, reason}
    end
  end

  # REPAIR iff `before` raised on EVERY input and `after` succeeded on ≥1 — the
  # before has no valid output on any input, so the fix is a correction.
  defp repair?(pairs) do
    Enum.all?(pairs, fn {_i, ob, _oa} -> match?({:raise, _}, ob) end) and
      Enum.any?(pairs, fn {_i, _ob, oa} -> match?({:ok, _}, oa) end)
  end

  # ── Minimal switch set ──────────────────────────────────────────────────

  defp run_minimal_set(before, after_src, vars, base_inputs, compare_messages?) do
    # Strict: the full battery, no promise.
    case classify(before, after_src, vars, base_inputs, compare_messages?) do
      :equivalent ->
        Mix.shell().info("EQUIVALENT minimal_set=[]")

      strict_verdict ->
        # Try each single switch: filter the battery to its admitted domain.
        switch =
          Enum.find(known_switches(), fn sw ->
            inputs = filter_for_assumptions(base_inputs, [sw])
            classify(before, after_src, vars, inputs, compare_messages?) == :equivalent
          end)

        if switch do
          Mix.shell().info("EQUIVALENT minimal_set=[#{switch}]")
        else
          # No single switch rescues it — report the strict verdict (a bug, or a
          # repair, or needs a new/combined switch a human must judge).
          Mix.shell().info("#{format(strict_verdict)} minimal_set=none")
        end
    end
  end

  # ── Inputs / assumptions ────────────────────────────────────────────────

  defp base_inputs(opts, vars) do
    cond do
      file = opts[:inputs_file] ->
        {term, _} = Code.eval_string(File.read!(file))
        term

      opts[:dim] ->
        opts[:dim]
        |> String.split(",", trim: true)
        |> Enum.flat_map(&dim(String.trim(&1)))

      true ->
        # Default battery: all dimensions (single-var snippets take each value
        # directly; multi-var must pass --dim/--inputs-file with matching shape).
        if length(vars) == 1, do: Enum.flat_map(@all_dims, &dim/1), else: []
    end
  end

  # Drop promise-violating inputs for the admitted domain. Currently only
  # `single_codepoint_graphemes` shrinks the battery (drops multi-codepoint
  # string dims). `proper_lists` has no improper-list dimension to drop, so it
  # is a no-op on this battery (documented — grow EquivalenceInputs if needed).
  defp filter_for_assumptions(inputs, assumptions) do
    if :single_codepoint_graphemes in assumptions do
      drop = Enum.flat_map(@multi_codepoint_dims, &dim/1) |> MapSet.new()
      Enum.reject(inputs, &MapSet.member?(drop, &1))
    else
      inputs
    end
  end

  defp parse_assumptions(opts) do
    (opts[:assumptions] || "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.to_atom(String.trim(&1)))
  end

  defp known_switches do
    Credence.Assumptions.names()
  end

  # Dimension name → its input list (dynamic dispatch: EquivalenceInputs is a
  # test/support module, absent under :dev; the task only runs under :test).
  defp dim(name) when is_binary(name), do: dim(String.to_atom(name))
  defp dim(name) when is_atom(name), do: apply(Credence.EquivalenceInputs, name, [])

  # ── Compile + eval ──────────────────────────────────────────────────────

  defp compile_fn(vars, expr) do
    arglist = Enum.join(vars, ", ")
    code = "fn #{arglist} -> (#{String.trim(expr)}) end"

    silence(fn ->
      {result, diagnostics} =
        Code.with_diagnostics(fn ->
          try do
            {fun, _} = Code.eval_string(code)
            {:ok, fun}
          rescue
            e -> {:error, e}
          end
        end)

      case result do
        {:ok, fun} ->
          {:ok, fun}

        {:error, e} ->
          # Surface the REAL compiler diagnostics (e.g. `undefined function
          # do_count/3`). A bare `CompileError` only says "nofile: cannot compile
          # file (errors have been logged)" — the actual errors go to the
          # diagnostics, which `silence/1` would otherwise discard.
          detail =
            diagnostics
            |> Enum.map(&Map.get(&1, :message, ""))
            |> Enum.reject(&(&1 in [nil, ""]))
            |> Enum.join("; ")

          msg = if detail == "", do: Exception.message(e), else: detail
          {:error, "does not compile: #{msg}"}
      end
    end)
  end

  defp eval(thunk, compare_messages?) do
    # Dynamic dispatch (not a direct call): BehaviourEquivalence is a
    # test/support module, absent under :dev, so a static call would warn
    # "undefined function" at compile time. The task only runs under :test.
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    apply(Credence.BehaviourEquivalence, :eval_outcome, [thunk, compare_messages?])
  end

  defp to_args(_input, []), do: []

  defp to_args(input, vars) do
    cond do
      length(vars) == 1 -> [input]
      is_tuple(input) -> Tuple.to_list(input)
      is_list(input) -> input
      true -> [input]
    end
  end

  defp silence(fun) do
    ExUnit.CaptureIO.capture_io(:stderr, fn -> send(self(), {:silenced, fun.()}) end)

    receive do
      {:silenced, result} -> result
    end
  end

  # ── Output ──────────────────────────────────────────────────────────────

  defp format(:equivalent), do: "EQUIVALENT"
  defp format({:repair, exc, n, total}), do: "REPAIR #{inspect(exc)} #{n}/#{total}"

  defp format({:diverges, input, ob, oa}),
    do: "DIVERGES input=#{inspect(input)} before=#{inspect(ob)} after=#{inspect(oa)}"

  defp format({:diverges_compile, reason}), do: "DIVERGES after-#{reason}"

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp req(opts, key) do
    Keyword.get(opts, key) ||
      Mix.raise("--#{key} is required (see `mix help credence.equiv`)")
  end

  defp ensure_test_env! do
    unless Mix.env() == :test do
      Mix.raise("""
      credence.equiv must run under MIX_ENV=test — it reuses the test/support
      behaviour-equivalence battery (BehaviourEquivalence + EquivalenceInputs),
      which is not compiled under :#{Mix.env()}.
      Run: MIX_ENV=test mix credence.equiv ...
      """)
    end
  end
end
