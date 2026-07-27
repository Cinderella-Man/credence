defmodule Credence.Semantic.FixErlangBitwiseBif do
  @moduledoc """
  Fixes undefined bare Erlang bitwise BIF calls (band, bor, bsl, bsr, bxor,
  bnot) by prefixing them with `Bitwise.`, and fixes deprecated Bitwise infix
  operator forms (|||, &&&, <<<, >>>, ~~~, ^^^) by replacing them with the
  equivalent `Bitwise.xxx()` function calls.

  LLMs frequently write Erlang-style bare bitwise BIF calls or deprecated
  operator forms that fail to compile in Elixir with "undefined function".
  The deterministic fix prefixes BIF calls with `Bitwise.` — e.g.
  `bsl(value, n)` becomes `Bitwise.bsl(value, n)` — and replaces infix
  operators with their module function equivalents — e.g. `a ||| b` becomes
  `Bitwise.bor(a, b)`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @bitwise_bifs ~w(band bor bsl bsr bxor bnot)
  # Erlang-style infix bitwise operators that `import Bitwise` provides
  @bitwise_ops ~w(||| &&& <<< >>> ~~~ ^^^)

  # Map infix operator names to their Bitwise module function equivalents
  @op_to_fn %{
    "|||" => :bor,
    "&&&" => :band,
    "<<<" => :bsl,
    ">>>" => :bsr,
    "~~~" => :bnot,
    "^^^" => :bxor
  }

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

      {name, _arity} when name in @bitwise_ops ->
        replace_infix_operator(source, name)

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

  # Replaces deprecated Bitwise infix operators (|||, ^^^, <<<, >>>, &&&, ~~~)
  # with their Bitwise module function equivalents using AST transformation.
  defp replace_infix_operator(source, op_name) do
    op_atom = String.to_atom(op_name)
    fn_name = Map.fetch!(@op_to_fn, op_name)

    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          {^op_atom, _meta, args} when is_list(args) ->
            {{:., [], [{:__aliases__, [], [:Bitwise]}, fn_name]}, [], args}

          node ->
            node
        end)

      if result == ast do
        source
      else
        Sourceror.to_string(result)
      end
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
