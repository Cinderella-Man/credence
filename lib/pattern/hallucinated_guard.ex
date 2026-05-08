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

  @guard_names Map.keys(@hallucinated_guards) |> MapSet.new()

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {name, meta, [_arg]} = node, issues when is_atom(name) ->
          if name in @guard_names do
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
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      {name, _, [arg]} = node when is_atom(name) ->
        case Map.get(@hallucinated_guards, name) do
          {op, bound} ->
            {:and, [], [{:is_integer, [], [arg]}, {op, [], [arg, bound]}]}

          nil ->
            node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

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
