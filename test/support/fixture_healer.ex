defmodule Credence.FixtureHealer do
  @moduledoc """
  Deterministically rewrites flagged test fixtures into the canonical, escape-free
  form, before the suite compiles (invoked from `test/test_helper.exs`):

    * value with a newline         → `\"""` heredoc
    * single-line value with a `"` → `~S'…'` sigil (heredoc only if it also has a `'`)

  A clean single-line value with no `"` stays a plain `"…"`; heredocs, sigils, and
  `@allow` files are left untouched. Only flagged plain `"…"` fixtures (per
  `Credence.MetaTestSupport.fixture_ok?/1`) are converted.

  A file is written only when the result parses, drops at least one flagged
  fixture (monotonic), and preserves every fixture's compiled value (±a trailing
  newline, which a heredoc unavoidably adds). Best-effort: any error leaves the
  file untouched, so a healer bug can never brick the suite.
  """
  alias Credence.MetaTestSupport, as: Meta

  @dirs ["test/pattern", "test/semantic", "test/syntax"]

  @doc "Heal every rule test file under the gated dirs (skipping the `@allow` list)."
  def heal_dirs do
    @dirs
    |> Enum.flat_map(&Path.wildcard("#{&1}/**/*_test.exs"))
    |> Enum.each(&heal_file/1)
  end

  @doc "Heal one file in place. Never raises; never makes a file worse."
  def heal_file(path) do
    if Map.has_key?(Meta.allow(), path) do
      :ok
    else
      src = File.read!(path)
      {healed, _residue} = heal_source(src)
      if healed != src and safe?(src, healed), do: File.write!(path, healed)
      :ok
    end
  rescue
    _ -> :ok
  end

  @doc "Pure: `{healed_source, residue_count}`."
  def heal_source(src) do
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

  # ── rendering (only plain "…" nodes are convertible here) ────────────────

  # Returns the replacement source string, or nil (residue).
  defp render({:__block__, m, [_]} = node) do
    if Keyword.get(m, :delimiter) == "\"\"\"" do
      nil
    else
      case value_of(node) do
        {:ok, value} -> canonical(value)
        :error -> nil
      end
    end
  end

  defp render(_), do: nil

  # The fixture's true compiled value (Sourceror's binary is only partly
  # un-escaped, so render → eval the well-formed source instead).
  defp value_of(node) do
    {value, _} = Code.eval_string(Sourceror.to_string(node), [], file: "nofile")
    if is_binary(value), do: {:ok, value}, else: :error
  rescue
    _ -> :error
  end

  defp canonical(value) do
    cond do
      String.contains?(value, "\n") -> heredoc(value)
      not String.contains?(value, "'") -> "~S'" <> value <> "'"
      true -> heredoc(value)
    end
  end

  defp heredoc(value) do
    body = if String.ends_with?(value, "\n"), do: value, else: value <> "\n"
    "\"\"\"\n" <> body <> "\"\"\""
  end

  # ── write safety ─────────────────────────────────────────────────────────

  defp safe?(src, healed) do
    match?({:ok, _}, Code.string_to_quoted(healed)) and
      flagged_count(healed) < flagged_count(src) and
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
        {{:ok, x}, {:ok, y}} -> y == x or y == x <> "\n"
        _ -> false
      end)
  end

  defp fixture_values(src) do
    src
    |> Sourceror.parse_string!()
    |> Meta.fixtures()
    |> Enum.map(fn node ->
      try do
        {:ok, elem(Code.eval_string(Sourceror.to_string(node), [], file: "nofile"), 0)}
      rescue
        _ -> :uneval
      end
    end)
  end
end
