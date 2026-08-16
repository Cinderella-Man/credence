defmodule Credence.Pattern.NoHallucinatedEtsKeytypeOption do
  @moduledoc """
  Removes the hallucinated `keytype: :term` option from `:ets.new/2` calls.

  ## Why this matters

  LLMs translating Python dict key types frequently hallucinate `keytype:
  :term` as an option to `:ets.new/2`. No such option exists in Erlang's ETS,
  and the call raises `ArgumentError` at runtime:

      errors were found at the given arguments:

        * 2nd argument: invalid options

  ## Why the rewrite is a repair

  `:ets.new/2` rejects the whole option list, so the call crashes on every
  input and there is no runtime behaviour to preserve. Dropping the invented
  pair leaves the remaining options — all of them real — and the table is
  created as the author intended.

  ## Why this rule lives in the Pattern phase

  The failure is a **runtime** `ArgumentError`, so the compiler emits nothing
  for the shape this rule repairs — a call in a `def` body is never evaluated
  at compile time. This rule shipped in `Credence.Semantic` keyed on the
  runtime message and therefore could not fire at all; the T1 pipeline-witness
  gate proved it. The invented option is visible in the AST alone, which is
  the Pattern phase's input by definition.

  ## Flagged patterns

      :ets.new(:table, [:set, keytype: :term, read_concurrency: true])

  ## Not flagged

      :ets.new(:table, [:set, keytype: :bag])   — a different value; out of scope
      :ets.new(:table, [:set, {:keytype, :term}]) — tuple form; out of scope
      :ets.new(:table, opts)                    — options are not a literal list

  ## Bad

      defmodule AnchoredNHEKO do
        def create do
          :ets.new(:test, [:set, keytype: :term])
        end
      end

  ## Good

      defmodule AnchoredNHEKO do
        def create do
          :ets.new(:test, [:set])
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
          {{:., _dot_meta, [{:__block__, _, [:ets]}, :new]}, call_meta, args} ->
            case remove_keytype_from_args(args) do
              {:ok, _new_args} -> {node, [build_issue(call_meta) | issues]}
              :error -> {node, issues}
            end

          _ ->
            {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  # Patches are emitted directly rather than through
  # `RuleHelpers.patches_from_ast_transform/3`, and the reason is a byte: the
  # options list is a bare list wrapped in `{:__block__, meta, [list]}`, and only
  # the *wrapper* carries the bracket positions (`column` on `[`, `closing` on
  # `]`). The AST differ recurses past the wrapper and lands on the bare list,
  # whose range starts one column later — inside the `[` — while
  # `Sourceror.to_string/1` renders the replacement *with* its brackets. Applying
  # that patch produced `:ets.new(:a, [[:set, keypos: 2]])`. Patching at the
  # wrapper's range keeps the two bracket-inclusive.
  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, patches ->
        case node do
          {{:., _dot_meta, [{:__block__, _, [:ets]}, :new]}, _call_meta, args} ->
            case options_patch(args) do
              {:ok, patch} -> {node, [patch | patches]}
              :error -> {node, patches}
            end

          _ ->
            {node, patches}
        end
      end)

    Enum.reverse(patches)
  end

  defp options_patch(args) when is_list(args) do
    with {:ok, new_args} <- remove_keytype_from_args(args),
         wrapper <- List.last(args),
         new_wrapper <- List.last(new_args),
         range when not is_nil(range) <- Sourceror.get_range(wrapper) do
      {:ok, %{range: range, change: Sourceror.to_string(new_wrapper)}}
    else
      _ -> :error
    end
  end

  defp options_patch(_), do: :error

  # The scope predicate `check/2` and `fix_patches/2` share. The options list is
  # the last argument, wrapped by Sourceror in a `:__block__`.
  defp remove_keytype_from_args(args) when is_list(args) do
    case List.last(args) do
      {:__block__, meta, [opts]} when is_list(opts) ->
        case do_remove_keytype(opts) do
          {:ok, new_opts} ->
            new_last = {:__block__, meta, [new_opts]}
            {:ok, List.replace_at(args, length(args) - 1, new_last)}

          :error ->
            :error
        end

      _ ->
        :error
    end
  end

  defp remove_keytype_from_args(_), do: :error

  defp do_remove_keytype(opts) when is_list(opts) do
    case Enum.find_index(opts, &keytype_option?/1) do
      nil -> :error
      idx -> {:ok, List.delete_at(opts, idx)}
    end
  end

  # Match a keyword pair written as `keytype: :term`. The `:format` marker is
  # what distinguishes it from the `{:keytype, :term}` tuple form, which this
  # rule deliberately leaves alone.
  defp keytype_option?({{:__block__, meta, [:keytype]}, {:__block__, _, [:term]}})
       when is_list(meta) do
    Keyword.get(meta, :format) == :keyword
  end

  defp keytype_option?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_hallucinated_ets_keytype_option,
      message: message(),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp message do
    "`keytype: :term` is not an :ets.new/2 option — the call raises " <>
      "ArgumentError at runtime; remove the invented pair"
  end

  # Rule Standard item 5 (docs/19), decided deliberately: the rewrite deletes one
  # keyword pair from a literal option list passed to an Erlang call. It
  # introduces and removes no comparison, boolean, control-flow or nil form, and
  # `:ets.new/2` is not a construct Ash.Expr, Ecto.Query or Nx.Defn reinterprets.
  @impl true
  def unsafe_in_dsl, do: []
end
