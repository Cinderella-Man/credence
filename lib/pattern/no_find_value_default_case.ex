defmodule Credence.Pattern.NoFindValueDefaultCase do
  @moduledoc """
  Detects `Enum.find_value/2` or `Enum.find/2` where the result is
  immediately checked against `nil` to provide a default, instead of
  using the 3-arity version that accepts a default argument.

  Also detects `Enum.find/2` on maps where the result tuple is
  destructured to extract a single element.

  ## Bad

      case Enum.find_value(list, &process/1) do
        nil -> :default
        val -> val
      end

      Enum.find(list, &valid?/1) || :default

      case Enum.find(map, fn {_k, v} -> v == target end) do
        {key, _} -> key
        nil -> -1
      end

  ## Good

      Enum.find_value(list, :default, &process/1)
      Enum.find(list, :default, &valid?/1)

      Enum.find_value(map, -1, fn {key, v} ->
        if v == target, do: key
      end)

  ## Auto-fix

  Replaces the `case`/`||` wrapper with the 3-arity call. For tuple
  extraction patterns, rewrites `Enum.find/2` to `Enum.find_value/3`
  with the extraction and predicate combined into a single callback.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @find_funcs [:find_value, :find]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # case Enum.find_value/Enum.find(coll, fun) do nil -> d; v -> v end
        # case Enum.find(coll, fun) do nil -> d; {k, _} -> k end
        {:case, meta, [find_call, kw]} = node, acc when is_list(kw) ->
          if find2?(find_call) and (nil_identity?(kw) or destructure_extraction?(kw)) do
            {node, [build_issue(:case, meta, find_call) | acc]}
          else
            {node, acc}
          end

        # Enum.find_value/Enum.find(coll, fun) |> case do nil -> d; v -> v end
        {:|>, _, [find_call, {:case, meta, [kw]}]} = node, acc when is_list(kw) ->
          if find2?(find_call) and (nil_identity?(kw) or destructure_extraction?(kw)) do
            {node, [build_issue(:case, meta, find_call) | acc]}
          else
            {node, acc}
          end

        # coll |> Enum.find_value/Enum.find(fun) |> case do nil -> d; v -> v end
        {:|>, _,
         [
           {:|>, _, [_coll, find1_call]},
           {:case, meta, [kw]}
         ]} = node,
        acc
        when is_list(kw) ->
          if find1?(find1_call) and (nil_identity?(kw) or destructure_extraction?(kw)) do
            {node, [build_issue(:case, meta, find1_call) | acc]}
          else
            {node, acc}
          end

        # Enum.find_value/Enum.find(coll, fun) || default
        {:||, meta, [find_call, _default]} = node, acc ->
          if find2?(find_call) do
            {node, [build_issue(:or, meta, find_call) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # case Enum.find_value/Enum.find(coll, fun) do nil -> d; v -> v end
      # case Enum.find(coll, fun) do nil -> d; {k, _} -> k end
      {:case, _, [find_call, kw]} = node ->
        cond do
          find2?(find_call) and nil_identity?(kw) ->
            default = extract_default(kw)
            rewrite_2arg(find_call, default)

          find2?(find_call) and destructure_extraction?(kw) ->
            default = extract_default(kw)
            extraction_clause = find_extraction_clause(kw)
            rewrite_2arg_destructure(find_call, default, extraction_clause)

          true ->
            node
        end

      # Enum.find_value/Enum.find(coll, fun) |> case do nil -> d; v -> v end
      {:|>, _, [find_call, {:case, _, [kw]}]} = node ->
        cond do
          find2?(find_call) and nil_identity?(kw) ->
            default = extract_default(kw)
            rewrite_2arg(find_call, default)

          find2?(find_call) and destructure_extraction?(kw) ->
            default = extract_default(kw)
            extraction_clause = find_extraction_clause(kw)
            rewrite_2arg_destructure(find_call, default, extraction_clause)

          true ->
            node
        end

      # coll |> Enum.find_value/Enum.find(fun) |> case do nil -> d; v -> v end
      {:|>, _, [{:|>, _, [coll, find1_call]}, {:case, _, [kw]}]} = node ->
        cond do
          find1?(find1_call) and nil_identity?(kw) ->
            default = extract_default(kw)
            rewrite_1arg_pipe(coll, find1_call, default)

          find1?(find1_call) and destructure_extraction?(kw) ->
            default = extract_default(kw)
            extraction_clause = find_extraction_clause(kw)
            rewrite_1arg_pipe_destructure(coll, find1_call, default, extraction_clause)

          true ->
            node
        end

      # Enum.find_value/Enum.find(coll, fun) || default
      {:||, _, [find_call, default]} = node ->
        if find2?(find_call) do
          rewrite_2arg(find_call, default)
        else
          node
        end

      node ->
        node
    end)
  end

  # ── Matchers ───────────────────────────────────────────────────────────

  defp find2?({{:., _, [{:__aliases__, _, [:Enum]}, func]}, _, [_, _]})
       when func in @find_funcs,
       do: true

  defp find2?(_), do: false

  defp find1?({{:., _, [{:__aliases__, _, [:Enum]}, func]}, _, [_]})
       when func in @find_funcs,
       do: true

  defp find1?(_), do: false

  # ── Case clause checks ─────────────────────────────────────────────────

  defp nil_identity?(kw) do
    case do_clauses(kw) do
      [c1, c2] -> (nil_clause?(c1) and identity?(c2)) or (nil_clause?(c2) and identity?(c1))
      _ -> false
    end
  end

  defp destructure_extraction?(kw) do
    case do_clauses(kw) do
      [c1, c2] ->
        (nil_clause?(c1) and extraction_clause?(c2)) or
          (nil_clause?(c2) and extraction_clause?(c1))

      _ ->
        false
    end
  end

  defp do_clauses([{{:__block__, _, [:do]}, clauses}]) when is_list(clauses), do: clauses
  defp do_clauses(_), do: nil

  defp nil_clause?({:->, _, [[{:__block__, _, [nil]}], _]}), do: true
  defp nil_clause?({:->, _, [[nil], _]}), do: true
  defp nil_clause?(_), do: false

  defp identity?({:->, _, [[{name, _, ctx}], {name2, _, ctx2}]})
       when is_atom(name) and is_atom(name2) and name == name2 and
              (is_nil(ctx) or is_atom(ctx)) and (is_nil(ctx2) or is_atom(ctx2)),
       do: true

  defp identity?(_), do: false

  defp extraction_clause?({:->, _, [[{:__block__, _, [{v1, v2}]}], body]})
       when is_tuple(v1) and is_tuple(v2) and tuple_size(v1) == 3 and tuple_size(v2) == 3 do
    body_name = extract_var_name(body)
    (not underscored?(v1) and elem(v1, 0) == body_name) or
      (not underscored?(v2) and elem(v2, 0) == body_name)
  end

  defp extraction_clause?(_), do: false

  # ── Extractors ─────────────────────────────────────────────────────────

  defp extract_default(kw) do
    do_clauses(kw)
    |> Enum.find_value(fn
      {:->, _, [[{:__block__, _, [nil]}], body]} -> body
      {:->, _, [[nil], body]} -> body
      _ -> nil
    end)
  end

  defp find_extraction_clause(kw) do
    do_clauses(kw)
    |> Enum.find(fn clause -> not nil_clause?(clause) end)
  end

  defp extract_var_name({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)),
    do: name

  defp extract_var_name(_), do: nil

  defp underscored?({name, _, _}) when is_atom(name) do
    name |> Atom.to_string() |> String.starts_with?("_")
  end

  defp underscored?(_), do: false

  defp find_used_var({:__block__, _, [{v1, v2}]})
       when is_tuple(v1) and is_tuple(v2) and tuple_size(v1) == 3 and tuple_size(v2) == 3 do
    cond do
      not underscored?(v1) -> {v1, 0}
      not underscored?(v2) -> {v2, 1}
      true -> {nil, nil}
    end
  end

  defp find_var_position({:__block__, _, [{v1, _v2}]}, target_name)
       when is_tuple(v1) and tuple_size(v1) == 3 do
    if elem(v1, 0) == target_name, do: 0, else: 1
  end

  defp build_tuple_param(pred_var_node, pred_pos, extract_node, extract_pos) do
    elems = List.duplicate(nil, 2)
    elems = List.replace_at(elems, pred_pos, pred_var_node)
    elems = List.replace_at(elems, extract_pos, extract_node)
    {:__block__, [], [{Enum.at(elems, 0), Enum.at(elems, 1)}]}
  end

  # ── Rewriters ──────────────────────────────────────────────────────────

  defp rewrite_2arg(
         {{:., dm, [{:__aliases__, am, [:Enum]}, func]}, cm, [coll, fun]},
         default
       ) do
    {{:., dm, [{:__aliases__, am, [:Enum]}, func]}, cm, [coll, default, fun]}
  end

  defp rewrite_1arg_pipe(
         coll,
         {{:., dm, [{:__aliases__, am, [:Enum]}, func]}, cm, [fun]},
         default
       ) do
    {{:., dm, [{:__aliases__, am, [:Enum]}, func]}, cm, [coll, default, fun]}
  end

  defp rewrite_2arg_destructure(
         {{:., dm, [{:__aliases__, am, [:Enum]}, :find]}, cm, [coll, fun]},
         default,
         extraction_clause
       ) do
    {:fn, fm, [{:->, _, [[param_pattern], pred_body]}]} = fun
    {pred_var_node, pred_pos} = find_used_var(param_pattern)

    {:->, _, [[extract_pattern], extract_body]} = extraction_clause
    extract_var_name = extract_var_name(extract_body)
    extract_pos = find_var_position(extract_pattern, extract_var_name)

    extract_node = {extract_var_name, [], nil}
    new_param = build_tuple_param(pred_var_node, pred_pos, extract_node, extract_pos)
    new_body = {:if, [], [pred_body, [do: extract_node]]}
    new_fun = {:fn, fm, [{:->, [], [[new_param], new_body]}]}

    {{:., dm, [{:__aliases__, am, [:Enum]}, :find_value]}, cm, [coll, default, new_fun]}
  end

  defp rewrite_1arg_pipe_destructure(
         coll,
         {{:., dm, [{:__aliases__, am, [:Enum]}, :find]}, cm, [fun]},
         default,
         extraction_clause
       ) do
    {:fn, fm, [{:->, _, [[param_pattern], pred_body]}]} = fun
    {pred_var_node, pred_pos} = find_used_var(param_pattern)

    {:->, _, [[extract_pattern], extract_body]} = extraction_clause
    extract_var_name = extract_var_name(extract_body)
    extract_pos = find_var_position(extract_pattern, extract_var_name)

    extract_node = {extract_var_name, [], nil}
    new_param = build_tuple_param(pred_var_node, pred_pos, extract_node, extract_pos)
    new_body = {:if, [], [pred_body, [do: extract_node]]}
    new_fun = {:fn, fm, [{:->, [], [[new_param], new_body]}]}

    {{:., dm, [{:__aliases__, am, [:Enum]}, :find_value]}, cm, [coll, default, new_fun]}
  end

  # ── Issue builders ─────────────────────────────────────────────────────

  defp build_issue(:case, meta, find_call) do
    {{:., _, [{:__aliases__, _, [:Enum]}, func]}, _, _} = find_call

    %Issue{
      rule: :no_find_value_default_case,
      message:
        "`case Enum.#{func}/2 do nil -> default; val -> val end` should use " <>
          "`Enum.#{func}/3` with the default as the second argument.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_issue(:or, meta, find_call) do
    {{:., _, [{:__aliases__, _, [:Enum]}, func]}, _, _} = find_call

    %Issue{
      rule: :no_find_value_default_case,
      message:
        "`Enum.#{func}/2 || default` treats `false` as falsy. " <>
          "Use `Enum.#{func}/3` with the default as the second argument.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
