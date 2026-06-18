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
  # is useful. ~200 packages spanning web, DB, parsing, auth, and tooling.
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
    {:typed_struct, "0.3.0"},

    # --- Expansion to 200: a second wave of widely-used packages, same
    # filter (genuine Elixir `lib/*.ex`, no Erlang-only or 1-file shims).
    # Spans web servers, Ash ecosystem, ML, AWS, auth, jobs, testing,
    # templating, config, CLI, observability, and Ecto/data tooling. ---
    {:ash_phoenix, "2.3.23"},
    {:ash_postgres, "2.10.0"},
    {:assent, "0.3.1"},
    {:axon, "0.8.1"},
    {:bandit, "1.12.0"},
    {:boundary, "0.10.4"},
    {:briefly, "0.5.1"},
    {:broadway_rabbitmq, "0.8.2"},
    {:broadway_sqs, "0.7.4"},
    {:calendar, "1.0.0"},
    {:cubdb, "2.0.2"},
    {:dart_sass, "0.7.0"},
    {:deep_merge, "1.0.2"},
    {:doctor, "0.23.0"},
    {:domo, "1.5.19"},
    {:ecto_dev_logger, "0.15.0"},
    {:ecto_psql_extras, "0.8.8"},
    {:error_tracker, "0.9.0"},
    {:esbuild, "0.10.0"},
    {:ex_aws_dynamo, "4.2.2"},
    {:ex_aws_sns, "2.3.5"},
    {:ex_aws_sqs, "3.4.0"},
    {:ex_cldr_calendars, "2.4.3"},
    {:ex_cldr_dates_times, "2.25.6"},
    {:ex_cldr_units, "3.20.4"},
    {:ex_json_schema, "0.11.4"},
    {:ex_phone_number, "0.4.11"},
    {:exq, "0.23.0"},
    {:ex_twilio, "0.10.0"},
    {:exvcr, "0.17.1"},
    {:file_system, "1.1.1"},
    {:gen_state_machine, "3.0.0"},
    {:git_hooks, "0.8.1"},
    {:goth, "1.4.5"},
    {:hammer, "7.4.0"},
    {:hammox, "0.7.1"},
    {:honeydew, "1.5.0"},
    {:html_entities, "0.5.2"},
    {:html_sanitize_ex, "1.5.1"},
    {:inflex, "2.1.0"},
    {:joken_jwks, "1.7.0"},
    {:jsonpatch, "2.3.1"},
    {:libring, "1.7.0"},
    {:liquex, "0.15.0"},
    {:logger_json, "7.0.4"},
    {:makeup_eex, "2.0.2"},
    {:mdex, "0.13.0"},
    {:meeseeks, "0.18.0"},
    {:memento, "0.6.0"},
    {:mimic, "2.3.0"},
    {:mix_audit, "2.1.5"},
    {:mix_test_watch, "1.4.0"},
    {:mogrify, "0.9.3"},
    {:mongodb_driver, "1.6.3"},
    {:mua, "0.2.6"},
    {:new_relic_agent, "1.40.2"},
    {:nimble_ownership, "1.0.2"},
    {:nimble_publisher, "2.0.0"},
    {:norm, "0.13.1"},
    {:oapi_generator, "0.4.0"},
    {:oauth2, "2.1.1"},
    {:optimus, "0.6.1"},
    {:owl, "0.13.1"},
    {:parent, "0.13.0"},
    {:patch, "0.16.0"},
    {:pathex, "2.6.1"},
    {:phoenix_html_helpers, "1.0.1"},
    {:phoenix_live_reload, "1.6.2"},
    {:plug_attack, "0.4.3"},
    {:polymorphic_embed, "5.0.6"},
    {:propcheck, "1.5.0"},
    {:protobuf, "0.17.0"},
    {:ratatouille, "0.5.1"},
    {:recase, "0.9.1"},
    {:recode, "0.8.0"},
    {:scholar, "0.4.1"},
    {:solid, "1.3.2"},
    {:sourceror, "1.12.2"},
    {:spandex, "3.2.0"},
    {:stripity_stripe, "3.3.1"},
    {:tailwind, "0.5.1"},
    {:tds, "2.3.8"},
    {:telemetry_metrics_prometheus, "1.1.0"},
    {:tentacat, "2.5.0"},
    {:thousand_island, "1.5.0"},
    {:toml, "0.7.0"},
    {:toml_elixir, "3.1.0"},
    {:typed_ecto_schema, "0.4.3"},
    {:tz, "0.28.2"},
    {:ueberauth_github, "0.8.3"},
    {:ueberauth_google, "0.12.1"},
    {:uniq, "0.6.3"},
    {:vapor, "0.10.0"},
    {:vega_lite, "0.1.11"},
    {:verk, "1.7.3"},
    {:vex, "0.9.2"},
    {:wallaby, "0.30.12"},
    {:xema, "0.17.9"},
    {:xml_builder, "2.4.0"},
    {:ymlr, "5.1.5"}
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
