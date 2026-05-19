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
  Normalizes an AST produced by `Sourceror.parse_string!/1` so that
  standard `Code.string_to_quoted` pattern matches work against it.

  Sourceror wraps literals and 2-tuples in `{:__block__, meta, [value]}`
  nodes to carry position metadata (the standard AST has no metadata slot
  for these). This breaks patterns like `{:==, _, [expr, 1]}` because
  the `1` is actually `{:__block__, [token: "1"], [1]}`.

  This function recursively unwraps:

  - Literals: `{:__block__, _, [1]}` → `1`
  - Atoms: `{:__block__, _, [:do]}` → `:do`
  - 2-tuples: `{:__block__, _, [{a, b}]}` → `{a, b}`

  As a result, keyword blocks like `[{{:__block__, _, [:do]}, body}]`
  become `[do: body]`, matching standard AST shapes.

  Use this in rule `fix/2` functions between parsing and walking:

      source
      |> Sourceror.parse_string!()
      |> RuleHelpers.normalize_sourceror_ast()
      |> Macro.postwalk(fn ... end)
      |> Sourceror.to_string()
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
      [] -> source
      patches when is_list(patches) -> Sourceror.patch_string(source, patches)
    end
  end

  @doc """
  Builds a single-patch list that replaces the whole source from
  `(1, 1)` through the end of `original_source` with `new_source`.

  An adapter used by Pattern rules that already implement complex
  source-level transformations but need to expose the patch-based
  `fix_patches/2` interface. Loses the per-edit locality that proper
  patch decomposition would deliver — only use when refactoring the
  rule into discrete patches would be substantially more work than
  it's worth.
  """
  @spec whole_source_patches(String.t(), String.t()) :: [map()]
  def whole_source_patches(original_source, new_source) do
    if new_source == original_source do
      []
    else
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
  end

  @doc """
  Renders a replacement subtree as source text suitable for patching
  back into the original source at `original_range`'s position.

  Used by patch-based rules to keep multi-line originals from
  collapsing onto a single line just because the replacement fits
  Sourceror's default 98-column line budget.

  The heuristic: if the original spans multiple lines, set Sourceror's
  `line_length` to the original expression's column-width (with a
  floor of 40 so tiny snippets don't over-wrap). If the original sits
  on a single line, use Sourceror's default.

  Established by the Issue 4 fix on `no_map_then_aggregate`.
  """
  @spec render_replacement(Macro.t(), map()) :: String.t()
  def render_replacement(new_ast, original_range) do
    opts =
      if original_range.start[:line] == original_range.end[:line] do
        []
      else
        budget = max(original_range.end[:column] - original_range.start[:column], 40)
        [line_length: budget]
      end

    Sourceror.to_string(new_ast, opts)
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
