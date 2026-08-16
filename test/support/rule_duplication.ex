defmodule Credence.RuleDuplication do
  @moduledoc """
  The mechanical duplicate signal behind `RuleDuplicationTest` (docs/12 C11).

  Two rules are duplicates when one could be deleted without changing what
  Credence does. Nothing here proves that — it is undecidable in general — so
  this module computes two cheap signals that a genuine duplicate must satisfy
  **both** of, and the gate fires only on their intersection.

  ## Signal 1 — signature overlap

  A rule's signature is the set of **atom literals in its source**, moduledoc
  stripped. Those are the module and function names it keys on: the `:Enum`
  inside `{:__aliases__, _, [:Enum]}`, the `:map` beside it. What a rule
  *targets* shows up as atoms; its own machinery (`Enum.map/2`, `Sourceror.*`)
  shows up as **calls**, which is what separates the two.

  The obvious signature — the qualified `Module.fun` calls in a rule's source —
  does not work, and is recorded here so nobody rebuilds it: scoring on those
  gives 133 pairs at Jaccard >= 0.6, with `prefer_explicit_binary_arithmetic` ~
  `prefer_regex_match` at a perfect 1.0, because both are written with the same
  `Enum`/`Sourceror` plumbing. Scoring on matched atoms gives 19.

  The rule's **own name atom** is excluded. It is present in every rule by
  construction (the `%Issue{rule: :name}` literal), so leaving it in can only
  ever lower the score between two rules, never raise it — measured on the one
  known-genuine duplicate this project has retired, `no_list_delete_at_length` ~
  `no_list_delete_at_with_length`: **0.778 with the names in, 0.875 without**,
  and the only atoms that differed were the two names themselves.

  ## Signal 2 — firing-set containment

  The corpus is each Pattern rule's own `## Bad` example (111 of 156 rules have
  one that parses). Every snippet is, by construction, an input some author
  intended a rule to fire on, so it is a shared adversarial corpus that costs
  nothing to maintain — it grows with the rule set.

  `A` contains `B` when every snippet `B` fires on, `A` fires on too, and `B`
  fires on at least one. Alone this signal is weak: with 111 snippets a rule
  that fires on exactly one is contained by anything that happens to fire on
  the same one, which is how it reported `RemoveUnreachableClausesAfterCatchall`
  containing `NoDocFalseOnPrivate` — two rules with nothing to do with each
  other.

  ## Why the intersection, and why 0.6

  Neither signal is trustworthy alone: signature overlap says two rules talk
  about the same functions, containment says one out-fires the other on a small
  corpus. Together they say *this rule keys on the same thing as that one and
  never catches anything it misses*, which is the shape of a real duplicate.

  The threshold is 0.6 because that is **below** the whole benign band, not
  because it produced a convenient answer. Measured: the three pairs the
  intersection reports today score 0.63, 0.63 and 0.67, and all three were
  triaged benign (see the ledger in the gate). Raising the threshold to 0.7
  empties the ledger — and that is exactly the move T3.10a warns against, a
  number chosen for its output rather than its meaning. The retired genuine
  duplicate scores 0.875, so a threshold anywhere up to that catches it; 0.6
  keeps the three known pairs visible so a *fourth* has to be looked at.
  """

  @noise [
    :do,
    :else,
    :ok,
    :error,
    :__block__,
    :__aliases__,
    :line,
    :column,
    :source,
    :rule,
    :message,
    :meta
  ]

  @doc "Signature of the rule module `rule`, read from its source file."
  def signature(rule) do
    %{rule_path: path, snake: own} = Credence.RuleName.from_module(rule)
    path |> File.read!() |> signature_from_source(own)
  end

  @doc """
  Signature of rule `source`, excluding `own_name` (a string or atom).

  Split out from `signature/1` so the gate's positive control can score
  fabricated rule sources that are not on disk and are not discoverable.
  """
  def signature_from_source(source, own_name) do
    own = if is_atom(own_name), do: own_name, else: String.to_atom(own_name)

    {_ast, atoms} =
      source
      |> strip_moduledoc()
      |> Sourceror.parse_string!()
      |> Macro.prewalk(MapSet.new(), fn
        {:__block__, _, [a]} = node, acc when is_atom(a) -> {node, MapSet.put(acc, a)}
        node, acc -> {node, acc}
      end)

    MapSet.reject(atoms, &(&1 == own or &1 in @noise or is_boolean(&1) or is_nil(&1)))
  end

  # Prose mentions the idiom too — `Enum.map` appears in the ## Bad block of
  # every rule about `Enum.map` — so leaving the moduledoc in would make every
  # rule about a function look like every other rule about it.
  defp strip_moduledoc(source) do
    case Regex.run(~r/@moduledoc\s+"""(.*?)"""/s, source) do
      [full, _] -> String.replace(source, full, "@moduledoc false")
      _ -> source
    end
  end

  @doc "Jaccard similarity of two signatures; 0.0 when both are empty."
  def jaccard(a, b) do
    case MapSet.union(a, b) |> MapSet.size() do
      0 -> 0.0
      union -> MapSet.intersection(a, b) |> MapSet.size() |> Kernel./(union)
    end
  end

  @doc """
  The shared corpus: each rule's own `## Bad` example, as `{source, ast}`.

  Snippets that do not parse are dropped rather than raising — a rule whose Bad
  block is prose or a fragment should not be able to break the gate for every
  other rule.
  """
  def corpus(rules) do
    for rule <- rules,
        snippet = bad_example(rule),
        snippet not in [nil, ""],
        {:ok, ast} <- [Sourceror.parse_string(snippet)],
        do: {snippet, ast}
  end

  @doc "The `## Bad` block of `rule`'s moduledoc, dedented, or `nil`."
  def bad_example(rule) do
    with {:docs_v1, _, _, _, %{"en" => doc}, _, _} <- Code.fetch_docs(rule),
         [_, block] <- Regex.run(~r/##\s*Bad\s*\n\n(.*?)(?:\n\s*\n##|\z)/s, doc) do
      block
      |> String.split("\n")
      |> Enum.map_join("\n", &String.replace_prefix(&1, "    ", ""))
      |> String.trim()
    else
      _ -> nil
    end
  end

  @doc """
  For each rule, the set of corpus indices it reports at least one issue on.

  A rule that crashes on a snippet counts as not firing: the duplicate gate is
  not the place to fail on that, and `pipeline_witness` already covers it.
  """
  def firing_sets(rules, corpus) do
    Map.new(rules, fn rule ->
      set =
        corpus
        |> Enum.with_index()
        |> Enum.filter(fn {{source, ast}, _idx} ->
          try do
            rule.check(ast, source: source) != []
          rescue
            _ -> false
          catch
            _, _ -> false
          end
        end)
        |> MapSet.new(fn {_snippet, idx} -> idx end)

      {rule, set}
    end)
  end

  @doc """
  Pairs where **both** signals agree, as `{container, contained, score}`.

  `signatures` and `firing` are maps keyed by rule. A pair is reported when the
  signatures score at or above `threshold` and the second rule's firing set is a
  non-empty subset of the first's. Rules with a signature smaller than two atoms
  are skipped: a one-atom signature scores 1.0 against any other one-atom
  signature that happens to match, which is noise rather than similarity.
  """
  def duplicate_pairs(signatures, firing, threshold) do
    rules = Map.keys(signatures)

    for a <- rules,
        b <- rules,
        a != b,
        sig_a = signatures[a],
        sig_b = signatures[b],
        MapSet.size(sig_a) >= 2,
        MapSet.size(sig_b) >= 2,
        fire_a = firing[a],
        fire_b = firing[b],
        MapSet.size(fire_b) > 0,
        MapSet.subset?(fire_b, fire_a),
        # An equal pair is symmetric; report it once, under the lower name.
        not (MapSet.equal?(fire_a, fire_b) and a > b),
        score = jaccard(sig_a, sig_b),
        score >= threshold,
        do: {a, b, Float.round(score, 3)}
  end
end
