defmodule Credence.Syntax.NoCaptureAsIdentityFunction do
  @moduledoc """
  Detects and replaces `&variable` used as an identity-function callback.

  LLMs frequently write `&variable` intending it as a shorthand for
  `fn _ -> variable end` (an identity function that ignores its argument and
  returns `variable`). In Elixir, however, `&bare_identifier` is invalid
  capture syntax — only these forms are legal:

    * `&Mod.fun/arity` — qualified function reference
    * `&fun/arity` — local function reference
    * `&body(&1, ...)` — capture body with numbered parameters

  A bare `&identifier` (without `/arity` or capture parameters) always fails
  to parse. The fix replaces each `&identifier` with `fn _ -> identifier end`.

  ## Bad (won't parse)

      Map.update!(m, :key, &new_value)
      Enum.map(list, &transform)

  ## Good

      Map.update!(m, :key, fn _ -> new_value end)
      Enum.map(list, fn _ -> transform end)
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # Matches `&identifier` where:
  #   - `identifier` starts with a letter or underscore (not a digit like &1)
  #   - NOT followed by `.` (module path: &Mod.func)
  #   - NOT followed by `/` and digits (arity: &func/1)
  #   - NOT followed by `(` (capture body: &func(&1))
  #   - NOT followed by `&` (nested capture: &(&1 + 1))
  @capture_identity_pattern ~r/&([a-zA-Z_][a-zA-Z0-9_]++)(?![.\/(&])/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if capture_identity_line?(line) do
        [
          %Issue{
            rule: :no_capture_as_identity_function,
            message:
              "`&variable` is not valid Elixir capture syntax; " <>
                "use `fn _ -> variable end` instead.",
            meta: %{line: line_no}
          }
        ]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if capture_identity_line?(line), do: fix_line(line), else: line
    end)
  end

  defp capture_identity_line?(line) do
    not comment?(line) and Regex.match?(@capture_identity_pattern, line)
  end

  defp comment?(line), do: Regex.match?(~r/^\s*#/, line)

  defp fix_line(line) do
    Regex.replace(@capture_identity_pattern, line, fn _match, var_name ->
      "fn _ -> #{var_name} end"
    end)
  end
end
