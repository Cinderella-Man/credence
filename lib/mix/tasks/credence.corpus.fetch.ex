defmodule Mix.Tasks.Credence.Corpus.Fetch do
  @shortdoc "Fetch the pinned real-world corpus packages into corpus/"

  @moduledoc """
  Fetches the source of the pinned popular hex packages (see `Credence.Corpus`)
  into the gitignored `corpus/` directory, using `mix hex.package fetch` — source
  only, no transitive deps, no compilation.

      mix credence.corpus.fetch

  Idempotent: packages already present at the pinned version are skipped. Run
  this once; the over-firing test (`mix test --include corpus`) and
  `mix credence.corpus` then read the cached source.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Credence.Corpus.ensure_fetched!()

    present =
      Credence.Corpus.entries()
      |> Enum.map(fn {name, label} ->
        "  #{name} #{label} — #{length(Credence.Corpus.lib_files(name))} lib files"
      end)

    Mix.shell().info("Corpus ready in #{Credence.Corpus.root()}/:\n" <> Enum.join(present, "\n"))
  end
end
