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

  ## Bad

      defmodule ExampleNDADAD do
        def greet(name) do
          "Hello, " <> name
        end

        defp greet(name) do
          "Hi, " <> name
        end
      end

  ## Good

      defmodule ExampleNDADAD do
        def greet(name) do
          "Hello, " <> name
        end
      end
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
  def fix(source, %{message: msg} = diagnostic) do
    with {name, arity} <- extract_fn_name_arity(msg),
         {:ok, ast} <- Sourceror.parse_string(source),
         line when is_integer(line) <- line(diagnostic),
         {:ok, module} <- find_target_module(ast, name, arity, line) do
      if duplicate_clause?(module, name, arity, line) do
        case find_defp_range(module, name, arity, line) do
          %Sourceror.Range{} = range -> delete_range(source, range)
          _ -> source
        end
      else
        rename_defp_to_do(ast, module, name, arity)
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

  # --- Target and duplicate detection -------------------------------------

  defp find_target_module(ast, name, arity, line) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, _} = node, acc ->
          range = Sourceror.get_range(node)

          if line_in_range?(line, range) and has_direct_defp?(node, name, arity),
            do: {node, [node | acc]},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    case Enum.min_by(modules, &module_line_span/1, fn -> nil end) do
      nil -> :error
      module -> {:ok, module}
    end
  end

  defp duplicate_clause?(module, name, arity, line) do
    clauses = direct_clauses(module)

    private =
      clauses
      |> Enum.filter(&(defp_fn_name_arity(&1) == {name, arity}))
      |> Enum.min_by(&abs(node_line(&1) - line), fn -> nil end)

    public = Enum.filter(clauses, &(def_fn_name_arity(&1) == {name, arity}))

    private != nil and Enum.any?(public, &(normalized_clause(&1) == normalized_clause(private)))
  end

  defp normalized_clause({kind, _, parts}) when kind in [:def, :defp] do
    {:def, [], strip_meta(parts)}
  end

  defp strip_meta(term) do
    Macro.prewalk(term, fn
      {form, meta, children} when is_list(meta) -> {form, [], children}
      other -> other
    end)
  end

  defp direct_clauses({:defmodule, _, [_name, body_kw]}) do
    case keyword_value(body_kw, :do) do
      {:__block__, _, clauses} -> clauses
      nil -> []
      clause -> [clause]
    end
  end

  defp direct_clauses(_), do: []

  defp keyword_value(keyword, key) do
    Enum.find_value(keyword, fn
      {{:__block__, _, [^key]}, value} -> value
      {^key, value} -> value
      _ -> nil
    end)
  end

  defp has_direct_defp?(module, name, arity) do
    Enum.any?(direct_clauses(module), &(defp_fn_name_arity(&1) == {name, arity}))
  end

  defp line_in_range?(line, %Sourceror.Range{start: s, end: e}),
    do: line >= s[:line] and line <= e[:line]

  defp module_line_span(node) do
    %Sourceror.Range{start: s, end: e} = Sourceror.get_range(node)
    e[:line] - s[:line]
  end

  defp node_line({_form, meta, _children}), do: Keyword.get(meta, :line, 0)

  # --- Rename path ---------------------------------------------------------

  defp rename_defp_to_do(ast, target_module, name, arity) do
    new_name = :"do_#{name}"
    target_start = node_line(target_module)

    new_ast =
      Macro.prewalk(ast, fn
        {:defmodule, _, _} = node ->
          if node_line(node) == target_start,
            do: rename_target_module(node, name, arity, new_name),
            else: node

        node ->
          node
      end)

    Sourceror.to_string(new_ast)
  end

  defp rename_target_module({:defmodule, meta, [module_name, body_kw]}, name, arity, new_name) do
    {:defmodule, meta, [module_name, walk_body_kw(body_kw, name, arity, new_name)]}
  end

  # defp with matching name: rename head, walk body
  defp walk_and_rename({:defp, meta, [{n, fmeta, args}, body_kw]}, name, arity, new_name)
       when is_atom(n) and n == name and is_list(args) and length(args) == arity do
    {:defp, meta, [{new_name, fmeta, args}, walk_body_kw(body_kw, name, arity, new_name)]}
  end

  # defp with matching name via when guard
  defp walk_and_rename(
         {:defp, meta, [{:when, wmeta, [{n, fmeta, args} | guards]}, body_kw]},
         name,
         arity,
         new_name
       )
       when is_atom(n) and n == name and is_list(args) and length(args) == arity do
    {:defp, meta,
     [
       {:when, wmeta, [{new_name, fmeta, args} | guards]},
       walk_body_kw(body_kw, name, arity, new_name)
     ]}
  end

  # def: walk body only, skip head
  defp walk_and_rename({:def, meta, [head, body_kw]}, name, arity, new_name) do
    node = {:def, meta, [head, body_kw]}

    if def_fn_name_arity(node) == {name, arity},
      do: node,
      else: {:def, meta, [head, walk_body_kw(body_kw, name, arity, new_name)]}
  end

  defp walk_and_rename({:defmodule, _, _} = node, _name, _arity, _new_name), do: node

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

  defp find_defp_range(module, name, arity, line) do
    module
    |> direct_clauses()
    |> Enum.filter(&(defp_fn_name_arity(&1) == {name, arity}))
    |> Enum.min_by(&abs(node_line(&1) - line), fn -> nil end)
    |> case do
      nil -> nil
      node -> Sourceror.get_range(node)
    end
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
