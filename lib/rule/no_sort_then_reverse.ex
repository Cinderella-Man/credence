defmodule Credence.Rule.NoSortThenReverse do
  @moduledoc """
  Performance & readability rule: Detects the pattern of calling `Enum.sort/1,2`
  followed by `Enum.reverse/1` on the result.

  Sorting ascending then reversing is equivalent to `Enum.sort(list, :desc)`
  but wastes a full O(n) pass for the reversal.

  This rule can automatically fix pipeline and nested-call patterns where the
  sort uses a simple direction (`:asc`, `:desc`, or default ascending). Sorts
  with a custom comparator function are detected but left for manual fixing.

  ## Bad

      # In a pipeline
      nums |> Enum.sort() |> Enum.reverse()

      # As a nested call
      Enum.reverse(Enum.sort(nums))

  ## Good

      nums |> Enum.sort(:desc)
      Enum.sort(nums, :desc)
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline form: ... |> Enum.sort(...) |> Enum.reverse()
        {:|>, meta, [left, right]} = node, issues ->
          if remote_call?(right, :Enum, :reverse) and
               remote_call?(rightmost(left), :Enum, :sort) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Nested call form: Enum.reverse(Enum.sort(...))
        {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, meta,
         [{{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, _}]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

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
  defp fixable_pipe_args?([]), do: true
  defp fixable_pipe_args?([:asc]), do: true
  defp fixable_pipe_args?([:desc]), do: true
  defp fixable_pipe_args?(_), do: false

  defp pipe_flip_args([]), do: [:desc]
  defp pipe_flip_args([:asc]), do: [:desc]
  defp pipe_flip_args([:desc]), do: []

  # Direct context: first arg is the subject
  defp fixable_direct_args?([_subject]), do: true
  defp fixable_direct_args?([_subject, :asc]), do: true
  defp fixable_direct_args?([_subject, :desc]), do: true
  defp fixable_direct_args?(_), do: false

  defp direct_flip_args([subject]), do: [subject, :desc]
  defp direct_flip_args([subject, :asc]), do: [subject, :desc]
  defp direct_flip_args([subject, :desc]), do: [subject]

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
