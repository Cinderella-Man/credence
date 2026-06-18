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

  # Top-popularity Elixir packages with substantial `lib/*.ex`, pinned to the
  # latest stable at the time of writing. Selected from the most-downloaded hex
  # packages, filtered to genuine Elixir source: Erlang-only packages
  # (telemetry/cowboy/ranch/jose/…) and trivial 1-file shims (mime/castore/…)
  # are excluded — the Pattern phase is parse-only, so only real Elixir source
  # is useful. ~100 packages spanning web, DB, parsing, auth, and tooling.
  @packages [
    # Core / original set
    {:jason, "1.4.5"},
    {:plug, "1.19.2"},
    {:ecto, "3.14.0"},
    {:phoenix, "1.8.8"},
    {:decimal, "3.1.1"},
    {:gettext, "1.0.2"},
    {:poison, "6.0.0"},
    {:tesla, "1.20.0"},
    {:floki, "0.38.3"},
    {:credo, "1.7.19"},
    # Phoenix / web
    {:phoenix_live_view, "1.2.3"},
    {:phoenix_html, "4.3.0"},
    {:phoenix_pubsub, "2.2.0"},
    {:phoenix_ecto, "4.7.0"},
    {:phoenix_template, "1.0.4"},
    {:plug_cowboy, "2.8.1"},
    {:plug_crypto, "2.1.1"},
    {:websock_adapter, "0.6.0"},
    # Database
    {:ecto_sql, "3.14.0"},
    {:postgrex, "0.22.2"},
    {:db_connection, "2.10.1"},
    # HTTP / network
    {:finch, "0.23.0"},
    {:mint, "1.9.0"},
    {:httpoison, "3.0.0"},
    {:swoosh, "1.26.1"},
    {:ex_aws, "2.7.0"},
    {:libcluster, "3.5.0"},
    # Parsing / docs / markup
    {:nimble_parsec, "1.4.2"},
    {:nimble_options, "1.1.1"},
    {:earmark, "1.4.49"},
    {:earmark_parser, "1.4.45"},
    {:makeup, "1.2.1"},
    {:makeup_elixir, "1.0.1"},
    {:ex_doc, "0.40.3"},
    {:csv, "3.2.2"},
    # Concurrency / jobs
    {:oban, "2.23.0"},
    {:gen_stage, "1.3.2"},
    {:cachex, "4.1.1"},
    {:telemetry_metrics, "1.1.0"},
    # Auth
    {:joken, "2.6.2"},
    {:comeonin, "5.5.1"},
    {:bcrypt_elixir, "3.3.2"},
    # GraphQL
    {:absinthe, "1.11.0"},
    # Utilities / testing
    {:timex, "3.7.13"},
    {:money, "1.15.0"},
    {:faker, "0.18.0"},
    {:ex_machina, "2.8.0"},
    {:mox, "1.2.0"},
    {:stream_data, "1.3.0"},
    {:elixir_make, "0.10.0"},

    # --- Expansion to 100: more of the most-downloaded / most-starred Elixir
    # packages, same filter (genuine Elixir `lib/*.ex`, no Erlang-only or
    # trivial 1-file shims). ---

    # HTTP / web / API
    {:req, "0.6.1"},
    {:broadway, "1.3.0"},
    {:flow, "1.2.4"},
    {:websockex, "0.5.1"},
    {:bypass, "2.1.0"},
    {:corsica, "2.1.3"},
    {:remote_ip, "1.2.0"},
    {:absinthe_plug, "1.5.10"},
    {:dataloader, "2.0.2"},
    {:open_api_spex, "3.22.3"},
    # Auth / security
    {:guardian, "2.4.0"},
    {:pow, "1.0.39"},
    {:argon2_elixir, "4.1.3"},
    {:pbkdf2_elixir, "2.3.1"},
    {:ueberauth, "0.10.8"},
    {:sobelow, "0.14.1"},
    # Database / Ecto ecosystem
    {:redix, "1.5.3"},
    {:myxql, "0.9.0"},
    {:exqlite, "0.37.0"},
    {:ecto_sqlite3, "0.24.1"},
    {:ecto_enum, "1.4.0"},
    {:flop, "0.26.4"},
    {:paginator, "1.2.0"},
    # Caching / distributed
    {:con_cache, "1.1.1"},
    {:nebulex, "3.0.4"},
    {:horde, "0.10.0"},
    {:swarm, "3.4.0"},
    # Numerical / data / Livebook
    {:nx, "0.12.1"},
    {:explorer, "0.11.1"},
    {:kino, "0.19.0"},
    # Internationalization
    {:ex_cldr, "2.47.4"},
    {:ex_cldr_numbers, "2.38.3"},
    # Dev tooling
    {:styler, "1.11.0"},
    {:excoveralls, "0.18.5"},
    {:dialyxir, "1.4.7"},
    {:benchee, "1.5.1"},
    # Scheduling / messaging
    {:quantum, "3.5.3"},
    {:crontab, "1.2.0"},
    {:amqp, "4.1.1"},
    {:tzdata, "1.1.3"},
    # Email / monitoring
    {:bamboo, "2.5.0"},
    {:appsignal, "2.17.3"},
    {:sentry, "13.2.0"},
    # Frameworks
    {:ash, "3.29.1"},
    {:spark, "2.7.2"},
    # Markup / serialization
    {:saxy, "1.6.0"},
    {:yaml_elixir, "2.12.2"},
    {:sweet_xml, "0.7.5"},
    # Phoenix / misc
    {:phoenix_live_dashboard, "0.8.7"},
    {:typed_struct, "0.3.0"}
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
