defmodule Credence.Semantic.FixErlangBitwiseBif do
  @moduledoc """
  Fixes undefined bare Erlang bitwise BIF calls (band, bor, bsl, bsr, bxor,
  bnot) by prefixing them with `Bitwise.`.

  LLMs frequently write Erlang-style bare bitwise BIF calls that fail to
  compile in Elixir with "undefined function". The deterministic fix is to
  prefix the call with `Bitwise.` — e.g. `bsl(value, n)` becomes
  `Bitwise.bsl(value, n)`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @bitwise_bifs ~w(band bor bsl bsr bxor bnot)
  # Erlang-style infix bitwise operators that `import Bitwise` provides
  @bitwise_ops ~w(||| &&& <<< >>> ~~~ ^^^)

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    case parse_function_ref(msg) do
      {name, _arity} -> name in @bitwise_bifs or name in @bitwise_ops
      _ -> false
    end
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg} = diagnostic) do
    {name, arity} = parse_function_ref(msg)

    hint =
      if name in @bitwise_bifs,
        do: "use Bitwise.#{name} instead",
        else: "use Bitwise module functions instead"

    %Issue{
      rule: :fix_erlang_bitwise_bif,
      message: "undefined function #{name}/#{arity}; #{hint}",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg} = diagnostic) do
    case parse_function_ref(msg) do
      {name, _arity} when name in @bitwise_bifs ->
        line_no = line(diagnostic)
        replace_bare_bif(source, line_no, name)

      _ ->
        source
    end
  end

  defp parse_function_ref(msg) do
    case Regex.run(~r/undefined function ([^\s()]+)\/(\d+)/, msg) do
      [_, name, arity] -> {name, String.to_integer(arity)}
      _ -> nil
    end
  end

  defp replace_bare_bif(source, line_no, name) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {text, ^line_no} ->
        # Replace only bare (non-module-prefixed) calls: bsl( → Bitwise.bsl(
        # Avoids double-prefixing if already Bitwise.bsl(
        Regex.replace(
          ~r/(?<![.\w])#{Regex.escape(name)}\(/,
          text,
          "Bitwise.#{name}("
        )

      {text, _} ->
        text
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
