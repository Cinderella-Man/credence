defmodule Credence.Pattern.NoSortThenReverse do
  @moduledoc """
  Performance & readability rule: Detects the pattern of calling `Enum.sort/1,2`
  followed by `Enum.reverse/1` on the result, where the sort direction can be
  statically determined.

  Sorting ascending then reversing is equivalent to `Enum.sort(list, :desc)`
  but wastes a full O(n) pass for the reversal.

  ## Recognised direction forms

      Enum.sort(nums)                        # default :asc
      Enum.sort(nums, :asc)                  # explicit atom
      Enum.sort(nums, :desc)                 # explicit atom
      Enum.sort(nums, &>=/2)                 # capture → :desc
      Enum.sort(nums, &<=/2)                 # capture → :asc
      Enum.sort(nums, fn a, b -> a > b end)  # anonymous comparator → :desc
      Enum.sort(nums, fn a, b -> b > a end)  # flipped comparator  → :asc

  ## Not flagged

  Unresolvable directions such as `Enum.sort(nums, dir) |> Enum.reverse()` or
  opaque comparators like `Enum.sort(nums, &MyModule.compare/2) |> Enum.reverse()`
  are not flagged because we cannot determine the flipped direction.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline form: ... |> Enum.sort(...) |> Enum.reverse()
        {:|>, meta, [left, right]} = node, issues ->
          sort_node = rightmost(left)
          context = if match?({:|>, _, _}, left), do: :pipe, else: :direct

          if remote_call?(right, :Enum, :reverse) and
               remote_call?(sort_node, :Enum, :sort) and
               resolvable_direction?(call_args(sort_node), context) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Nested call form: Enum.reverse(Enum.sort(...))
        {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, meta,
         [{{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, sort_args}]} = node,
        issues ->
          if resolvable_direction?(sort_args, :direct) do
            {node, [build_issue(meta) | issues]}
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
    |> Macro.prewalk(fn
      # Pipeline: ... |> Enum.sort(...) |> Enum.reverse()
      {:|>, pipe_meta, [left, reverse_node]} = node ->
        if remote_call?(reverse_node, :Enum, :reverse) do
          fix_pipeline(left, pipe_meta, node)
        else
          node
        end

      # Nested: Enum.reverse(Enum.sort(...))
      {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [sort_node]} = node ->
        if remote_call?(sort_node, :Enum, :sort) do
          fix_nested_sort(sort_node, node)
        else
          node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  end

  # ── Pipeline fix helpers ──────────────────────────────────────────────

  # Multi-step pipe: before |> Enum.sort() |> Enum.reverse()
  defp fix_pipeline({:|>, _, [before_sort, sort_node]}, pipe_meta, fallback) do
    if remote_call?(sort_node, :Enum, :sort) do
      args = call_args(sort_node) |> normalize_args()

      if fixable_pipe_args?(args) do
        {:|>, pipe_meta, [before_sort, build_sort_call(pipe_flip_args(args))]}
      else
        fallback
      end
    else
      fallback
    end
  end

  # Direct call piped to reverse: Enum.sort(x) |> Enum.reverse()
  defp fix_pipeline(sort_node, _pipe_meta, fallback) do
    if remote_call?(sort_node, :Enum, :sort) do
      args = call_args(sort_node) |> normalize_args()

      if fixable_direct_args?(args) do
        build_sort_call(direct_flip_args(args))
      else
        fallback
      end
    else
      fallback
    end
  end

  # Nested: Enum.reverse(Enum.sort(...))
  defp fix_nested_sort(sort_node, fallback) do
    args = call_args(sort_node) |> normalize_args()

    if fixable_direct_args?(args) do
      build_sort_call(direct_flip_args(args))
    else
      fallback
    end
  end

  # ── Sourceror AST normalization ───────────────────────────────────────

  # Sourceror wraps literal atoms (and other literals) in
  # {:__block__, meta, [value]} nodes to preserve source metadata.
  # Unwrap them so our pattern-matching helpers see plain atoms.
  defp normalize_args(args), do: Enum.map(args, &normalize_arg/1)

  defp normalize_arg({:__block__, _, [literal]}) when is_atom(literal), do: literal
  defp normalize_arg(other), do: other

  # ── Argument classification & transformation ──────────────────────────

  # Pipe context: no subject (pipe provides it), only sort direction
  defp fixable_pipe_args?(args), do: pipe_sort_direction(args) != :unknown

  defp pipe_flip_args(args) do
    case pipe_sort_direction(args) do
      :asc -> [:desc]
      :desc -> []
    end
  end

  # Direct context: first arg is the subject
  defp fixable_direct_args?(args), do: direct_sort_direction(args) != :unknown

  defp direct_flip_args(args) do
    subject = hd(args)

    case direct_sort_direction(args) do
      :asc -> [subject, :desc]
      :desc -> [subject]
    end
  end

  # ── Direction resolution ─────────────────────────────────────────────

  # Used by check/2 — works on raw (non-normalized) sort args
  defp resolvable_direction?(sort_args, context) do
    normalized = normalize_args(sort_args)

    case context do
      :pipe -> pipe_sort_direction(normalized) != :unknown
      :direct -> direct_sort_direction(normalized) != :unknown
    end
  end

  # Pipe args (no subject)
  defp pipe_sort_direction([]), do: :asc
  defp pipe_sort_direction([:asc]), do: :asc
  defp pipe_sort_direction([:desc]), do: :desc
  defp pipe_sort_direction([comparator]), do: resolve_comparator(comparator)
  defp pipe_sort_direction(_), do: :unknown

  # Direct args (first is subject)
  defp direct_sort_direction([_subject]), do: :asc
  defp direct_sort_direction([_subject, :asc]), do: :asc
  defp direct_sort_direction([_subject, :desc]), do: :desc
  defp direct_sort_direction([_subject, comparator]), do: resolve_comparator(comparator)
  defp direct_sort_direction(_), do: :unknown

  # Function captures: &>=/2, &>/2 → :desc; &<=/2, &</2 → :asc
  defp resolve_comparator({:&, _, [{:/, _, [{op, _, _}, 2]}]})
       when op in [:>=, :>],
       do: :desc

  defp resolve_comparator({:&, _, [{:/, _, [{op, _, _}, 2]}]})
       when op in [:<=, :<],
       do: :asc

  defp resolve_comparator({:&, _, [{:/, _, [{op, _, _}, {:__block__, _, [2]}]}]})
       when op in [:>=, :>],
       do: :desc

  defp resolve_comparator({:&, _, [{:/, _, [{op, _, _}, {:__block__, _, [2]}]}]})
       when op in [:<=, :<],
       do: :asc

  # Anonymous comparators: fn a, b -> a OP b end
  defp resolve_comparator({:fn, _, [{:->, _, [[p1, p2], {op, _, [left, right]}]}]})
       when op in [:>, :>=] do
    cond do
      same_var?(p1, left) and same_var?(p2, right) -> :desc
      same_var?(p2, left) and same_var?(p1, right) -> :asc
      true -> :unknown
    end
  end

  defp resolve_comparator({:fn, _, [{:->, _, [[p1, p2], {op, _, [left, right]}]}]})
       when op in [:<, :<=] do
    cond do
      same_var?(p1, left) and same_var?(p2, right) -> :asc
      same_var?(p2, left) and same_var?(p1, right) -> :desc
      true -> :unknown
    end
  end

  defp resolve_comparator(_), do: :unknown

  defp same_var?({name, _, _}, {name, _, _}) when is_atom(name), do: true
  defp same_var?(_, _), do: false

  # ── AST builders & utilities ──────────────────────────────────────────

  defp build_sort_call(args) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :sort]}, [], args}
  end

  defp call_args({{:., _, _}, _, args}), do: args
  defp call_args(_), do: []

  defp rightmost({:|>, _, [_, right]}), do: right
  defp rightmost(other), do: other

  defp remote_call?(node, mod, func) do
    match?({{:., _, [{:__aliases__, _, [^mod]}, ^func]}, _, _}, node)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_sort_then_reverse,
      message:
        "Avoid `Enum.sort/1` followed by `Enum.reverse/1`. " <>
          "Use `Enum.sort(list, :desc)` instead to sort in descending order in a single pass.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
