defmodule Credence.FixtureHealer do
  @moduledoc """
  Deterministically rewrites test fixtures (and the fix-result assertions that
  consume them) into the project's single canonical form, before the suite
  compiles (invoked from `test/test_helper.exs`). Idempotent: a no-op once a
  file is canonical.

  Three passes per file:

    1. **Normalize fix comparisons** — `assert <fix-call> == expected` (and the
       var-bound `result = fix(...)` / `assert result == expected` shape) becomes
       `confirm_fix(<fix-call>, expected)`. `confirm_fix/2` compares with trailing
       newlines trimmed, so a heredoc input/expected (which always ends in `\\n`)
       and a compact plain string are interchangeable. The `fix` call may be the
       unqualified `RuleCase.fix/2` helper or a qualified `Mod.fix/2`. When a file
       gains a `confirm_fix` call, `import Credence.RuleCase, only: [confirm_fix: 2]`
       is ensured (merged into an existing scoped import, since a second
       `import M, only: [...]` would shadow the first).

    2. **Canonicalize fixture string forms** (one value, one form):

         * value with an internal newline → `\"""` heredoc
         * single-line value, no `"`      → plain `"…"`
         * single-line value with a `"`   → `~S'…'` sigil (heredoc if it also has `'`)

       A single-content-line heredoc (`\"""\\nfoo\\n\"""`, value `"foo\\n"`) is *not*
       canonical and is converted to plain/`~S'…'`. A heredoc whose value has an
       internal newline stays a heredoc.

  A file is written only when the result parses, never increases the flagged
  fixture count, and preserves every fixture's compiled value up to trailing
  newlines. Best-effort: any error leaves the file untouched, so a healer bug can
  never brick the suite.
  """
  alias Credence.MetaTestSupport, as: Meta

  @dirs ["test/pattern", "test/semantic", "test/syntax"]

  @doc "Heal every rule test file under the gated dirs."
  def heal_dirs do
    @dirs
    |> Enum.flat_map(&Path.wildcard("#{&1}/**/*_test.exs"))
    |> Enum.each(&heal_file/1)
  end

  @doc """
  Heal one file in place. Never raises; never makes a file worse.

  The two passes are guarded independently, because pass 1 (assertion rewrite)
  legitimately changes how many fixtures `Meta.fixtures/1` detects, so a
  count-matched value check can't span it:

    * pass 1 is value-neutral — it only wraps `==` operands in `confirm_fix` — so
      its guard is "parses, and every original fixture value still appears"
      (subset; pass 1 may *expose* one extra fixture, never lose one).
    * pass 2 changes string forms but keeps the fixture set 1:1, so it keeps the
      strict count-matched, value-preserving (±trailing newline) guard.
  """
  def heal_file(path) do
    src = File.read!(path)

    {s1, rewrote} = rewrite_assertions(src)
    s1 = if rewrote, do: ensure_confirm_fix_import(s1), else: s1
    s1 = if s1 != src and parses?(s1) and values_kept?(src, s1), do: s1, else: src

    {s2, _residue} = convert_fixtures(s1)
    s2 = if s2 != s1 and convert_safe?(s1, s2), do: s2, else: s1

    # Only touch a file we actually healed; then `mix format` it, since the
    # rewrite/patch render isn't always format-clean (long `confirm_fix(...)`
    # lines wrap differently). The convention assumes formatted source.
    final = if s2 != src, do: format(s2), else: src

    if final != src, do: File.write!(path, final)
    :ok
  rescue
    _ -> :ok
  end

  defp format(src) do
    formatted = src |> Code.format_string!() |> IO.iodata_to_binary()
    if String.ends_with?(formatted, "\n"), do: formatted, else: formatted <> "\n"
  rescue
    _ -> src
  end

  @doc "Pure: `{healed_source, residue_count}` — both passes, unguarded."
  def heal_source(src) do
    {src, rewrote} = rewrite_assertions(src)
    src = if rewrote, do: ensure_confirm_fix_import(src), else: src
    convert_fixtures(src)
  end

  # Pass 2 in isolation: canonicalize every fixture string form.
  defp convert_fixtures(src) do
    ast = Sourceror.parse_string!(src)

    {patches, residue} =
      ast
      |> Meta.fixtures()
      |> Enum.reduce({[], 0}, fn node, {patches, residue} ->
        cond do
          Meta.fixture_ok?(node) ->
            {patches, residue}

          change = render(node) ->
            {[%{range: Sourceror.get_range(node), change: change} | patches], residue}

          true ->
            {patches, residue + 1}
        end
      end)

    healed = if patches == [], do: src, else: Sourceror.patch_string(src, patches)
    {healed, residue}
  end

  # ── pass 1: normalize fix-result comparisons to confirm_fix/2 ──────────────

  defp rewrite_assertions(src) do
    ast = Sourceror.parse_string!(src)
    bound = fix_bound_vars(ast)

    {_, patches} =
      Macro.prewalk(ast, [], fn
        {:assert, _, [{:==, _, [a, b]}]} = node, acc ->
          cond do
            fix_call?(a) -> {node, [confirm_patch(node, a, b) | acc]}
            fix_call?(b) -> {node, [confirm_patch(node, b, a) | acc]}
            bound_var?(a, bound) -> {node, [confirm_patch(node, a, b) | acc]}
            bound_var?(b, bound) -> {node, [confirm_patch(node, b, a) | acc]}
            true -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    if patches == [], do: {src, false}, else: {Sourceror.patch_string(src, patches), true}
  rescue
    _ -> {src, false}
  end

  defp confirm_patch(node, fix_side, other_side) do
    %{
      range: Sourceror.get_range(node),
      change:
        "confirm_fix(" <>
          Sourceror.to_string(fix_side) <> ", " <> Sourceror.to_string(other_side) <> ")"
    }
  end

  # Vars bound to a fix call in an assignment, so `result = fix(...)` then
  # `assert result == expected` is recognised as a fix comparison.
  defp fix_bound_vars(ast) do
    {_, vars} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:=, _, [{name, _, ctx}, rhs]} = node, acc when is_atom(name) and is_atom(ctx) ->
          if fix_call?(rhs), do: {node, MapSet.put(acc, name)}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    vars
  end

  defp fix_call?({:fix, _, [_ | _]}), do: true
  defp fix_call?({{:., _, [_, :fix]}, _, [_ | _]}), do: true
  defp fix_call?(_), do: false

  defp bound_var?({name, _, ctx}, set) when is_atom(name) and is_atom(ctx),
    do: MapSet.member?(set, name)

  defp bound_var?(_, _), do: false

  defp ensure_confirm_fix_import(src) do
    cond do
      # the full case template brings confirm_fix/2 in unqualified
      String.contains?(src, "use Credence.RuleCase") ->
        src

      # already imports confirm_fix specifically
      Regex.match?(~r/import Credence\.RuleCase,\s*only:\s*\[[^\]]*confirm_fix/, src) ->
        src

      # a scoped RuleCase import already exists — merge confirm_fix into it
      # (a second `import M, only: [...]` would shadow the first, dropping it)
      Regex.match?(~r/import Credence\.RuleCase,\s*only:\s*\[/, src) ->
        Regex.replace(
          ~r/(import Credence\.RuleCase,\s*only:\s*\[)/,
          src,
          "\\1confirm_fix: 2, ",
          global: false
        )

      # no RuleCase import at all — add one after `use ExUnit.Case`
      true ->
        Regex.replace(
          ~r/^(\s*use ExUnit\.Case[^\n]*\n)/m,
          src,
          "\\1\n  import Credence.RuleCase, only: [confirm_fix: 2]\n",
          global: false
        )
    end
  end

  # ── pass 2: canonicalize fixture string forms ──────────────────────────────

  # render/1 is only reached for a flagged (non-canonical) fixture node — a plain
  # `"…"`, a single-content-line heredoc, or an `~s`/`~S` sigil. They all reduce to
  # the same decision on the node's compiled value. Returns the replacement source
  # string, or nil (residue — e.g. an interpolated value that won't eval).
  defp render(node) do
    case value_of(node) do
      {:ok, value} -> canonicalize(value)
      :error -> nil
    end
  end

  # The fixture's true compiled value (Sourceror's binary is only partly
  # un-escaped, so render → eval the well-formed source instead).
  defp value_of(node) do
    {{value, _}, _diagnostics} =
      Code.with_diagnostics(fn ->
        Code.eval_string(Sourceror.to_string(node), [], file: "nofile")
      end)

    if is_binary(value), do: {:ok, value}, else: :error
  rescue
    _ -> :error
  end

  # Trailing newlines are incidental (a heredoc always adds one; `confirm_fix`
  # trims them) — so a value is multi-line only by an *internal* newline.
  defp canonicalize(value) do
    inner = String.trim_trailing(value, "\n")

    cond do
      String.contains?(inner, "\n") -> heredoc(value)
      not String.contains?(inner, "\"") -> Macro.to_string(inner)
      not String.contains?(inner, "'") -> "~S'" <> inner <> "'"
      true -> heredoc(value)
    end
  end

  # `value` is a compiled binary and a `"""` heredoc is read back through the same
  # escape rules as a plain string, so a raw splice only round-trips for values
  # containing neither `\` nor `#{`. For everything else the emitted heredoc
  # compiles to a *different* value — or, for `#{`, to an interpolation that may
  # not compile at all.
  #
  # That never corrupted a fixture, because `values_preserved?/2` compares compiled
  # values and rejects the write; the cost was silent, not loud — those fixtures
  # were simply never canonicalized, and the ones affected are exactly the
  # escaping-sensitive rules. Escaping here is what lets the guard pass.
  #
  # Order matters: backslashes first, then `#{`, or the backslash this adds in
  # front of `#{` gets doubled and the interpolation comes back.
  defp heredoc(value) do
    body = if String.ends_with?(value, "\n"), do: value, else: value <> "\n"
    "\"\"\"\n" <> escape_heredoc(body) <> "\"\"\""
  end

  defp escape_heredoc(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\#{", "\\\#{")
  end

  # ── write safety ─────────────────────────────────────────────────────────

  defp parses?(src), do: match?({:ok, _}, Code.string_to_quoted(src))

  # Pass 1 guard: value-neutral, so only require that no original fixture value
  # is lost (pass 1 may expose one extra fixture — the inner fix-call operand).
  defp values_kept?(src, healed) do
    parses?(healed) and MapSet.subset?(value_set(src), value_set(healed))
  rescue
    _ -> false
  end

  defp value_set(src) do
    src
    |> fixture_values()
    |> Enum.flat_map(fn
      {:ok, v} -> [String.trim_trailing(v, "\n")]
      :uneval -> []
    end)
    |> MapSet.new()
  end

  # Pass 2 guard: form-only, so the fixture set stays 1:1 and values are
  # preserved up to a trailing newline; never increase the flagged count.
  defp convert_safe?(src, healed) do
    parses?(healed) and
      flagged_count(healed) <= flagged_count(src) and
      values_preserved?(src, healed)
  rescue
    _ -> false
  end

  defp flagged_count(src) do
    src |> Sourceror.parse_string!() |> Meta.fixtures() |> Enum.count(&(not Meta.fixture_ok?(&1)))
  end

  defp values_preserved?(src, healed) do
    before = fixture_values(src)
    after_ = fixture_values(healed)

    length(before) == length(after_) and
      before
      |> Enum.zip(after_)
      |> Enum.all?(fn
        {:uneval, :uneval} -> true
        {{:ok, x}, {:ok, y}} -> String.trim_trailing(x, "\n") == String.trim_trailing(y, "\n")
        _ -> false
      end)
  end

  defp fixture_values(src) do
    src
    |> Sourceror.parse_string!()
    |> Meta.fixtures()
    |> Enum.map(fn node ->
      try do
        {evaled, _diagnostics} =
          Code.with_diagnostics(fn ->
            Code.eval_string(Sourceror.to_string(node), [], file: "nofile")
          end)

        {:ok, elem(evaled, 0)}
      rescue
        _ -> :uneval
      end
    end)
  end
end
