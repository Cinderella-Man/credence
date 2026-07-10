defmodule Credence.Semantic.FixBitwiseInfixOperator do
  @moduledoc """
  Fixes syntax errors caused by bare Bitwise infix operators (|||, &&&, <<<,
  >>>, ~~~, ^^^) used without `import Bitwise`.

  Without the import, these operators are not recognised by the parser, which
  emits a syntax-error diagnostic.  The fix replaces each bare infix operator
  with the equivalent `Bitwise.xxx()` function call — e.g. `a ||| b` becomes
  `Bitwise.bor(a, b)` — which requires no import.

  Companion to `FixErlangBitwiseBif`, which handles the *undefined function*
  variant (where Bitwise *is* imported but the deprecated operator form is
  rejected) and the Erlang BIF style (`band`, `bor`, …).
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @bitwise_infix_ops [:"|||", :"&&&", :"<<<", :">>>", :"~~~", :"^^^"]

  @op_to_fn %{
    :"|||" => :bor,
    :"&&&" => :band,
    :"<<<" => :bsl,
    :">>>" => :bsr,
    :"~~~" => :bnot,
    :"^^^" => :bxor
  }

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, "syntax error") and
      Enum.any?(~w(||| &&& <<< >>> ~~~ ^^^), &String.contains?(msg, &1))
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    op = extract_operator(diagnostic.message)

    %Issue{
      rule: :fix_bitwise_infix_operator,
      message: "bare Bitwise infix operator #{op} without import; use Bitwise module functions instead",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          {op, _meta, args} when op in @bitwise_infix_ops and is_list(args) ->
            fn_name = Map.fetch!(@op_to_fn, op)
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

  defp extract_operator(msg) do
    Enum.find(~w(||| &&& <<< >>> ~~~ ^^^), "?", &String.contains?(msg, &1))
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
