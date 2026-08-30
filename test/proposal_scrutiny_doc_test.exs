defmodule Credence.ProposalScrutinyDocTest do
  use ExUnit.Case, async: true

  @doc_path Path.expand("../docs/14-proposal-scrutiny.md", __DIR__)
  @oracle_path Path.expand("../gold_oracle.exs", __DIR__)

  test "E2 gold oracle is checked in and rejects an empty dataset" do
    doc = File.read!(@doc_path)
    oracle = File.read!(@oracle_path)

    b3 = doc |> String.split("### B.3 E2 — gold over-fire oracle dry-run\n\n") |> Enum.at(1)
    b3 = b3 |> String.split("\n### B.4 E2b", parts: 2) |> hd()

    assert b3 == """
           The runner is checked in at `gold_oracle.exs`. By default it expects the
           dataset in a sibling checkout; set `DATASET_ROOT` for any other location. It
           fails loudly instead of reporting a vacuous clean result when no golds exist.

           ```bash
           DATASET_ROOT=/path/to/elixir-sft-dataset MIX_ENV=test \\
             maintainer_tools/pr_review/run_capped.sh mix run gold_oracle.exs
           ```
           """

    oracle_guard = oracle |> String.split("\n\n{elapsed_us", parts: 2) |> hd()

    assert oracle_guard ==
             """
             dataset_root = System.get_env("DATASET_ROOT", "../elixir-sft-dataset")

             golds =
               dataset_root
               |> Path.join("tasks/*_01/solution.ex")
               |> Path.wildcard()
               |> Enum.sort()

             if golds == [], do: raise("no gold solutions found under \#{dataset_root}")
             """
             |> String.trim_trailing()
  end

  test "E2b compiles the emitted fixture and harness through the bounded helper" do
    doc = File.read!(@doc_path)

    calls =
      Regex.scan(
        ~r/(?:Code\.compile_file|Credence\.RuleHelpers\.compile_and_capture)\([^\n]+/,
        doc
      )

    assert calls == [["Credence.RuleHelpers.compile_and_capture(source) do"]]
  end
end
