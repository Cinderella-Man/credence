defmodule Credence.Pattern.FixEtsOptionsBareKeypos do
  @moduledoc """
  Wraps a flattened `:keypos, n` in an `:ets.new/2` option list into `{:keypos, n}`.

  `:ets.new/2`'s option list mixes bare atoms (`:set`, `:named_table`) with
  two-element tuples (`{:keypos, 2}`, `{:read_concurrency, true}`). Writing the
  tupled ones flat is an easy slip, and it raises — executed, not read off the
  docs:

      :ets.new(:t, [:set, :keypos, 2])     # ** (ArgumentError)
      :ets.new(:t, [:set, {:keypos, 2}])   # #Reference<...>

  Like its sibling `FixEtsNewStringName`, nothing catches this until runtime: the
  module compiles and dies the first time the table is created.

  ## Scope

  Only `:keypos` immediately followed by an integer literal. The other tupled
  options take booleans or terms where a flattened pair is far less obviously a
  mistake, and `:keypos` is the one that shows up — it is the option people
  reach for when a record's key is not in position 1.

  ## Equivalence

  A repair, not a behaviour change: the before raises for every table, every
  key and every caller, so there is no input on which it returns a value the
  rewrite could disagree with.

  ## Bad

      defmodule TableFEOBK do
        def start, do: :ets.new(:records, [:set, :keypos, 2])
      end

  ## Good

      defmodule TableFEOBK do
        def start, do: :ets.new(:records, [:set, {:keypos, 2}])
      end
  """
  use Credence.Pattern.Rule

  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case bare_keypos(node) do
          {:ok, meta} -> {node, [build_issue(meta) | acc]}
          :error -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, &fix_node/1)
  end

  defp bare_keypos({{:., _, [{:__block__, _, [:ets]}, :new]}, meta, [_name, opts]}) do
    if flattened?(opts), do: {:ok, meta}, else: :error
  end

  defp bare_keypos(_node), do: :error

  defp fix_node({{:., _, [{:__block__, _, [:ets]}, :new]} = target, meta, [name, opts]} = node) do
    if flattened?(opts), do: {target, meta, [name, rewrap(opts)]}, else: node
  end

  defp fix_node(node), do: node

  # `[..., :keypos, 2, ...]` — the atom and the integer as separate elements.
  defp flattened?({:__block__, _, [elements]}) when is_list(elements),
    do: pairs(elements) != []

  defp flattened?(_opts), do: false

  defp pairs(elements) do
    elements
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn
      [{:__block__, _, [:keypos]}, {:__block__, _, [n]}] when is_integer(n) -> true
      _ -> false
    end)
  end

  # Rebuild the list with each `:keypos, n` pair collapsed into one tuple node.
  # Walking with an explicit accumulator rather than `Enum.chunk_every/4`: the
  # pair has to be CONSUMED, and a chunking pass would leave the integer behind
  # as its own element on the next window.
  defp rewrap({:__block__, list_meta, [elements]}) do
    {:__block__, list_meta, [collapse(elements)]}
  end

  defp collapse([
         {:__block__, kp_meta, [:keypos]} = key,
         {:__block__, _, [n]} = value | rest
       ])
       when is_integer(n) do
    tuple = {:{}, Keyword.take(kp_meta, [:line, :column]), [key, value]}
    [tuple | collapse(rest)]
  end

  defp collapse([element | rest]), do: [element | collapse(rest)]
  defp collapse([]), do: []

  defp build_issue(meta) do
    %Issue{
      rule: :fix_ets_options_bare_keypos,
      message:
        "`:ets.new/2` takes `{:keypos, n}` as a tuple. A flattened `:keypos, n` in " <>
          "the option list raises ArgumentError.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  # Rewrites a literal option list passed to one erlang call. No macro DSL
  # reinterprets `:ets.new/2` or list literals inside it.
  @impl true
  def unsafe_in_dsl, do: []
end
