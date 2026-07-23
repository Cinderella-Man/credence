defmodule Credence.Semantic.FixErlangBitwiseBif do
  @moduledoc """
  Fixes undefined bare Erlang bitwise BIF calls (band, bor, bsl, bsr, bxor,
  bnot) by prefixing them with `Bitwise.`, and fixes unimported Bitwise infix
  operator forms (|||, &&&, <<<, >>>, ~~~, ^^^) by replacing them with the
  equivalent `Bitwise.xxx()` function calls.

  LLMs frequently write Erlang-style bare bitwise BIF calls or operator forms
  that fail to compile in Elixir with "undefined function" when `Bitwise` is
  not imported. The deterministic fix rewrites the flagged call — e.g.
  `bsl(value, n)` becomes `Bitwise.bsl(value, n)` and `a ||| b` becomes
  `Bitwise.bor(a, b)`. `Bitwise` module calls need no import and stay
  guard-safe, so the rewrite computes the exact same value the author asked
  the Erlang BIF for.

  The rule only claims the exact BIF arities (`band/2`, …, `bnot/1`); a
  wrong-arity call like `bsl/3` has no same-answer rewrite (prefixing would
  merely trade the compile error for a runtime `UndefinedFunctionError`) and
  is left to other rules. The fix is AST-based and restricted to the
  diagnostic's line, so occurrences inside string literals, and same-named
  operators defined or legitimately used elsewhere in the file, are never
  touched. Each call site gets its own compiler diagnostic, so line-scoped
  rewrites still cover every site.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # Diagnostic name → {Bitwise function, required arity}. Keys cover both the
  # bare Erlang-style BIF spellings and the operator spellings that
  # `import Bitwise` would provide.
  @replacements %{
    "band" => {:band, 2},
    "bor" => {:bor, 2},
    "bsl" => {:bsl, 2},
    "bsr" => {:bsr, 2},
    "bxor" => {:bxor, 2},
    "bnot" => {:bnot, 1},
    "|||" => {:bor, 2},
    "&&&" => {:band, 2},
    "<<<" => {:bsl, 2},
    ">>>" => {:bsr, 2},
    "~~~" => {:bnot, 1},
    "^^^" => {:bxor, 2}
  }

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    lookup_replacement(msg) != nil
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg} = diagnostic) do
    {name, arity, fn_name} = lookup_replacement(msg)

    %Issue{
      rule: :fix_erlang_bitwise_bif,
      message: "undefined function #{name}/#{arity}; use Bitwise.#{fn_name} instead",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg} = diagnostic) do
    with {name, _arity, fn_name} <- lookup_replacement(msg),
         line_no when is_integer(line_no) <- line(diagnostic),
         {:ok, ast} <- Sourceror.parse_string(source) do
      target = String.to_atom(name)

      result =
        Macro.prewalk(ast, fn
          {^target, meta, args} = node when is_list(args) ->
            if meta[:line] == line_no do
              {{:., [], [{:__aliases__, [], [:Bitwise]}, fn_name]}, meta, args}
            else
              node
            end

          node ->
            node
        end)

      if result == ast, do: source, else: Sourceror.to_string(result)
    else
      _ -> source
    end
  end

  defp lookup_replacement(msg) do
    with [_, name, arity] <- Regex.run(~r/undefined function ([^\s()]+)\/(\d+)/, msg),
         arity = String.to_integer(arity),
         {fn_name, ^arity} <- Map.get(@replacements, name) do
      {name, arity, fn_name}
    else
      _ -> nil
    end
  end

  defp line(%{position: {line, _col}}) when is_integer(line), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_), do: nil
end
