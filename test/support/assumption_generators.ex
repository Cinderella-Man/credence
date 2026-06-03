defmodule Credence.AssumptionGenerators do
  @moduledoc """
  StreamData generators that produce only strings satisfying a given assumption,
  shared by every property test that needs that promise.

  The `single_codepoint_string/0` generator is the proof tool for
  `single_codepoint_graphemes`: every character it can emit is a single codepoint
  *by construction*, so the promise holds for every string it produces — no
  matter how they are concatenated. The popular presets don't have this property:

    * `StreamData.string(:ascii)` is safe but never reaches an accented letter,
      so it never exercises the interesting case.
    * `StreamData.string(:printable)` / `:utf8` build text one codepoint at a
      time and will sooner or later emit a lone combining mark that joins the
      previous letter into a two-codepoint grapheme — breaking the promise and
      failing the property test for the wrong reason.

  So we hand-pick a set of single-piece characters: printable ASCII plus the
  ready-made (precomposed) accented Latin-1 letters À–ÿ, each of which is one
  codepoint *and* one grapheme.
  """

  @doc """
  A generator of strings where every character is a single codepoint: printable
  ASCII (`\\s`–`~`) plus the precomposed Latin-1 accented letters À–ÿ (skipping
  the × and ÷ math symbols at 0xD7 / 0xF7).
  """
  def single_codepoint_string do
    StreamData.string([?\s..?~, 0xC0..0xD6, 0xD8..0xF6, 0xF8..0xFF])
  end
end
