defmodule Mix.Tasks.Credence.NormalizeTests do
  @shortdoc "Strip provably-unnecessary heredoc trailing `\\` from test files"

  @moduledoc ~S'''
  Cosmetic cleanup for agent-authored rule tests (tunex docs/10).

      mix credence.normalize_tests test/syntax/foo_fix_test.exs [more...]

  An agent often writes heredoc fixtures with a trailing line-continuation `\`
  to drop the final newline:

      code = """
      foo(bar)\
      """

  That's valid (value = "foo(bar)" with no trailing "\n") and sometimes
  load-bearing — but usually gratuitous and confusing. This task removes each
  such `\` ONLY when it can prove the removal is safe: it deletes the `\` (which
  adds the trailing newline back), **re-runs that test file, and keeps the change
  only if the file is still green** — otherwise it reverts. A `\` that genuinely
  pins a newline-free value is left untouched, so a green suite can't go red.

  Files whose baseline run is already RED are skipped (we can't attribute a
  failure). Deletes a single character per edit, so all surrounding formatting is
  preserved.
  '''

  use Mix.Task

  @close "\"\"\""

  @impl Mix.Task
  def run(paths), do: Enum.each(paths, &normalize_file/1)

  @doc """
  Normalize one file. `opts[:run]` is a `(path -> exit_code)` runner (defaults to
  `mix test <path>`); injected in tests. Returns `{:ok, removed}` / `{:noop, 0}` /
  `{:skip, 0}`.
  """
  def normalize_file(path, opts \\ []) do
    run = Keyword.get(opts, :run, &mix_test/1)
    src = File.read!(path)
    cands = candidates(src)

    cond do
      cands == [] ->
        {:noop, 0}

      run.(path) != 0 ->
        Mix.shell().info("[normalize] #{path}: baseline RED — skipped")
        {:skip, 0}

      true ->
        n = clean(path, src, cands, run)
        Mix.shell().info("[normalize] #{path}: removed #{n}/#{length(cands)} trailing `\\`")
        {:ok, n}
    end
  end

  # Try all at once (the common all-cosmetic case → 1 run); if that goes red,
  # fall back to greedy per-candidate so independently-safe ones still get cleaned.
  defp clean(path, src, cands, run) do
    all = Enum.reduce(cands, lines(src), &strip_at(&2, &1)) |> join()
    File.write!(path, all)

    if run.(path) == 0 do
      length(cands)
    else
      {final, n} =
        Enum.reduce(cands, {src, 0}, fn i, {cur, kept} ->
          trial = cur |> lines() |> strip_at(i) |> join()
          File.write!(path, trial)

          if run.(path) == 0 do
            {trial, kept + 1}
          else
            File.write!(path, cur)
            {cur, kept}
          end
        end)

      File.write!(path, final)
      n
    end
  end

  # Line indices whose line ends with an ODD number of `\` (a real continuation,
  # not an escaped backslash) AND whose next line is a closing heredoc delimiter.
  @doc false
  def candidates(src) do
    ls = lines(src)

    ls
    |> Enum.with_index()
    |> Enum.filter(fn {line, i} ->
      nxt = Enum.at(ls, i + 1)
      # the closing delimiter is at line start (possibly followed by a call-closer
      # or operator, e.g. `""")`, `""") == []`); an OPENING `"""` is at line END.
      nxt != nil and String.starts_with?(String.trim(nxt), @close) and
        odd_trailing_backslashes?(line)
    end)
    |> Enum.map(&elem(&1, 1))
  end

  # Deleting one trailing `\` per edit keeps line indices stable across edits.
  defp strip_at(ls, i), do: List.update_at(ls, i, &String.replace_suffix(&1, "\\", ""))
  defp lines(src), do: String.split(src, "\n")
  defp join(ls), do: Enum.join(ls, "\n")

  defp odd_trailing_backslashes?(line) do
    n =
      line
      |> String.to_charlist()
      |> Enum.reverse()
      |> Enum.take_while(&(&1 == ?\\))
      |> length()

    rem(n, 2) == 1
  end

  defp mix_test(path) do
    {_out, code} =
      System.cmd("mix", ["test", path], stderr_to_stdout: true, env: [{"MIX_ENV", "test"}])

    code
  end
end
