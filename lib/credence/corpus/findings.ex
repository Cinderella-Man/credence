defmodule Credence.Corpus.Findings do
  @moduledoc """
  Resolves every Pattern finding on a corpus package to a stable identity, used
  for snapshot-based over-fire *regression* testing.

  Each finding becomes one line:

      <corpus-relative path>:<line>  <rule>

  with a trailing `  (xN)` on the rare occasion the same `(file, line, rule)`
  fires more than once. The accepted set of these lines is pinned in
  `test/corpus/accepted_findings.txt`; `test/corpus/over_firing_test.exs` asserts
  the *live* set equals the pin, per package — so a NEW finding (a candidate
  over-fire) shows up as an unexpected line and fails the suite, rather than
  being silently swallowed by a rule-level allowlist. Re-pin intentionally with:

      mix credence.corpus --update-snapshot

  Keying on `file:line` makes every finding distinct, so the pin is maximally
  sensitive: any new firing site — even one inside an already-pinned function —
  is a diff. The cost is that bumping a package version shifts line numbers and
  forces a re-pin, which is intended: you re-review a package's findings when you
  upgrade it.
  """

  alias Credence.Corpus

  @snapshot_relpath "test/corpus/accepted_findings.txt"

  @doc "Absolute path to the committed snapshot file."
  @spec snapshot_path() :: String.t()
  def snapshot_path, do: Path.join(File.cwd!(), @snapshot_relpath)

  @doc """
  Sorted finding-identity lines for a single package — the live set to compare
  against the snapshot's lines for that package.
  """
  @spec for_package(atom()) :: [String.t()]
  def for_package(pkg) do
    pkg
    |> Corpus.lib_files()
    |> Enum.flat_map(&raw_findings/1)
    |> format()
  end

  @doc "Sorted finding-identity lines across every pinned package."
  @spec all() :: [String.t()]
  def all do
    Corpus.packages()
    |> Enum.flat_map(fn {pkg, _version} -> for_package(pkg) end)
    |> Enum.sort()
  end

  @doc """
  The accepted lines recorded in the snapshot file (blank lines and `#` comments
  stripped). Returns `[]` if the file does not exist yet.
  """
  @spec snapshot_lines() :: [String.t()]
  def snapshot_lines do
    case File.read(snapshot_path()) do
      {:ok, body} ->
        body
        |> String.split("\n")
        |> Enum.map(&String.trim_trailing/1)
        |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))

      {:error, _} ->
        []
    end
  end

  @doc """
  Format raw `{relative_path, line, rule}` findings into sorted identity lines,
  collapsing exact duplicates with an `(xN)` count. Public for unit testing.
  """
  @spec format([{String.t(), pos_integer() | nil, atom()}]) :: [String.t()]
  def format(raw) do
    raw
    |> Enum.frequencies()
    |> Enum.map(fn {{rel, line, rule}, n} ->
      loc = if line, do: "#{rel}:#{line}", else: "#{rel}:?"
      base = "#{loc}  #{rule}"
      if n > 1, do: base <> "  (x#{n})", else: base
    end)
    |> Enum.sort()
  end

  defp raw_findings(path) do
    source = File.read!(path)
    rel = Path.relative_to(path, Corpus.root())

    for issue <- Credence.Pattern.analyze(source), issue.rule != :parse_error do
      {rel, issue.meta[:line], issue.rule}
    end
  end
end
