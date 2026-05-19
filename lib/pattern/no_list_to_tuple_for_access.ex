defmodule Credence.Pattern.NoListToTupleForAccess do
  @moduledoc """
  Performance & style rule: Detects converting a list to a tuple via
  `List.to_tuple/1` and then accessing elements with `elem/2`.
  Tuples are meant for small, fixed-size collections. Copying a
  dynamically-sized list into a tuple just for one-shot indexed access
  defeats the purpose and allocates a full copy of the data. Use pattern
  matching (`[a, b | _] = list`) or `Enum.at/2` on the list directly instead.
  For string processing, use `binary_part/3` or binary pattern matching.

  ## Bad

      t = List.to_tuple(graphemes)
      first = elem(t, 0)
      last = elem(t, tuple_size(t) - 1)

  ## Good

      [first | _] = graphemes
      last = List.last(graphemes)
      # Or for indexed access on strings:
      <<first::utf8, _rest::binary>> = string

  ## Loop-scope exemption

  The pattern `t = List.to_tuple(list)` outside a loop, followed by
  `elem(t, i)` *inside* `Enum.reduce`/`Enum.map`/`fn`/`for`/... is the
  canonical Elixir idiom for O(1) random access during iteration.
  Rewriting that `elem` to `Enum.at` would turn O(m + n) into O(m × n).
  The rule recognises this shape and refuses to flag (or auto-fix) it.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  # ── Check ─────────────────────────────────────────────────────────

  @impl true
  def check(ast, _opts) do
    bindings = collect_bindings(ast)

    if map_size(bindings) == 0 do
      []
    else
      readers = collect_elem_readers(ast, bindings)

      Enum.flat_map(bindings, fn {var, _info} ->
        case Map.get(readers, var, []) do
          [] ->
            []

          var_readers ->
            if Enum.any?(var_readers, & &1.in_loop?) do
              # All-or-some-in-loop: the pattern is the recommended idiom
              # for O(1) random access during iteration. Don't nag.
              []
            else
              [build_issue(var, hd(var_readers).node)]
            end
        end
      end)
    end
  end

  # ── Fix ───────────────────────────────────────────────────────────

  @impl true
  def fix(source, _opts) do
    ast = Sourceror.parse_string!(source)
    bindings = collect_bindings(ast)

    if map_size(bindings) == 0 do
      source
    else
      readers = collect_elem_readers(ast, bindings)
      {elem_patches, removable_bindings} = decide_patches(bindings, readers, ast)

      binding_patches = Enum.map(removable_bindings, &binding_removal_patch/1)
      patches = elem_patches ++ binding_patches

      if patches == [] do
        source
      else
        source
        |> Sourceror.patch_string(patches)
        |> String.trim_trailing("\n")
      end
    end
  end

  # ── Phase 1: collect bindings with scope ──────────────────────────

  defp collect_bindings(ast) do
    {_, {_, bindings}} =
      Macro.traverse(
        ast,
        {[], %{}},
        fn node, {stack, bindings} ->
          bindings = maybe_record_binding(node, stack, bindings)
          {node, {enter_scope(node, stack), bindings}}
        end,
        fn node, {stack, bindings} ->
          {node, {exit_scope(node, stack), bindings}}
        end
      )

    bindings
  end

  defp maybe_record_binding({:=, _, [{var, _, nil}, rhs]} = node, scope, bindings)
       when is_atom(var) do
    case extract_tuple_source(rhs) do
      {:ok, source_expr} ->
        Map.put(bindings, var, %{
          source: Macro.to_string(source_expr),
          node: node,
          scope: scope
        })

      :error ->
        bindings
    end
  end

  defp maybe_record_binding(_, _, bindings), do: bindings

  # ── Phase 2: collect elem readers with scope ──────────────────────

  defp collect_elem_readers(ast, bindings) do
    {_, {_, readers}} =
      Macro.traverse(
        ast,
        {[], %{}},
        fn node, {stack, readers} ->
          readers = maybe_record_elem(node, stack, bindings, readers)
          {node, {enter_scope(node, stack), readers}}
        end,
        fn node, {stack, readers} ->
          {node, {exit_scope(node, stack), readers}}
        end
      )

    readers
  end

  defp maybe_record_elem({:elem, _, [{var, _, nil}, idx]} = node, scope, bindings, readers)
       when is_atom(var) do
    case Map.get(bindings, var) do
      nil ->
        readers

      %{scope: binding_scope} ->
        entry = %{
          node: node,
          idx: idx,
          in_loop?: in_loop_relative_to_binding?(scope, binding_scope)
        }

        Map.update(readers, var, [entry], &(&1 ++ [entry]))
    end
  end

  defp maybe_record_elem(_, _, _, readers), do: readers

  # ── Phase 3: decide what to patch ─────────────────────────────────

  defp decide_patches(bindings, readers, ast) do
    Enum.reduce(bindings, {[], []}, fn {var, binding_info}, {patches, removable} ->
      var_readers = Map.get(readers, var, [])

      cond do
        var_readers == [] ->
          {patches, removable}

        Enum.any?(var_readers, & &1.in_loop?) ->
          # Preserve the in-loop O(1) random-access idiom intact.
          {patches, removable}

        true ->
          new_patches =
            Enum.map(var_readers, fn r ->
              %{
                range: Sourceror.get_range(r.node),
                change: "Enum.at(#{binding_info.source}, #{Macro.to_string(r.idx)})"
              }
            end)

          total = count_var_refs(ast, var)
          # Total refs = binding LHS (1) + each elem first arg (length(readers))
          # + any other reference. So non-elem readers count is:
          non_elem_count = total - 1 - length(var_readers)

          new_removable =
            if non_elem_count == 0 do
              [binding_info.node | removable]
            else
              removable
            end

          {patches ++ new_patches, new_removable}
      end
    end)
  end

  defp count_var_refs(ast, var) do
    {_, count} =
      Macro.prewalk(ast, 0, fn
        {^var, _, nil} = node, acc -> {node, acc + 1}
        node, acc -> {node, acc}
      end)

    count
  end

  defp binding_removal_patch({:=, _, _} = node) do
    range = Sourceror.get_range(node)

    %{
      range: %{
        start: [line: range.start[:line], column: 1],
        end: [line: range.end[:line] + 1, column: 1]
      },
      change: ""
    }
  end

  # ── Loop-scope tracking ───────────────────────────────────────────

  # Stack entries identify a `:fn` or `:for` ancestor by its source
  # position so two siblings with the same shape don't collide.
  defp enter_scope({:fn, meta, _}, stack), do: [{:fn, meta_id(meta)} | stack]
  defp enter_scope({:for, meta, _}, stack), do: [{:for, meta_id(meta)} | stack]
  defp enter_scope(_, stack), do: stack

  defp exit_scope({:fn, _, _}, [_ | rest]), do: rest
  defp exit_scope({:for, _, _}, [_ | rest]), do: rest
  defp exit_scope(_, stack), do: stack

  defp meta_id(meta), do: {Keyword.get(meta, :line), Keyword.get(meta, :column)}

  # A reader is "in a loop relative to its binding" iff it sits inside
  # at least one `:fn`/`:for` that was opened *after* the binding —
  # i.e., the binding's scope path is a strict suffix of the reader's.
  defp in_loop_relative_to_binding?(reader_scope, binding_scope) do
    blen = length(binding_scope)
    rlen = length(reader_scope)

    rlen > blen and Enum.drop(reader_scope, rlen - blen) == binding_scope
  end

  # ── List.to_tuple source extraction ───────────────────────────────

  defp extract_tuple_source({{:., _, [{:__aliases__, _, [:List]}, :to_tuple]}, _, [source]}),
    do: {:ok, source}

  defp extract_tuple_source(
         {:|>, _, [source, {{:., _, [{:__aliases__, _, [:List]}, :to_tuple]}, _, _}]}
       ),
       do: {:ok, source}

  defp extract_tuple_source(_), do: :error

  # ── Issue construction ────────────────────────────────────────────

  defp build_issue(var, {:elem, meta, _}) do
    %Issue{
      rule: :no_list_to_tuple_for_access,
      message:
        "`#{var}` is created with `List.to_tuple/1` and then accessed with `elem/2`. " <>
          "Avoid copying a dynamic list into a tuple for one-shot indexed access. " <>
          "Use pattern matching or `Enum.at/2` on the list directly.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
