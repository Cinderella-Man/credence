defmodule Mix.Tasks.Credence.FixTests do
  @shortdoc "Canonicalize a Pattern rule fix-test's `expected` to the rule's REAL output"

  @moduledoc """
  Deterministic helper for the tunex rule-gen flow (tunex docs/10).

      mix credence.fix_tests test/pattern/foo_fix_test.exs [more_test.exs ...]

  An LLM building a rule writes `assert fix(Rule, input) == expected` but can't
  byte-predict the rule's exact output, so `expected` is wrong → the fix test
  fails → the Gate rejects the (often correct) rule, and the agent burns turns
  guessing. This task removes that class WITHOUT the AI: for each
  `input = "\""…"\""` / `expected = "\""…"\""` / `assert fix(Rule, input) ==
  expected` block in a Pattern rule's fix test, it RUNS the rule on `input` and
  rewrites `expected` to the actual output — which is exactly the project's own
  convention ("`expected` is the rule's REAL output — run it, copy the string").

  Safe + conservative:
    * Only Pattern rules (it calls `fix_patches/2`); the module is derived from the
      test path and must be loaded (so a rule that doesn't compile is skipped — its
      failure is a real bug for the agent, not ours).
    * Only the `fix(Alias, input) == expected` shape with resolvable heredoc
      operands; anything else is left untouched.
    * NO-OP fixes (`actual == input`) are NOT rewritten — that would create a
      `expected == input` test that fails the "real transformation" meta-gate; a
      no-op fix is a genuine rule bug, left for the agent.
    * Correctness is still guarded by the rule's equivalence test, not by this
      (auto-captured) `expected`.
  """

  use Mix.Task

  alias Credence.RuleHelpers

  @impl Mix.Task
  def run(paths), do: Enum.each(paths, &fix_file/1)

  @doc "Rewrite one fix-test file in place. Best-effort: any problem leaves it untouched."
  def fix_file(path) do
    with true <- File.exists?(path),
         {:ok, module} <- rule_module(path),
         true <- Code.ensure_loaded?(module) and function_exported?(module, :fix_patches, 2) do
      src = File.read!(path)
      ast = Sourceror.parse_string!(src)

      case collect_patches(ast, module) do
        [] -> :ok
        patches -> File.write!(path, Sourceror.patch_string(src, patches))
      end
    else
      _ -> :ok
    end
  rescue
    _ -> :ok
  end

  # test/pattern/<snake>_fix_test.exs → Credence.Pattern.<Camelize(snake)>
  defp rule_module(path) do
    case Regex.run(~r{test/pattern/([a-z0-9_]+)_fix_test\.exs$}, path) do
      [_, snake] -> {:ok, Module.concat([Credence, Pattern, Macro.camelize(snake)])}
      _ -> :error
    end
  end

  defp collect_patches(ast, module) do
    {_, patches} =
      Macro.prewalk(ast, [], fn
        {:test, _, args} = node, acc when is_list(args) ->
          case args |> List.last() |> do_body() do
            nil -> {node, acc}
            body -> {node, test_patches(body, module) ++ acc}
          end

        node, acc ->
          {node, acc}
      end)

    patches
  end

  # Sourceror wraps the `do:` keyword key as `{:__block__, _, [:do]}` (not the
  # bare `:do` of standard quoted), so match both.
  defp do_body(kw) when is_list(kw) do
    Enum.find_value(kw, fn
      {:do, body} -> body
      {{:__block__, _, [:do]}, body} -> body
      _ -> nil
    end)
  end

  defp do_body(_), do: nil

  defp test_patches(body, module) do
    binds = heredoc_bindings(body)

    case eq_patch(body, binds, module) do
      [] -> tilde_patch(body, binds, module)
      patches -> patches
    end
  end

  # Shape 1 — `assert fix(Alias, input) == expected` with a WRONG `expected`:
  # rewrite the `expected` heredoc to the rule's real output.
  defp eq_patch(body, binds, module) do
    with {input_ref, expected_ref} <- fix_assertion(body),
         {:ok, {input_str, _}} <- resolve(input_ref, binds),
         {:ok, {expected_str, expected_node}} <- resolve(expected_ref, binds),
         actual when is_binary(actual) <- safe_fix(module, input_str),
         # only rewrite a REAL transform that's currently WRONG
         true <- actual != input_str and actual != expected_str,
         true <- String.ends_with?(actual, "\n") do
      [%{range: Sourceror.get_range(expected_node), change: heredoc(actual)}]
    else
      _ -> []
    end
  end

  # Shape 2 — `result = fix(Alias, input)` then a CONTIGUOUS run of
  # `assert/refute result =~ "…"`: collapse the whole run into one inline
  # `assert fix(Alias, input) == "\""<actual>"\""` (inline, so FixMetaTest's
  # `has_transform` sees a real `fix(...) == B`; a bound var wouldn't count).
  defp tilde_patch(body, binds, module) do
    stmts = statements(body)

    with {fixcall, input_ref, rvar} <- result_binding(stmts),
         {:ok, {input_str, _}} <- resolve(input_ref, binds),
         run when run != [] <- contiguous_tilde_run(stmts, rvar),
         actual when is_binary(actual) <- safe_fix(module, input_str),
         true <- actual != input_str,
         true <- String.ends_with?(actual, "\n") do
      r1 = Sourceror.get_range(List.first(run))
      r2 = Sourceror.get_range(List.last(run))
      change = "assert " <> fixcall_text(fixcall) <> " == " <> heredoc(actual)
      [%{range: %{start: r1.start, end: r2.end}, change: change}]
    else
      _ -> []
    end
  end

  # `result = fix(Alias, input)` → {fix_call_node, input_ref, result_var}.
  defp result_binding(stmts) do
    Enum.find_value(stmts, fn
      {:=, _, [{rvar, _, ctx}, {:fix, _, [{:__aliases__, _, _}, arg]} = call]}
      when is_atom(rvar) and is_atom(ctx) ->
        {call, ref(arg), rvar}

      _ ->
        false
    end) || :none
  end

  # The contiguous block of `assert/refute <rvar> =~ …` statements (returns []
  # if a non-`=~`-on-rvar statement is interleaved, to keep the span surgical).
  defp contiguous_tilde_run(stmts, rvar) do
    idxs =
      stmts
      |> Enum.with_index()
      |> Enum.filter(fn {s, _} -> tilde_on?(s, rvar) end)
      |> Enum.map(&elem(&1, 1))

    case idxs do
      [] ->
        []

      _ ->
        if List.last(idxs) - List.first(idxs) + 1 == length(idxs),
          do: Enum.map(idxs, &Enum.at(stmts, &1)),
          else: []
    end
  end

  defp tilde_on?({verb, _, [{:=~, _, [{rvar, _, ctx}, _]}]}, rvar)
       when verb in [:assert, :refute] and is_atom(ctx),
       do: true

  defp tilde_on?(_, _), do: false

  defp fixcall_text({:fix, _, [{:__aliases__, _, parts}, arg]}) do
    "fix(" <> Enum.map_join(parts, ".", &Atom.to_string/1) <> ", " <> arg_text(arg) <> ")"
  end

  defp arg_text({var, _, ctx}) when is_atom(var) and is_atom(ctx), do: Atom.to_string(var)
  defp arg_text(node), do: Sourceror.to_string(node)

  # `var = "\""…"\""` heredoc bindings in the block → %{var => {value, node}}.
  defp heredoc_bindings(body) do
    body
    |> statements()
    |> Enum.reduce(%{}, fn
      {:=, _, [{var, _, ctx}, hd]}, acc when is_atom(var) and is_atom(ctx) ->
        case heredoc_value(hd) do
          {:ok, v} -> Map.put(acc, var, {v, hd})
          :error -> acc
        end

      _, acc ->
        acc
    end)
  end

  # The fix assertion → {input_ref, expected_ref} where each ref is `{:var, atom}`
  # or `{:node, heredoc_node}`. Matches both the canonical
  # `confirm_fix(fix(Alias, <input>), <expected>)` and the legacy
  # `assert fix(Alias, <input>) == <expected>`.
  defp fix_assertion(body) do
    Enum.find_value(statements(body), fn
      {:confirm_fix, _, [{:fix, _, [{:__aliases__, _, _}, arg]}, rhs]} ->
        {ref(arg), ref(rhs)}

      {:assert, _, [{:==, _, [{:fix, _, [{:__aliases__, _, _}, arg]}, rhs]}]} ->
        {ref(arg), ref(rhs)}

      _ ->
        false
    end) || :none
  end

  defp ref({var, _, ctx}) when is_atom(var) and is_atom(ctx), do: {:var, var}
  defp ref(node), do: {:node, node}

  defp resolve({:var, var}, binds), do: Map.fetch(binds, var)

  defp resolve({:node, node}, _binds) do
    case heredoc_value(node) do
      {:ok, v} -> {:ok, {v, node}}
      :error -> :error
    end
  end

  # Sourceror parses with `unescape: false`, so `v` here is the heredoc's RAW
  # source bytes — `\"` is still two characters. ExUnit, running the same file
  # later, sees the *decoded* value. Those differ for any fixture containing an
  # escape, and this function feeds both the rule's input and the expected-output
  # comparison, so returning the raw bytes made the tool reason about a string no
  # test ever holds:
  #
  #   * the rule was handed `~c"say \"hi\""` (with backslashes) as its INPUT,
  #     rather than the `~c"say "hi""` the runtime test passes it;
  #   * and a fixture that was correctly escaped compared unequal to the rule's
  #     real output, so the tool rewrote it on every run — churn that looks like
  #     the rule being unstable.
  #
  # Decoding here makes this the exact inverse of `heredoc/1`'s escaping, which is
  # what keeps `mix credence.fix_tests` idempotent.
  defp heredoc_value({:__block__, meta, [v]}) when is_binary(v) do
    if Keyword.get(meta, :delimiter) == "\"\"\"", do: {:ok, unescape(v)}, else: :error
  end

  defp heredoc_value(_), do: :error

  # A heredoc that reached here came out of a file that compiles, so its escapes
  # are valid — but a raw byte sequence is not a promise, and an unreadable escape
  # should degrade to "leave this fixture alone" rather than kill the whole task.
  defp unescape(raw) do
    Macro.unescape_string(raw)
  rescue
    _ -> raw
  end

  defp safe_fix(module, source) do
    RuleHelpers.apply_rule_fix(module, source)
  rescue
    _ -> :error
  end

  # A heredoc literal whose VALUE equals `value` (which ends in "\n"). The content
  # is column-0 here; Sourceror.patch_string re-indents the whole replacement
  # uniformly to the node's column, so the closing-delimiter dedent cancels and
  # the value is preserved.
  #
  # `value` is the rule's real output as BYTES, while a `"""` heredoc is read back
  # through the same escape rules as a plain string — so splicing it in raw is only
  # correct for output that happens to contain neither `\` nor `#{`. It silently
  # broke for everything else, which meant precisely the escaping-sensitive rules:
  #
  #   * `~c"say \"hi\""` was written verbatim and read back as `~c"say "hi""` —
  #     the backslashes consumed as heredoc escapes. The fixture then no longer
  #     equalled the rule's output and the test failed with a diff whose two sides
  #     looked almost identical, which is how this survived (escalation ledger row
  #     134, misfiled against `PreferSigilCharlist` — that rule's output was right
  #     all along; this emitter corrupted the fixture recording it).
  #   * output containing `#{` was worse than corrupted: the heredoc parsed as an
  #     interpolation, so the node was a `{:<<>>, _, [...]}` rather than a binary
  #     literal and `heredoc_value/1` could not read it back at all.
  #
  # Escape order is load-bearing: backslashes first, then `#{`. The other order
  # doubles the backslash this function just added in front of `#{` and the
  # interpolation comes back.
  defp heredoc(value), do: "\"\"\"\n" <> escape_heredoc(value) <> "\"\"\""

  defp escape_heredoc(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\#{", "\\\#{")
  end

  defp statements({:__block__, _, stmts}) when is_list(stmts), do: stmts
  defp statements(single), do: [single]
end
