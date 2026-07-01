defmodule Credence.Pattern.HallucinatedGuard do
  @moduledoc """
  Fixes calls to guard functions that don't exist in Elixir.

  LLMs sometimes hallucinate guard names from Erlang typespecs or other
  languages. This rule detects known hallucinated guards and replaces
  them with their correct Elixir equivalents.

  ## Replacements

      is_pos_integer(x)      →  is_integer(x) and x > 0
      is_non_neg_integer(x)  →  is_integer(x) and x >= 0
      is_neg_integer(x)      →  is_integer(x) and x < 0
      is_non_pos_integer(x)  →  is_integer(x) and x <= 0
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @hallucinated_guards %{
    is_pos_integer: {:>, 0},
    is_non_neg_integer: {:>=, 0},
    is_neg_integer: {:<, 0},
    is_non_pos_integer: {:<=, 0}
  }

  @guard_names Map.keys(@hallucinated_guards)

  @impl true
  def check(ast, _opts) do
    active =
      if imports_or_uses?(ast),
        do: [],
        else: @guard_names -- defined_guards(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {name, meta, [_arg]} = node, issues when is_atom(name) ->
          if name in active do
            {node, [build_issue(name, meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    if imports_or_uses?(ast) do
      []
    else
      do_fix(ast)
    end
  end

  defp do_fix(ast) do
    defined = defined_guards(ast)

    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {name, _, [arg]} = node when is_atom(name) ->
        case Map.get(@hallucinated_guards, name) do
          {op, bound} ->
            if name in defined do
              node
            else
              {:and, [], [{:is_integer, [], [arg]}, {op, [], [arg, bound]}]}
            end

          nil ->
            node
        end

      node ->
        node
    end)
  end

  # A module that `import`s or `use`s another module may bring these guard names
  # into scope as REAL custom guards (e.g. `import MyApp.Guards` defining
  # `is_pos_integer/1`). We can't resolve the other module's definitions, and an
  # unqualified guard call that compiles must be locally defined OR imported — so
  # if any `import`/`use` is present, do not treat these names as hallucinated
  # (unrolling an imported guard, possibly to a divergent definition, is unsafe).
  defp imports_or_uses?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        _node, true -> {nil, true}
        {directive, _, [_ | _]} = node, _ when directive in [:import, :use] -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # Names from `@guard_names` that the module DEFINES as a guard via
  # `defguard`/`defguardp` at arity 1. A defined guard is not hallucinated — it
  # exists — so it must be left untouched everywhere: rewriting it would corrupt
  # the definition head (`defguardp is_pos_integer(x) when ...` → invalid) and
  # needlessly unroll the user's own abstraction at its call sites.
  defp defined_guards(ast) do
    {_ast, defined} =
      Macro.prewalk(ast, [], fn
        {dg, _, [head | _]} = node, acc when dg in [:defguard, :defguardp] ->
          case guard_head(head) do
            {name, 1} -> {node, [name | acc]}
            _ -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.filter(@guard_names, &(&1 in defined))
  end

  # The `name/arity` a `defguard(p)` head defines, stripping the `when` guard.
  defp guard_head({:when, _, [call, _guard]}), do: guard_head(call)
  defp guard_head({name, _, args}) when is_atom(name) and is_list(args), do: {name, length(args)}
  defp guard_head(_), do: nil

  defp build_issue(name, meta) do
    %Issue{
      rule: :hallucinated_guard,
      message:
        "`#{name}/1` does not exist in Elixir. " <>
          "Replace with the equivalent guard expression.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
