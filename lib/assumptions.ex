defmodule Credence.Assumptions do
  @moduledoc """
  Safety switches — the promises Credence is allowed to make about your data.

  A **switch** (an *assumption*) is a checkable promise about the text your code
  handles **while it runs** — names, chat messages, file contents — *not* about
  the characters in your `.ex` source files. Some rules only give the exact same
  answer as your original code when a particular promise holds; those rules
  declare the promise via `assumptions/0` and run only while it is on.

  The reframed invariant:

  > **Credence never changes behaviour on any input your stated promises admit.**

  ## The two modes

  - **`:strict`** — you make *no* promises, so only rules that are correct for
    *every possible input* run. Bit-identical to your original code, guaranteed.
  - **the helpful default** — a small curated set of promises is on, which lets
    Credence also run the extra rules. Correct for the ~99% of real code whose
    running data is plain, single-piece text.

  ## Setting switches

  Pass `assumptions:` as one of three things (to `Credence.fix/2`,
  `Credence.analyze/2`, etc.), or set it project-wide via
  `config :credence, assumptions: ...`:

  - a **small map** naming only the switches you want to change —
    `%{single_codepoint_graphemes: false}`. It *patches* only the keys it names;
    every switch it does not mention falls through to the layer below.
  - **`:strict`** — a full reset that forces **every** switch off.
  - **`:default`** — a full reset that returns **every** switch to its built-in
    default (the mirror of `:strict`).

  ## Three places, later wins

  Credence folds three layers, later beating earlier:
  **call options > `config :credence` > built-in defaults.** A place that isn't
  set is skipped. Mechanically it starts from the full defaults map, then folds
  each later layer on top: `:strict`/`:default` overwrite *all* keys, a small map
  patches *only its own* keys (never expanded with defaults — that would let an
  unmentioned switch stomp the layer beneath it).

      # project-wide: play it safe everywhere
      config :credence, assumptions: :strict

      # one trusted run re-enables just this switch, leaving the rest off
      Credence.fix(code, assumptions: %{single_codepoint_graphemes: true})

  ## Inspecting

  `Credence.Pattern.rule_status/1` lists every rule, the promises it needs,
  whether it is on now, and which needed promises are off.
  `Credence.Pattern.enabled_rules/1` is the on-names from that list.

  ## The switches

  ### `single_codepoint_graphemes` (on by default)

  Promises that every character (grapheme) in your **running data** is a single
  codepoint — a plain single-piece character. No decomposed accents (an `"e"`
  plus a *separate* combining accent mark), no ZWJ emoji (`👨‍👩‍👧`), no flag
  sequences (`🇵🇱`). This is about the text your program *handles*, not the
  characters in your source file. It is on by default because LLM-generated
  Phoenix apps overwhelmingly process exactly this kind of text; turn it off
  (or use `:strict`) if your code processes arbitrary Unicode.
  """

  @type name :: atom()
  @type settings :: %{name() => boolean()}

  @registry %{
    single_codepoint_graphemes: %{
      default: true,
      summary:
        "Every character in your running data is a single codepoint (no decomposed " <>
          "accents, ZWJ emoji, or flag sequences). About running data, not source."
    }
  }

  @doc "The full registry: `%{name => %{default:, summary:}}`."
  @spec all() :: %{name() => %{default: boolean(), summary: String.t()}}
  def all, do: @registry

  @doc "The names of all known switches."
  @spec names() :: [name()]
  def names, do: Map.keys(@registry)

  @doc "The built-in default settings: `%{name => boolean}`."
  @spec defaults() :: settings()
  def defaults, do: Map.new(@registry, fn {name, %{default: d}} -> {name, d} end)

  @doc "Whether `name` is a known switch."
  @spec known?(term()) :: boolean()
  def known?(name), do: Map.has_key?(@registry, name)

  @doc """
  Validates a user-supplied settings map, raising `ArgumentError` if it names a
  switch that does not exist. Returns the map unchanged on success.
  """
  @spec validate!(map()) :: map()
  def validate!(map) when is_map(map) do
    case map |> Map.keys() |> Enum.reject(&known?/1) do
      [] ->
        map

      unknown ->
        raise ArgumentError,
              "unknown assumption(s): #{inspect(unknown)}. " <>
                "Known assumptions: #{inspect(names())}. " <>
                "Pass `:strict` to turn all off or `:default` to reset to defaults."
    end
  end
end
