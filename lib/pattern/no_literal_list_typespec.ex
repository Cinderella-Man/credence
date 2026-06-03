defmodule Credence.Pattern.NoLiteralListTypespec do
  @moduledoc """
  Correctness rule: Detects a multi-element **literal list** used as an
  `@spec` return type — e.g. `[pos_integer(), pos_integer()]`. This is not
  valid Elixir: in a typespec `[type]` means "a list of `type`", and a list
  with two or more comma-separated element types raises
  `Kernel.TypespecError` at compile time. LLMs translating fixed-size return
  values from other languages (a Python tuple, say) emit this shape.

  The fix converts the literal list to a **tuple**, the idiomatic way to
  express a fixed-size heterogeneous type. A `@spec` has no runtime effect and
  the original does not compile, so the rewrite only ever touches already-broken
  specs.

  ## Scope (deliberately narrow)

  Only fires when **every** element is a plain type call (`pos_integer()`,
  `atom()`, `String.t()`, `list(integer())`, …). It does **not** touch:

    * keyword-list types (`[ok: integer(), error: atom()]`) — those are valid;
    * non-empty list types (`[type, ...]`) — also valid;
    * literal-atom lists (`[:ok, :error]`) — ambiguous (likely a `:ok | :error`
      union, not a tuple), so left for a human;
    * single-element list types (`[type]`) — valid.

  ## Bad

      @spec foo(integer()) :: [pos_integer(), pos_integer()]

  ## Good

      @spec foo(integer()) :: {pos_integer(), pos_integer()}
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:@, _, [{:spec, spec_meta, [{:"::", _, [_lhs, rhs]}]}]} = node, acc ->
          case fixable_list(rhs) do
            {:ok, _elements} -> {node, [build_issue(spec_meta) | acc]}
            :no -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:@, attr_meta, [{:spec, spec_meta, [{:"::", colon_meta, [lhs, rhs]}]}]} = node ->
        case fixable_list(rhs) do
          {:ok, elements} ->
            {:@, attr_meta, [{:spec, spec_meta, [{:"::", colon_meta, [lhs, to_tuple(elements)]}]}]}

          :no ->
            node
        end

      node ->
        node
    end)
  end

  # A return type fixable by this rule: a Sourceror-wrapped list literal with
  # two or more elements, every one of which is a plain type call.
  defp fixable_list({:__block__, _, [elements]})
       when is_list(elements) and length(elements) >= 2 do
    if Enum.all?(elements, &type_call?/1), do: {:ok, elements}, else: :no
  end

  defp fixable_list(_), do: :no

  # Plain type calls only: `atom()`, `pos_integer()`, `list(integer())`,
  # `String.t()`. Excludes `...`, literal blocks (`:ok`, `1`), keyword pairs
  # (`k: v` → bare 2-tuple), and tuple literals.
  defp type_call?({name, meta, args})
       when is_atom(name) and is_list(meta) and is_list(args),
       do: name not in [:..., :__block__]

  defp type_call?({{:., _, _}, meta, args}) when is_list(meta) and is_list(args), do: true

  defp type_call?(_), do: false

  defp to_tuple([a, b]), do: {a, b}
  defp to_tuple(elements), do: {:{}, [], elements}

  defp build_issue(meta) do
    %Issue{
      rule: :no_literal_list_typespec,
      message:
        "Multi-element literal list `[type, type]` in an `@spec` return type is invalid " <>
          "Elixir (raises `TypespecError`). Use a tuple `{type, type}` for a fixed-size type.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
