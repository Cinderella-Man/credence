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
  Compiles `source` with `Code.with_diagnostics/1` and returns
  `{:ok, diagnostics}` or `{:error, diagnostics}`.

  Uses `:code.soft_purge/1` for cleanup so that compiling source
  which redefines a currently-executing module does not kill the BEAM
  (see `:code.purge/1` — it sends an unconditional kill signal to
  any process still running the old version of the module).
  """
  @spec compile_and_capture(String.t()) :: {:ok, [map()]} | {:error, [map()]}
  def compile_and_capture(source) do
    {result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          Code.compile_string(source, "credence_check.ex")
        rescue
          e ->
            Logger.debug("[credence_fix] Code.compile_string raised: #{Exception.message(e)}")

            :error
        end
      end)

    case result do
      :error ->
        {:error, diagnostics}

      modules when is_list(modules) ->
        safe_cleanup_modules(modules)
        {:ok, diagnostics}
    end
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
  Strips `Sourceror.parse_string!/1`'s `{:__block__, meta, [value]}`
  wrappers around literals, atoms, 2-tuples, and lists — producing the
  bare-literal shape that `Macro.to_string/1` expects for rendering.

  Used by test helpers to canonicalize ASTs for structural comparison
  (parse → normalize → `Macro.to_string` → string compare). Not used
  by production rules — all rules pattern-match Sourceror's wrapped
  form directly.

  Unwraps:

  - Literals: `{:__block__, _, [1]}` → `1`
  - Atoms: `{:__block__, _, [:do]}` → `:do`
  - 2-tuples: `{:__block__, _, [{a, b}]}` → `{a, b}`
  - Lists: `{:__block__, _, [[a, b]]}` → `[a, b]`
  """
  @spec normalize_sourceror_ast(Macro.t()) :: Macro.t()
  def normalize_sourceror_ast(ast) do
    Macro.postwalk(ast, &unwrap_sourceror_node/1)
  end

  defp unwrap_sourceror_node({:__block__, _meta, [val]})
       when is_integer(val) or is_float(val) or is_binary(val) or is_atom(val) do
    val
  end

  # Sourceror wraps list literals in {:__block__, meta, [[elements...]]}
  # for position tracking (closing bracket location, etc.).
  # Standard AST has bare lists.
  defp unwrap_sourceror_node({:__block__, _meta, [val]}) when is_list(val) do
    val
  end

  # Sourceror wraps single-expression bodies in {:__block__, meta, [expr]}
  # for position tracking. Standard AST has just the expression directly.
  # Only unwrap when the child is a single AST node (3-tuple), not
  # multi-expression blocks which have 2+ children.
  defp unwrap_sourceror_node({:__block__, _meta, [expr]})
       when is_tuple(expr) and tuple_size(expr) == 3 do
    expr
  end

  defp unwrap_sourceror_node({:__block__, _meta, [{left, right}]})
       when not (is_list(right) and is_atom(left)) do
    # Unwrap 2-tuples that Sourceror wrapped for position metadata.
    # Guard excludes 3-tuple AST nodes that happen to look like {atom, list}
    # — those are real AST nodes like {:foo, [], nil} (impossible here since
    # nil is not a list, but we guard defensively).
    {left, right}
  end

  defp unwrap_sourceror_node(node), do: node

  @doc """
  Computes a line-by-line diff between two strings.

  Returns a list of `{:removed, line_no, text}` and `{:added, line_no, text}`
  tuples for every line that changed.
  """
  @spec diff_lines(String.t(), String.t()) :: [
          {:removed, pos_integer(), String.t()} | {:added, pos_integer(), String.t()}
        ]
  def diff_lines(before, after_fix) do
    before_lines = String.split(before, "\n")
    after_lines = String.split(after_fix, "\n")
    max_len = max(length(before_lines), length(after_lines))

    Enum.flat_map(0..(max_len - 1), fn i ->
      b = Enum.at(before_lines, i)
      a = Enum.at(after_lines, i)

      cond do
        b == a -> []
        is_nil(a) -> [{:removed, i + 1, b}]
        is_nil(b) -> [{:added, i + 1, a}]
        true -> [{:removed, i + 1, b}, {:added, i + 1, a}]
      end
    end)
  end

  @doc """
  Invokes a Pattern rule's fix on `source`, dispatching to either the
  new patch-based `fix_patches/2` callback (if the rule has migrated)
  or the legacy `fix/2` callback.

  Used by both the orchestrator (`Credence.Pattern.run_fixable_rules/3`)
  and rule tests, so test assertions on the post-fix source string
  continue working unchanged regardless of which side of the
  migration a rule is on.
  """
  @spec apply_rule_fix(module(), String.t(), keyword()) :: String.t()
  def apply_rule_fix(rule, source, opts \\ []) do
    opts = Keyword.put(opts, :source, source)
    ast = Sourceror.parse_string!(source)

    case rule.fix_patches(ast, opts) do
      [] ->
        source

      patches when is_list(patches) ->
        source
        |> Sourceror.patch_string(patches)
        |> strip_trailing_ws_per_line()
    end
  end

  # `Sourceror.patch_string` re-indents multi-line replacements to
  # match the patch's start column, which can turn empty blank lines
  # in the replacement into whitespace-only lines. Clean those up.
  defp strip_trailing_ws_per_line(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &String.trim_trailing/1)
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

  defp diff_patches(same, same), do: []

  # `:__block__` wrappers around a single literal leaf (string, atom,
  # number) carry no source position of their own beyond the wrapper.
  # If the wrapped value changed, the patch must land at the wrapper's
  # range — recursing into the args list would drop us at a bare literal
  # with no range, losing the patch.
  defp diff_patches({:__block__, _, [val_o]} = orig, {:__block__, _, [val_m]} = modified)
       when val_o != val_m and not is_tuple(val_o) and not is_list(val_o) do
    case node_range(orig) do
      nil -> []
      range -> [%{range: range, change: render_replacement(modified, range)}]
    end
  end

  # Same 3-tuple shape with same arity — recurse into args. (Form must
  # be deeply equal too: an atom-form vs tuple-form is structurally
  # different and should patch the whole node.)
  defp diff_patches({form, _, args_o}, {form, _, args_m})
       when is_list(args_o) and is_list(args_m) and length(args_o) == length(args_m) do
    args_o
    |> Enum.zip(args_m)
    |> Enum.flat_map(fn {o, m} -> diff_patches(o, m) end)
  end

  # Lists of the same length — zip and recurse.
  defp diff_patches([_ | _] = orig, [_ | _] = modified)
       when length(orig) == length(modified) do
    orig
    |> Enum.zip(modified)
    |> Enum.flat_map(fn {o, m} -> diff_patches(o, m) end)
  end

  # 2-tuples (keyword pair etc.) — recurse on each side.
  defp diff_patches({a_o, b_o}, {a_m, b_m}) do
    diff_patches(a_o, a_m) ++ diff_patches(b_o, b_m)
  end

  # Structures diverge here — emit one patch covering the original
  # node's range. Skip if the original is a leaf without a range
  # (Sourceror can't pinpoint bare literals/atoms).
  defp diff_patches(orig, modified) do
    case node_range(orig) do
      nil ->
        []

      range ->
        [%{range: range, change: render_replacement(modified, range)}]
    end
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
        {form, Keyword.drop(meta, [:line, :column, :closing, :last, :end]), args}

      other ->
        other
    end)
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
        {:removed, line_no, text} -> "  L#{line_no} - #{String.trim(text)}"
        {:added, line_no, text} -> "  L#{line_no} + #{String.trim(text)}"
      end)

    Logger.debug("[credence_fix] #{label}: source CHANGED:\n#{change_summary}")
  end
end
