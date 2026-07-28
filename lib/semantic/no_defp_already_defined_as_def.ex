defmodule Credence.Semantic.NoDefpAlreadyDefinedAsDef do
  @moduledoc """
  Fixes compiler errors caused by LLMs defining a function as both `def` and
  `defp` with the same name and arity.

  LLMs commonly produce code like:

      def stab_count(server, point) do
        GenServer.call(server, {:stab_count, point})
      end

      defp stab_count(nil, _point), do: 0
      defp stab_count(%{left: l, right: r}, point) do
        1 + stab_count(l, point) + stab_count(r, point)
      end

  The compiler emits "defp X/N already defined as def" because Elixir does not
  allow a private clause with the same name/arity as a public one.

  When the `defp` argument patterns are structurally identical to the `def`
  clause (a true duplicate), the fix removes the `defp` clause. When the
  patterns differ (e.g. a recursive helper with different base cases), the fix
  renames the `defp` to `do_<name>` and updates all internal call sites.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "already defined as def"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_defp_already_defined_as_def,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    with {name, arity} <- extract_fn_name_arity(msg),
         {:ok, ast} <- Sourceror.parse_string(source) do
      if same_patterns?(ast, name, arity) do
        case find_defp_range(ast, name, arity) do
          %Sourceror.Range{} = range -> delete_range(source, range)
          _ -> source
        end
      else
        rename_defp_to_do(source, ast, name, arity)
      end
    else
      _ -> source
    end
  end

  defp extract_fn_name_arity(msg) do
    case Regex.run(~r/defp (\w+)\/(\d+)/, msg) do
      [_, name, arity_str] -> {String.to_atom(name), String.to_integer(arity_str)}
      _ -> nil
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line

  # --- Pattern comparison --------------------------------------------------

  defp same_patterns?(ast, name, arity) do
    case {find_def_args(ast, name, arity), find_defp_args(ast, name, arity)} do
      {{:ok, d}, {:ok, p}} -> normalize_pattern(d) == normalize_pattern(p)
      _ -> false
    end
  end

  defp find_def_args(ast, name, arity) do
    {_ast, result} =
      Macro.prewalk(ast, nil, fn
        {:def, _, _} = node, nil ->
          if def_fn_name_arity(node) == {name, arity},
            do: {node, {:ok, clause_args(node)}},
            else: {node, nil}

        node, acc ->
          {node, acc}
      end)

    result || :error
  end

  defp find_defp_args(ast, name, arity) do
    {_ast, result} =
      Macro.prewalk(ast, nil, fn
        {:defp, _, _} = node, nil ->
          if defp_fn_name_arity(node) == {name, arity},
            do: {node, {:ok, clause_args(node)}},
            else: {node, nil}

        node, acc ->
          {node, acc}
      end)

    result || :error
  end

  defp clause_args({_, _, [head | _]}) do
    head =
      case head do
        {:when, _, [h | _]} -> h
        _ -> head
      end

    case head do
      {_, _, args} when is_list(args) -> args
      {_, _, nil} -> []
      _ -> []
    end
  end

  defp normalize_pattern(args) do
    Enum.map(args, fn arg ->
      arg
      |> Macro.prewalk(fn
        {form, _meta, children} -> {form, [], children}
        other -> other
      end)
      |> Macro.to_string()
    end)
  end

  # --- Rename path ---------------------------------------------------------

  defp rename_defp_to_do(_source, ast, name, arity) do
    new_name = :"do_#{name}"
    new_ast = walk_and_rename(ast, name, arity, new_name)
    Sourceror.to_string(new_ast)
  end

  # defp with matching name: rename head, walk body
  defp walk_and_rename({:defp, meta, [{n, fmeta, args}, body_kw]}, name, arity, new_name)
       when is_atom(n) and n == name do
    {:defp, meta, [{new_name, fmeta, args}, walk_body_kw(body_kw, name, arity, new_name)]}
  end

  # defp with matching name via when guard
  defp walk_and_rename(
         {:defp, meta, [{:when, wmeta, [{n, fmeta, args} | guards]}, body_kw]},
         name,
         arity,
         new_name
       )
       when is_atom(n) and n == name do
    {:defp, meta,
     [
       {:when, wmeta, [{new_name, fmeta, args} | guards]},
       walk_body_kw(body_kw, name, arity, new_name)
     ]}
  end

  # def: walk body only, skip head
  defp walk_and_rename({:def, meta, [head, body_kw]}, name, arity, new_name) do
    {:def, meta, [head, walk_body_kw(body_kw, name, arity, new_name)]}
  end

  # defp with different name: walk body only, skip head
  defp walk_and_rename({:defp, meta, [head, body_kw]}, name, arity, new_name) do
    {:defp, meta, [head, walk_body_kw(body_kw, name, arity, new_name)]}
  end

  # Call site: rename bare function calls with matching arity
  defp walk_and_rename({n, meta, args}, name, arity, new_name)
       when is_atom(n) and is_list(args) and length(args) == arity and n == name do
    {new_name, meta, Enum.map(args, &walk_and_rename(&1, name, arity, new_name))}
  end

  # Generic 3-tuple node: walk children
  defp walk_and_rename({form, meta, children}, name, arity, new_name)
       when is_list(children) do
    {form, meta, Enum.map(children, &walk_and_rename(&1, name, arity, new_name))}
  end

  # 2-tuple
  defp walk_and_rename({a, b}, name, arity, new_name) do
    {walk_and_rename(a, name, arity, new_name), walk_and_rename(b, name, arity, new_name)}
  end

  # List
  defp walk_and_rename(list, name, arity, new_name) when is_list(list) do
    Enum.map(list, &walk_and_rename(&1, name, arity, new_name))
  end

  # Leaf
  defp walk_and_rename(other, _name, _arity, _new_name), do: other

  defp walk_body_kw(kw, name, arity, new_name) when is_list(kw) do
    Enum.map(kw, fn
      {k, body} -> {k, walk_and_rename(body, name, arity, new_name)}
    end)
  end

  # --- Deletion path -------------------------------------------------------

  defp find_defp_range(ast, name, arity) do
    {_ast, result} =
      Macro.prewalk(ast, nil, fn
        {:defp, _, _} = node, nil ->
          if defp_fn_name_arity(node) == {name, arity} do
            {node, Sourceror.get_range(node)}
          else
            {node, nil}
          end

        node, acc ->
          {node, acc}
      end)

    result
  end

  defp defp_fn_name_arity({:defp, _meta, [_head | _]} = node) do
    head =
      case node do
        {:defp, _, [{:when, _, [h | _]} | _]} -> h
        {:defp, _, [h | _]} -> h
      end

    case head do
      {name, _, args} when is_atom(name) and is_list(args) -> {name, length(args)}
      _ -> nil
    end
  end

  defp defp_fn_name_arity(_), do: nil

  defp def_fn_name_arity({:def, _meta, [_head | _]} = node) do
    head =
      case node do
        {:def, _, [{:when, _, [h | _]} | _]} -> h
        {:def, _, [h | _]} -> h
      end

    case head do
      {name, _, args} when is_atom(name) and is_list(args) -> {name, length(args)}
      _ -> nil
    end
  end

  defp def_fn_name_arity(_), do: nil

  defp delete_range(source, %Sourceror.Range{start: s, end: e}) do
    lines = String.split(source, "\n")
    start_idx = s[:line] - 1
    end_idx = e[:line] - 1

    delete_from =
      if start_idx > 0 and String.trim(Enum.at(lines, start_idx - 1, "")) == "",
        do: start_idx - 1,
        else: start_idx

    new_lines = Enum.take(lines, delete_from) ++ Enum.drop(lines, end_idx + 1)
    Enum.join(new_lines, "\n")
  end
end
