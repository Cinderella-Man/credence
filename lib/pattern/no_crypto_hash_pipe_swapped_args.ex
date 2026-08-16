defmodule Credence.Pattern.NoCryptoHashPipeSwappedArgs do
  @moduledoc """
  Detects data piped into `:crypto.hash/2` and rewrites the pipe into a direct
  call whose arguments are in the order `:crypto.hash/2` actually takes.

  ## Why this matters

  LLMs frequently write:

      path
      |> File.read!()
      |> :crypto.hash(:sha256)

  The pipe operator inserts the piped value as the **first** argument, so that
  is `:crypto.hash(contents, :sha256)` — the file contents land in the
  algorithm position and the algorithm atom lands in the data position.
  `:crypto.hash/2` takes `(algorithm, data)`, so this raises `ArgumentError`
  at runtime.

  ## Why the rewrite is a repair

  The piped form crashes on every input: the first argument is not a hash
  algorithm and the second is not an iodata term, so there is no runtime
  behaviour to preserve. The direct call computes the digest the author meant.

  ## Why this rule lives in the Pattern phase

  The failure is a **runtime** `ArgumentError`, so the compiler emits nothing
  for the shape this rule repairs — a call in a `def` body is never evaluated
  at compile time. This rule shipped in `Credence.Semantic` keyed on the
  runtime message and therefore could not fire at all; the T1 pipeline-witness
  gate proved it. The offending shape is visible in the AST alone, which is
  the Pattern phase's input by definition.

  ## Flagged patterns

      data |> :crypto.hash(:sha256)

  ## Not flagged

      :crypto.hash(:sha256, data)         — already the correct argument order
      data |> :crypto.hash(:sha256, salt) — not the one-argument pipe shape
      data |> :crypto.hash(algo)          — algorithm is a variable, not a literal

  ## Bad

      defmodule AnchoredNCHPSA do
        def hash_file(path) do
          path
          |> File.read!()
          |> :crypto.hash(:sha256)
        end
      end

  ## Good

      defmodule AnchoredNCHPSA do
        def hash_file(path) do
          :crypto.hash(
            :sha256,
            path
            |> File.read!()
          )
        end
      end
  """

  use Credence.Pattern.Rule

  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case node do
          {:|>, _pipe_meta, [_left, right]} ->
            case algorithm_only_call(right) do
              {:ok, meta} -> {node, [build_issue(meta) | issues]}
              :error -> {node, issues}
            end

          _ ->
            {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    Credence.RuleHelpers.patches_from_ast_transform(
      ast,
      Keyword.fetch!(opts, :source),
      &swap_piped_calls/1
    )
  end

  # The scope predicate `check/2` and `fix_patches/2` share: a `:crypto.hash`
  # call carrying exactly one argument, an atom literal in the algorithm
  # position. Returns the call's meta so the issue can be anchored to it.
  defp algorithm_only_call(
         {{:., _dot_meta, [{:__block__, _crypto_meta, [:crypto]}, :hash]}, call_meta,
          [{:__block__, _algo_meta, [algo_atom]}]}
       )
       when is_atom(algo_atom) do
    {:ok, call_meta}
  end

  defp algorithm_only_call(_), do: :error

  defp swap_piped_calls(ast) do
    Macro.prewalk(ast, fn
      {:|>, _pipe_meta, [left, right]} = node ->
        case algorithm_only_call(right) do
          {:ok, _meta} -> direct_call(right, left)
          :error -> node
        end

      node ->
        node
    end)
  end

  # `:crypto.hash(algo)` + the piped value becomes `:crypto.hash(algo, value)`,
  # reusing the original call's metadata so the range lookup lands on it.
  defp direct_call(
         {{:., dot_meta, [{:__block__, crypto_meta, [:crypto]}, :hash]}, call_meta, [algo_node]},
         piped_value
       ) do
    {{:., dot_meta, [{:__block__, crypto_meta, [:crypto]}, :hash]}, call_meta,
     [algo_node, piped_value]}
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_crypto_hash_pipe_swapped_args,
      message: message(),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp message do
    "piping into :crypto.hash/2 puts the data in the algorithm position — " <>
      "this raises ArgumentError at runtime; call :crypto.hash(algorithm, data) directly"
  end

  # Rule Standard item 5 (docs/19), decided deliberately: the rewrite moves a
  # piped value into an argument position and introduces no comparison, boolean,
  # control-flow or nil form. `|>` is not a construct Ash.Expr, Ecto.Query or
  # Nx.Defn reinterprets, and `:crypto.hash/2` is an Erlang call none of the
  # three families give a second meaning to.
  @impl true
  def unsafe_in_dsl, do: []
end
