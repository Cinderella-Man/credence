defmodule Credence.Corpus do
  @moduledoc """
  Real-world corpus of popular hex packages, used by the over-firing test layer
  (`test/corpus/over_firing_test.exs`) and the `mix credence.corpus` /
  `mix credence.corpus.fetch` maintainer tasks.

  The premise: these packages are widely used, well-reviewed Elixir code, so
  Credence should find nothing to flag in them. Anything it *does* flag is a
  candidate over-fire (a false positive on idiomatic code) — unless it is a
  reviewed, genuinely-correct suggestion (see the allowlist in the test).

  Source is fetched with `mix hex.package fetch` into a gitignored `corpus/`
  directory — source only, no transitive deps, no compilation (the Pattern phase
  is parse-only, so compiled artifacts are never needed). Versions are pinned
  exactly; hex versions are immutable, so the cache is reproducible.
  """

  # Top-popularity Elixir packages with `lib/*.ex`, pinned to the latest stable
  # at the time of writing (Erlang-only packages like telemetry/cowboy/ranch are
  # excluded — there is no Elixir source for the Pattern phase to parse).
  @packages [
    {:jason, "1.4.5"},
    {:plug, "1.19.2"},
    {:ecto, "3.14.0"},
    {:phoenix, "1.8.8"},
    {:decimal, "3.1.1"},
    {:gettext, "1.0.2"},
    {:poison, "6.0.0"},
    {:tesla, "1.20.0"},
    {:floki, "0.38.3"},
    {:credo, "1.7.19"}
  ]

  @root "corpus"

  @doc "The pinned `{package, version}` list."
  @spec packages() :: [{atom(), String.t()}]
  def packages, do: @packages

  @doc "Root directory the corpus is unpacked into (gitignored)."
  @spec root() :: String.t()
  def root, do: @root

  @doc "Local cache directory for a package's unpacked source."
  @spec dir(atom()) :: String.t()
  def dir(pkg), do: Path.join(@root, to_string(pkg))

  @doc "Every `lib/**/*.ex` file of a fetched package."
  @spec lib_files(atom()) :: [String.t()]
  def lib_files(pkg), do: Path.wildcard(Path.join([dir(pkg), "lib", "**", "*.ex"]))

  @doc "True if the package's source is present in `corpus/`."
  @spec fetched?(atom()) :: boolean()
  def fetched?(pkg), do: File.dir?(Path.join(dir(pkg), "lib"))

  @doc """
  Fetches each pinned package into `corpus/` if missing or version-mismatched.
  Idempotent — a no-op once the cache is warm, so the test loop and the report
  task pay the network cost only once.
  """
  @spec ensure_fetched!() :: :ok
  def ensure_fetched! do
    Enum.each(@packages, &fetch_one!/1)
  end

  defp fetch_one!({pkg, version}) do
    unless installed_version(pkg) == version do
      File.rm_rf!(dir(pkg))

      {out, status} =
        System.cmd(
          "mix",
          ["hex.package", "fetch", to_string(pkg), version, "--unpack", "--output", dir(pkg)],
          stderr_to_stdout: true
        )

      if status != 0 do
        raise "corpus fetch failed for #{pkg} #{version} (exit #{status}):\n#{out}"
      end
    end

    :ok
  end

  # Reads the unpacked tarball's hex_metadata.config (Erlang terms) to confirm
  # which version is on disk, so bumping a pin above triggers a re-fetch.
  defp installed_version(pkg) do
    config = Path.join(dir(pkg), "hex_metadata.config")

    with true <- File.exists?(config),
         {:ok, terms} <- :file.consult(String.to_charlist(config)) do
      Enum.find_value(terms, fn
        {"version", v} -> to_string(v)
        _ -> nil
      end)
    else
      _ -> nil
    end
  end
end
