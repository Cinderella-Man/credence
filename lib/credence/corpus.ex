defmodule Credence.Corpus do
  @moduledoc """
  Real-world corpus of popular hex packages **and beefy application repos**, used
  by the over-firing test layer (`test/corpus/over_firing_test.exs`) and the
  `mix credence.corpus` / `mix credence.corpus.fetch` maintainer tasks.

  The premise: this is widely used, well-reviewed Elixir code, so Credence should
  find nothing to flag. Anything it *does* flag is a candidate over-fire (a false
  positive on idiomatic code) — unless it is a reviewed, genuinely-correct
  suggestion (see the allowlist in the test).

  Two sources, both into a gitignored `corpus/` directory (source only, no deps,
  no compilation — the Pattern phase is parse-only):

    * `@packages` — hex libraries, fetched with `mix hex.package fetch`. Versions
      are immutable, so the cache is reproducible.
    * `@repos` — large real-world application repos (Supabase's supavisor, Livebook,
      Plausible, Blockscout, the Elixir language itself, …), shallow-cloned at an
      exact commit SHA so line numbers — and thus the snapshot — stay reproducible.
  """

  # Top-popularity Elixir packages with substantial `lib/*.ex`, pinned to the
  # latest stable at the time of writing. Selected from the most-downloaded hex
  # packages, filtered to genuine Elixir source: Erlang-only packages
  # (telemetry/cowboy/ranch/jose/…) and trivial 1-file shims (mime/castore/…)
  # are excluded — the Pattern phase is parse-only, so only real Elixir source
  # is useful. ~465 hex packages plus ~36 beefy app repos (see @repos) — ~500 entries.
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
    {:ymlr, "5.1.5"},

    # --- Expansion to 500: a third wave from the most-downloaded hex
    # packages (download-ranked, same genuine-Elixir filter). Alongside the
    # beefy application repos in `@repos`, this takes the corpus to ~500
    # entries. ---
    {:abacus, "2.2.0"},
    {:abi, "1.3.0"},
    {:absinthe_error_payload, "1.2.0"},
    {:absinthe_federation, "0.9.2"},
    {:absinthe_graphql_ws, "0.3.6"},
    {:absinthe_phoenix, "2.0.5"},
    {:absinthe_relay, "1.6.0"},
    {:ace, "0.19.0"},
    {:apex, "1.2.1"},
    {:apollo_tracing, "0.4.4"},
    {:appsignal_phoenix, "2.8.1"},
    {:appsignal_plug, "2.1.3"},
    {:arc, "0.11.0"},
    {:arc_ecto, "0.11.3"},
    {:artificery, "0.4.4"},
    {:assertions, "0.22.0"},
    {:bamboo_ses, "0.5.0"},
    {:bamboo_smtp, "4.2.2"},
    {:basic_auth, "2.2.5"},
    {:benchfella, "0.3.5"},
    {:blacksmith, "0.2.1"},
    {:bodyguard, "2.4.3"},
    {:braintree, "0.16.0"},
    {:broadway_cloud_pub_sub, "1.0.0"},
    {:broadway_dashboard, "0.4.1"},
    {:broadway_kafka, "0.4.4"},
    {:browser, "0.5.5"},
    {:bugsnag, "3.0.2"},
    {:bunt, "1.0.0"},
    {:bureaucrat, "0.2.10"},
    {:canada, "2.0.0"},
    {:cc_precompiler, "0.1.11"},
    {:cldr_utils, "2.29.7"},
    {:cloak, "1.1.4"},
    {:cloak_ecto, "1.3.0"},
    {:coerce, "1.0.2"},
    {:combine, "0.10.0"},
    {:commanded, "1.4.10"},
    {:commanded_eventstore_adapter, "1.4.2"},
    {:complex, "0.7.0"},
    {:confex, "3.5.1"},
    {:configparser_ex, "5.0.0"},
    {:config_tuples, "0.4.2"},
    {:conform, "2.5.2"},
    {:countries, "1.6.0"},
    {:crc, "0.10.6"},
    {:credo_naming, "2.1.0"},
    {:date_time_parser, "1.3.0"},
    {:decorator, "1.4.0"},
    {:deferred_config, "0.1.1"},
    {:delta_crdt, "0.6.5"},
    {:digital_token, "2.0.0"},
    {:distance, "1.1.3"},
    {:distillery, "2.1.1"},
    {:dns, "2.4.0"},
    {:domainatrex, "3.2.0"},
    {:dotenvy, "1.1.1"},
    {:ecto_network, "1.6.1"},
    {:ed25519, "1.5.1"},
    {:edeliver, "1.9.2"},
    {:elasticsearch, "1.1.0"},
    {:elastix, "0.10.0"},
    {:elixir_xml_to_map, "3.1.0"},
    {:elixlsx, "0.6.0"},
    {:email_checker, "0.2.4"},
    {:eqrcode, "0.2.1"},
    {:erlex, "0.2.9"},
    {:eternal, "1.2.2"},
    {:ets, "0.9.0"},
    {:eventstore, "1.4.8"},
    {:exactor, "2.2.4"},
    {:ex_aws_s3, "2.5.9"},
    {:ex_aws_ses, "2.4.1"},
    {:ex_aws_sts, "2.3.0"},
    {:excellent_migrations, "0.1.10"},
    {:ex_check, "0.16.0"},
    {:ex_cldr_currencies, "2.17.2"},
    {:ex_cldr_lists, "2.12.2"},
    {:ex_cldr_territories, "2.12.0"},
    {:ex_crypto, "0.10.0"},
    {:ex_doc_dash, "0.3.1"},
    {:exexec, "0.2.0"},
    {:ex_force, "0.4.1"},
    {:ex_hash_ring, "7.0.0"},
    {:ex_image_info, "1.0.0"},
    {:ex_money, "6.0.0"},
    {:ex_money_sql, "2.0.0"},
    {:expo, "1.1.1"},
    {:exprof, "0.2.4"},
    {:exprotobuf, "1.2.17"},
    {:exq_ui, "0.19.0"},
    {:ex_rated, "2.1.0"},
    {:exredis, "0.3.0"},
    {:ex_unit_notifier, "1.3.1"},
    {:flop_phoenix, "0.26.1"},
    {:fss, "0.1.1"},
    {:fun_with_flags, "1.13.0"},
    {:fun_with_flags_ui, "1.1.0"},
    {:gen_registry, "1.3.0"},
    {:gen_retry, "1.4.0"},
    {:geo, "4.1.0"},
    {:geocalc, "0.8.5"},
    {:geolix, "2.1.0"},
    {:geo_postgis, "3.7.1"},
    {:git_cli, "0.3.0"},
    {:glob_ex, "0.1.11"},
    {:google_api_big_query, "0.88.0"},
    {:google_api_drive, "0.32.0"},
    {:google_api_pub_sub, "0.42.0"},
    {:google_api_secret_manager, "0.23.0"},
    {:google_api_storage, "0.46.1"},
    {:google_gax, "0.4.1"},
    {:google_maps, "0.11.0"},
    {:google_protos, "0.4.0"},
    {:guardian_db, "3.0.0"},
    {:ham, "0.3.2"},
    {:hammer_backend_redis, "7.1.1"},
    {:hashids, "2.1.0"},
    {:heroicons, "0.5.7"},
    {:honeybadger, "0.28.0"},
    {:hound, "1.1.1"},
    {:hpax, "1.0.3"},
    {:igniter, "0.8.1"},
    {:image, "0.69.0"},
    {:inch_ex, "2.1.0"},
    {:ink, "1.2.1"},
    {:instream, "2.2.1"},
    {:instruments, "2.11.0"},
    {:iptrie, "0.10.0"},
    {:ja_serializer, "0.18.2"},
    {:jaxon, "2.0.8"},
    {:jose, "1.11.12"},
    {:json, "1.4.1"},
    {:json_web_token, "0.2.10"},
    {:k8s, "2.8.0"},
    {:kadabra, "0.6.2"},
    {:kaffe, "2.0.0"},
    {:kafka_ex, "1.0.0"},
    {:kayrock, "1.0.0"},
    {:knigge, "1.4.1"},
    {:lazy_html, "0.1.11"},
    {:libcluster_ec2, "0.8.2"},
    {:libgraph, "0.16.0"},
    {:lob_elixir, "2.0.0"},
    {:logster, "1.1.1"},
    {:mail, "0.5.2"},
    {:makeup_erlang, "1.1.0"},
    {:makeup_html, "0.2.0"},
    {:mariaex, "0.9.1"},
    {:markdown_formatter, "1.1.0"},
    {:matrix_reloaded, "2.3.0"},
    {:memcachex, "0.5.7"},
    {:memoize, "1.4.5"},
    {:merkle_map, "0.2.2"},
    {:mint_web_socket, "1.0.5"},
    {:mjml, "6.0.0"},
    {:moar, "5.0.0"},
    {:mockery, "2.5.0"},
    {:mojito, "0.7.12"},
    {:morphix, "0.8.1"},
    {:msgpax, "2.4.0"},
    {:multipart, "0.6.1"},
    {:murmur, "2.0.0"},
    {:nanoid, "2.1.0"},
    {:nebulex_redis_adapter, "3.0.0"},
    {:nerves_bootstrap, "1.15.2"},
    {:nestru, "1.0.1"},
    {:neuron, "5.1.0"},
    {:nimble_pool, "1.1.0"},
    {:number, "1.0.5"},
    {:numbers, "5.2.5"},
    {:o11y, "0.3.0"},
    {:oban_met, "1.2.0"},
    {:oban_web, "2.12.5"},
    {:octo_fetch, "0.5.0"},
    {:opentelemetry_absinthe, "2.4.0"},
    {:opentelemetry_api, "1.5.0"},
    {:open_telemetry_decorator, "1.5.10"},
    {:opentelemetry_liveview, "1.0.0-rc.4"},
    {:opentelemetry_oban, "1.2.0"},
    {:opentelemetry_process_propagator, "0.3.0"},
    {:opentelemetry_redix, "0.1.1"},
    {:opentelemetry_semantic_conventions, "1.27.0"},
    {:optimal, "0.3.7"},
    {:paper_trail, "1.1.2"},
    {:parallel_stream, "1.1.0"},
    {:params, "2.3.0"},
    {:paraxial, "2.9.0"},
    {:pdf_generator, "0.6.2"},
    {:peep, "5.0.1"},
    {:petal_components, "4.1.2"},
    {:pfx, "0.14.2"},
    {:phoenix_bert, "1.1.5"},
    {:phoenix_pubsub_redis, "3.1.1"},
    {:phoenix_storybook, "1.2.0"},
    {:phoenix_swagger, "0.8.5"},
    {:phone, "0.5.11"},
    {:phx_new, "1.8.8"},
    {:pigeon, "2.0.1"},
    {:plaid_elixir, "3.4.0"},
    {:plugsnag, "1.7.2"},
    {:porcelain, "2.0.3"},
    {:premailex, "1.0.0"},
    {:process_tree, "0.3.0"},
    {:progress_bar, "3.0.0"},
    {:prometheus_ex, "5.1.0"},
    {:prometheus_plugs, "1.1.5"},
    {:prom_ex, "1.11.0"},
    {:proper_case, "1.3.1"},
    {:protox, "2.0.9"},
    {:puid, "2.7.1"},
    {:qr_code, "3.2.0"},
    {:ratio, "4.0.1"},
    {:result, "1.7.2"},
    {:retry, "0.19.0"},
    {:reverse_proxy_plug, "3.0.4"},
    {:rewrite, "1.3.0"},
    {:rexbug, "1.0.6"},
    {:rollbax, "0.11.0"},
    {:rustler, "0.38.0"},
    {:rustler_precompiled, "0.9.0"},
    {:sage, "0.6.3"},
    {:samly, "1.4.0"},
    {:scrivener, "2.7.2"},
    {:scrivener_ecto, "3.1.0"},
    {:scrivener_html, "1.8.1"},
    {:segment, "0.2.7"},
    {:sendgrid, "2.0.0"},
    {:sftp_client, "2.1.0"},
    {:shortuuid, "4.1.0"},
    {:slack, "0.23.5"},
    {:slugger, "0.3.0"},
    {:socket, "0.3.13"},
    {:spandex_datadog, "1.4.0"},
    {:spandex_ecto, "0.7.0"},
    {:spandex_phoenix, "1.1.0"},
    {:spitfire, "0.3.13"},
    {:statistex, "1.1.1"},
    {:statistics, "0.6.3"},
    {:statix, "1.4.0"},
    {:table, "0.1.2"},
    {:table_rex, "4.1.0"},
    {:telemetry_metrics_prometheus_core, "1.2.1"},
    {:telemetry_metrics_statsd, "0.7.2"},
    {:temp, "0.4.9"},
    {:tidewave, "0.6.0"},
    {:timex_ecto, "3.4.0"},
    {:ua_inspector, "3.12.0"},
    {:ua_parser, "1.10.0"},
    {:ueberauth_auth0, "2.1.0"},
    {:ueberauth_identity, "0.4.2"},
    {:ueberauth_microsoft, "0.25.0"},
    {:uinta, "0.16.0"},
    {:unsafe, "1.0.2"},
    {:varint, "1.6.0"},
    {:vix, "0.38.0"},
    {:waffle, "1.1.10"},
    {:waffle_ecto, "0.0.12"},
    {:web_driver_client, "0.2.0"},
    {:wormhole, "2.3.0"},
    {:x509, "0.9.2"},
    {:xlsxir, "1.6.4"},
    {:zen_monitor, "2.1.0"},
    {:zstream, "0.6.7"}
  ]

  # Beefy real-world *application* repositories (not hex libraries) — Supabase's
  # supavisor/realtime, Livebook, Plausible, Blockscout, the Elixir language
  # itself, etc. Fetched by shallow git clone of an exact commit SHA (immutable,
  # so line numbers — and thus the over-fire snapshot — are reproducible). These
  # exercise Credence on large production Phoenix/umbrella codebases, not just
  # well-trodden library code.
  @repos [
    {:accent, "https://github.com/mirego/accent.git",
     "361876c0f3f2c14d779b91470e727696a88bf194"},
    {:archethic, "https://github.com/archethic-foundation/archethic-node.git",
     "7ea2e2262dcc58eacec7ca93baee4f5d14af12e7"},
    {:ash_admin, "https://github.com/ash-project/ash_admin.git",
     "a579c8dda4c5e9048f4a80c8e062fc80569e4971"},
    {:ash_authentication, "https://github.com/team-alembic/ash_authentication.git",
     "22f4c6384397796c93ceba1a521ef48bc34961c8"},
    {:ash_graphql, "https://github.com/ash-project/ash_graphql.git",
     "179f6318af874e9bcfdb4d2f32b457deac8a316d"},
    {:ash_json_api, "https://github.com/ash-project/ash_json_api.git",
     "cdd5559c1fe84763ea42d3e3f8152015a38b405d"},
    {:blockscout, "https://github.com/blockscout/blockscout.git",
     "551ae8bb7111288abe54ba09e0ad8987f3e29566"},
    {:bumblebee, "https://github.com/elixir-nx/bumblebee.git",
     "d0774e8ab8c4d5ac60ade95ec8dc9e1f0efd7306"},
    {:changelog, "https://github.com/thechangelog/changelog.com.git",
     "9c26349b4a0887376daabed9b487c469e83f9091"},
    {:elixir_desktop, "https://github.com/elixir-desktop/desktop.git",
     "d5a7e330d6103a240f03b0f8aeb7e965005c444a"},
    {:elixir_lang, "https://github.com/elixir-lang/elixir.git",
     "ec50a88ee4391f1f10b7e9592edd53e8589c7b60"},
    {:elixir_ls, "https://github.com/elixir-lsp/elixir-ls.git",
     "256ec7787dc14fa666817199ec6aa5dc64787e37"},
    {:firezone, "https://github.com/firezone/firezone.git",
     "02da9189ab7c55aa9b7eb637dbace5df94fb9dbf"},
    {:glific, "https://github.com/glific/glific.git",
     "cbdee643951739fcf3d26444999562de06ad2d65"},
    {:grpc, "https://github.com/elixir-grpc/grpc.git",
     "38b4aaadbd4f82f2511af429b0fbf486c154d984"},
    {:hexpm, "https://github.com/hexpm/hexpm.git",
     "c84a83e8ca8127a7acdc27631923a05d73cd24f0"},
    {:instructor, "https://github.com/thmsmlr/instructor_ex.git",
     "c6dcad9e70c0db0d54c65efb85b56de4129d847b"},
    {:keila, "https://github.com/pentacent/keila.git",
     "2eb93f2f7a81fd9f518fcb74e89a93da3605dfd1"},
    {:lexical, "https://github.com/lexical-lsp/lexical.git",
     "477e8b418b27960710109d0014167bb371b0cade"},
    {:live_beats, "https://github.com/fly-apps/live_beats.git",
     "ac9780472e7019af274110a1cf71250a8d40c986"},
    {:livebook, "https://github.com/livebook-dev/livebook.git",
     "364fa68a49c9ceac9fe53beace54ad0743b77903"},
    {:logflare, "https://github.com/Logflare/logflare.git",
     "aad1eb921bc98fc7111e622e720d5461966a583a"},
    {:membrane_core, "https://github.com/membraneframework/membrane_core.git",
     "9c862b4d070ea0a03f86f54f4854446ed5ac717a"},
    {:membrane_rtc_engine, "https://github.com/fishjam-dev/membrane_rtc_engine.git",
     "2b519efdcdecd737eeeaa74be8e50904f2c5d0c0"},
    {:mobilizon, "https://framagit.org/framasoft/mobilizon.git",
     "029ad665a98e9bc5d3da8c4eaa716723a0ec0dfa"},
    {:nerves, "https://github.com/nerves-project/nerves.git",
     "e1b5f1bb57911235c7877943e3dbec0cb026c308"},
    {:next_ls, "https://github.com/elixir-tools/next-ls.git",
     "eb47c98eef92ffe2b369c7c2bf56ce63b837f949"},
    {:papercups, "https://github.com/papercups-io/papercups.git",
     "6a6f5adc7f0cef5813b2c2f1c0659922defaf976"},
    {:plausible, "https://github.com/plausible/analytics.git",
     "648f16f7e679b8f10f81194dc9c6ec046b3c68f2"},
    {:reactor, "https://github.com/ash-project/reactor.git",
     "0c498c1f1d13970339c580d256b946b3592e6ef1"},
    {:realtime, "https://github.com/supabase/realtime.git",
     "3d022fea53d8adbe42f0cf555a2d84f194db2c19"},
    {:sequin, "https://github.com/sequinstream/sequin.git",
     "46ce4e1048437575ce3c40ebb3eb589a4b9e4f27"},
    {:supavisor, "https://github.com/supabase/supavisor.git",
     "469aa09ef876a757914080c63e600e0ba7c43c3b"},
    {:surface, "https://github.com/surface-ui/surface.git",
     "b378f199a265e86afdf6efbc66dd174b6e002d89"},
    {:teslamate, "https://github.com/adriankumpf/teslamate.git",
     "a115cc9989fc47e9c3010d2f994ad79e46aed8e1"},
    {:tucan, "https://github.com/pnezis/tucan.git",
     "56b17b561cc788ae0035a92fa4c3cd35b9941ee3"}
  ]

  @root "corpus"

  @doc "The pinned `{package, version}` list (hex libraries only)."
  @spec packages() :: [{atom(), String.t()}]
  def packages, do: @packages

  @doc "The pinned `{name, git_url, sha}` list (beefy application repos)."
  @spec repos() :: [{atom(), String.t(), String.t()}]
  def repos, do: @repos

  @doc """
  Every corpus entry as `{name, label}` — hex packages labelled by version,
  git repos by short SHA. The unit of iteration for the corpus tests and report.
  """
  @spec entries() :: [{atom(), String.t()}]
  def entries do
    Enum.map(@packages, fn {name, version} -> {name, version} end) ++
      Enum.map(@repos, fn {name, _url, sha} -> {name, String.slice(sha, 0, 8)} end)
  end

  @doc "Root directory the corpus is unpacked into (gitignored)."
  @spec root() :: String.t()
  def root, do: @root

  @doc "Local cache directory for a package's unpacked source."
  @spec dir(atom()) :: String.t()
  def dir(pkg), do: Path.join(@root, to_string(pkg))

  @doc """
  Every Elixir source file of a fetched entry: any `lib/**/*.ex` at any depth —
  a hex package's top-level `lib/`, an umbrella's `apps/*/lib/`, or a multi-app
  repo's `<sub>/lib/` (e.g. grpc's `grpc/lib`, `grpc_core/lib`). Non-production
  trees (`test/`, `deps/`, `_build/`, JS `node_modules/`) are excluded, since the
  over-fire premise is well-reviewed *production* code.
  """
  @spec lib_files(atom()) :: [String.t()]
  def lib_files(name) do
    dir(name)
    |> Path.join("**/lib/**/*.ex")
    |> Path.wildcard()
    |> Enum.reject(&excluded_path?/1)
  end

  @excluded_segments ["/deps/", "/_build/", "/test/", "/node_modules/", "/.git/"]
  defp excluded_path?(path), do: String.contains?(path, @excluded_segments)

  @doc "True if the entry's source is present in `corpus/`."
  @spec fetched?(atom()) :: boolean()
  def fetched?(name), do: lib_files(name) != []

  @doc """
  Fetches every pinned hex package and git repo into `corpus/` if missing or at
  the wrong version/SHA. Idempotent — a no-op once the cache is warm, so the
  test loop and the report task pay the network cost only once.
  """
  @spec ensure_fetched!() :: :ok
  def ensure_fetched! do
    Enum.each(@packages, &fetch_one!/1)
    Enum.each(@repos, &fetch_repo!/1)
  end

  # Shallow-clone a single repo at its pinned SHA. `git init` + `fetch --depth 1
  # <sha>` + `checkout` pins an exact commit (GitHub/GitLab allow fetching a SHA
  # directly), so the working tree is reproducible across machines.
  defp fetch_repo!({name, url, sha}) do
    unless installed_sha(name) == sha do
      File.rm_rf!(dir(name))
      File.mkdir_p!(dir(name))

      git!(["init", "-q", dir(name)], name, sha)
      git!(["-C", dir(name), "remote", "add", "origin", url], name, sha)
      git!(["-C", dir(name), "fetch", "-q", "--depth", "1", "origin", sha], name, sha)
      git!(["-C", dir(name), "checkout", "-q", "--detach", "FETCH_HEAD"], name, sha)
    end

    :ok
  end

  defp git!(args, name, sha) do
    {out, status} = System.cmd("git", args, stderr_to_stdout: true)

    if status != 0 do
      raise "corpus git fetch failed for #{name} @ #{sha} (exit #{status}):\n#{out}"
    end
  end

  defp installed_sha(name) do
    case System.cmd("git", ["-C", dir(name), "rev-parse", "HEAD"], stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      _ -> nil
    end
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
