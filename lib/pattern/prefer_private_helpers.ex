defmodule Credence.Pattern.PreferPrivateHelpers do
  @moduledoc """
  Detects public helper functions (`def`) annotated with `@doc` or `@spec` that
  are only called within their own module, and converts them to private (`defp`).

  Helper functions used only internally should be private to improve
  encapsulation and follow Elixir idiom. Private functions cannot have
  documentation, so the `@doc` is removed; the `@spec` is also removed since
  it serves no purpose on a private function and the compiler warns about it.

  ## Bad

      @doc "Translates a single musical note into its special code."
      @spec translate_note(String.t()) :: String.t()
      def translate_note("C#"), do: "H"
      def translate_note(note), do: note

  ## Good

      defp translate_note("C#"), do: "H"
      defp translate_note(note), do: note
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    case extract_module_body(ast) do
      {:ok, body} ->
        candidates = private_helper_candidates(body)

        Enum.map(candidates, fn {name, arity, line} ->
          %Issue{
            rule: :prefer_private_helpers,
            message:
              "Function `#{name}/#{arity}` is annotated with `@doc` or `@spec` but is only " <>
                "called within its module. Make it private (`defp`) and remove the annotations.",
            meta: %{line: line}
          }
        end)

      :error ->
        []
    end
  end

  @impl true
  def fix_patches(ast, opts) do
    case extract_module_body(ast) do
      {:ok, body} ->
        candidates = private_helper_candidates(body)

        case candidates do
          [] ->
            []

          _ ->
            candidate_names = MapSet.new(candidates, fn {name, _arity, _line} -> name end)
            source = Keyword.get(opts, :source) || Sourceror.to_string(ast)

            RuleHelpers.patches_from_ast_transform(ast, source, fn ast ->
              transform(ast, candidate_names)
            end)
        end

      :error ->
        []
    end
  end

  # ── AST helpers ──────────────────────────────────────────────────────

  defp extract_module_body({:defmodule, _, [_alias, body_kw]}) do
    RuleHelpers.extract_do_body(body_kw)
  end

  defp extract_module_body(_), do: :error

  # ── Detection ────────────────────────────────────────────────────────

  # Returns [{name, arity, line}] for `def` functions that have `@doc` or
  # `@spec` and are only called within the module.
  defp private_helper_candidates(body) do
    stmts = block_to_list(body)

    # Collect all public function definitions that have @doc or @spec.
    defs_with_annotations =
      for {stmt, idx} <- Enum.with_index(stmts),
          {dt, meta, [head, _body_kw]} <- [stmt],
          dt == :def,
          idx > 0,
          prev = Enum.at(stmts, idx - 1),
          annotation?(prev),
          {name, arity} <- [func_name_arity(head)] do
        {name, arity, Keyword.get(meta, :line)}
      end

    Enum.filter(defs_with_annotations, fn {name, arity, _line} ->
      only_used_internally?(body, name, arity)
    end)
  end

  defp annotation?({:@, _, [{:doc, _, _}]}), do: true
  defp annotation?({:@, _, [{:spec, _, _}]}), do: true
  defp annotation?(_), do: false

  defp func_name_arity({:when, _, [head | _]}), do: func_name_arity(head)

  defp func_name_arity({name, _, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}

  defp func_name_arity(_), do: nil

  # Check if `name` is only referenced via direct calls of `expected_arity`
  # or function captures (`&name/arity`) within the module body — never as a
  # bare atom or variable, and never called with a different arity.
  #
  # We walk the module body but explicitly SKIP into the body of `def`/`defp`
  # nodes (not their heads) to avoid counting the definition head as a call.
  defp only_used_internally?(body, name, expected_arity) do
    refs = collect_refs_skipping_def_heads(body, name)
    has_ref? = Enum.any?(refs, &match?({:call, _}, &1) or match?({:capture}, &1))
    has_bare_atom? = Enum.any?(refs, &match?({:bare_atom}, &1))
    has_var? = Enum.any?(refs, &match?({:var}, &1))
    has_diff_arity? = Enum.any?(refs, fn {:call, a} -> a != expected_arity; _ -> false end)

    has_ref? and not has_bare_atom? and not has_var? and not has_diff_arity?
  end

  # Walk the AST collecting references to `name`, but when we encounter a
  # `def`/`defp` node, skip its head and only walk its body. Also skip
  # `@spec`/`@doc` attributes which mention the function name in type
  # annotations but are not actual references.
  defp collect_refs_skipping_def_heads(node, name) do
    case node do
      # @spec/@doc attribute — skip entirely (not a real reference)
      {:@, _, [{attr, _, _}]} when attr in [:spec, :doc] ->
        []

      # def/defp node — skip the head, walk the body only
      {dt, _, [_head, body_kw]} when dt in [:def, :defp] and is_list(body_kw) ->
        body = extract_do(body_kw) || body_kw
        collect_refs_skipping_def_heads(body, name)

      # Function capture &name/arity
      {:&, _, [{:/, _, [{^name, _, _}, _]}]} ->
        [{:capture}]

      # Bare atom reference (:name)
      {:__block__, _, [^name]} ->
        [{:bare_atom}]

      # Call to name
      {^name, _, args} when is_list(args) ->
        [{:call, length(args)}]

      # Variable reference (name with atom context)
      {^name, _, ctx} when is_atom(ctx) ->
        [{:var}]

      # Tuple node — recurse into children
      {_, _, children} when is_list(children) ->
        Enum.flat_map(children, &collect_refs_skipping_def_heads(&1, name))

      # List — recurse into elements
      list when is_list(list) ->
        Enum.flat_map(list, &collect_refs_skipping_def_heads(&1, name))

      # 2-tuple (keyword pair etc.)
      {a, b} ->
        collect_refs_skipping_def_heads(a, name) ++
          collect_refs_skipping_def_heads(b, name)

      # Leaf
      _ ->
        []
    end
  end

  defp extract_do(kw) when is_list(kw) do
    Enum.find_value(kw, fn
      {{:__block__, _, [:do]}, body} -> body
      _ -> nil
    end)
  end

  defp extract_do(_), do: nil

  # ── Transformation ───────────────────────────────────────────────────

  defp transform(ast, candidate_names) do
    Macro.prewalk(ast, fn
      {:__block__, meta, stmts} when is_list(stmts) ->
        {:__block__, meta, transform_statements(stmts, candidate_names)}

      node ->
        node
    end)
  end

  # Walk backwards from `idx`, collecting consecutive @doc/@spec indices.
  defp collect_annotation_indices(stmts, idx, acc) do
    if idx > 0 and annotation?(Enum.at(stmts, idx - 1)) do
      collect_annotation_indices(stmts, idx - 1, MapSet.put(acc, idx - 1))
    else
      acc
    end
  end

  defp transform_statements(stmts, candidate_names) do
    # Indices of candidate def nodes (to convert to defp)
    convert_indices =
      MapSet.new(
        for {stmt, idx} <- Enum.with_index(stmts),
            {dt, _meta, [head, _body_kw]} <- [stmt],
            dt == :def,
            {name, _arity} <- [func_name_arity(head)],
            MapSet.member?(candidate_names, name),
            do: idx
      )

    # Indices of @doc/@spec annotations to remove.
    # Walk backwards from each candidate def, removing consecutive annotations.
    remove_indices =
      Enum.reduce(convert_indices, MapSet.new(), fn idx, remove_set ->
        collect_annotation_indices(stmts, idx, remove_set)
      end)

    stmts
    |> Enum.with_index()
    |> Enum.reject(fn {_stmt, idx} -> MapSet.member?(remove_indices, idx) end)
    |> Enum.map(fn
      {{:def, meta, [head, body_kw]}, idx} ->
        if MapSet.member?(convert_indices, idx) do
          {:defp, meta, [head, body_kw]}
        else
          {:def, meta, [head, body_kw]}
        end

      {stmt, _idx} ->
        stmt
    end)
  end

  defp block_to_list({:__block__, _, stmts}) when is_list(stmts), do: stmts
  defp block_to_list(single), do: [single]
end
