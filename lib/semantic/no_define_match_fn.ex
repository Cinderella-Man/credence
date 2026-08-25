defmodule Credence.Semantic.NoDefineMatchFn do
  @moduledoc """
  Fixes the compile error caused by defining `defp match?/2`.

  LLMs frequently define a local `match?/2` helper for custom matching logic
  that conflicts with the auto-imported `Kernel.match?/2`. The compiler emits:

      "imported Kernel.match?/2 conflicts with local function"

  The fix renames the local function to `match_pattern?` and updates all
  internal call sites.

  ## Bad

      defmodule ANDMF do
        defp match?(a, b), do: a == b
        def f(x), do: match?(x, 1)
      end

      defmodule BNDMF do
        def g(x), do: match?({:ok, _}, x)
      end

  ## Good

      defmodule ANDMF do
        defp match_pattern?(a, b), do: a == b
        def f(x), do: match_pattern?(x, 1)
      end

      defmodule BNDMF do
        def g(x), do: match?({:ok, _}, x)
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @conflict_msg "conflicts with local function"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    # Only the `Kernel.match?/2` conflict — NOT `max/2`, `min/2`, `node/0`, etc.,
    # which are owned by sibling rules and which this rule's fix cannot repair.
    String.contains?(msg, "match?/2") and String.contains?(msg, @conflict_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_define_match_fn,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          # Only rename inside a module that actually defines a local `match?`.
          # Renaming file-wide would clobber legitimate `Kernel.match?/2` calls in
          # sibling modules (or a conflict-free file), breaking otherwise-valid code.
          {:defmodule, meta, [name, body]}, acc when is_list(body) ->
            if defines_local_match?(body) do
              renamed = rename_module_body(body)
              {{:defmodule, meta, [name, renamed]}, true}
            else
              {{:defmodule, meta, [name, body]}, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # True when this module (not a nested module) defines `defp match?/2`.
  defp defines_local_match?(body) do
    Enum.any?(module_expressions(body), fn
      {:defp, _, [head | _]} -> match_head?(head)
      _ -> false
    end)
  end

  defp match_head?({:match?, _, args}) when is_list(args), do: length(args) == 2
  defp match_head?({:when, _, [inner | _]}), do: match_head?(inner)
  defp match_head?(_), do: false

  defp module_expressions([{:do, {:__block__, _, expressions}}]), do: expressions

  defp module_expressions([{{:__block__, _, [:do]}, {:__block__, _, expressions}}]),
    do: expressions

  defp module_expressions([{:do, expression}]), do: [expression]
  defp module_expressions([{{:__block__, _, [:do]}, expression}]), do: [expression]

  # Rewrite each direct module expression separately so nested modules retain
  # their own lexical scope and are considered by the outer traversal later.
  defp rename_module_body([{do_key, {:__block__, meta, expressions}}]) do
    [{do_key, {:__block__, meta, Enum.map(expressions, &rename_module_expression/1)}}]
  end

  defp rename_module_body([{do_key, expression}]) do
    [{do_key, rename_module_expression(expression)}]
  end

  defp rename_module_expression({:defmodule, _, _} = expression), do: expression

  defp rename_module_expression(expression) do
    {renamed, _} = rename_match_refs(expression)
    renamed
  end

  # Rename only local `match?/2` calls, definition heads, and captures.
  # Qualified calls (`Kernel.match?`) are left untouched.
  defp rename_match_refs(ast) do
    Macro.prewalk(ast, false, fn
      {:&, capture_meta, [{:/, slash_meta, [{:match?, match_meta, context}, 2]}]}, _acc
      when is_atom(context) ->
        renamed =
          {:&, capture_meta, [{:/, slash_meta, [{:match_pattern?, match_meta, context}, 2]}]}

        {renamed, true}

      {:&, capture_meta,
       [{:/, slash_meta, [{:match?, match_meta, context}, {:__block__, arity_meta, [2]}]}]},
      _acc
      when is_atom(context) ->
        renamed =
          {:&, capture_meta,
           [
             {:/, slash_meta,
              [{:match_pattern?, match_meta, context}, {:__block__, arity_meta, [2]}]}
           ]}

        {renamed, true}

      {:match?, meta, [left, right]}, _acc ->
        {{:match_pattern?, meta, [left, right]}, true}

      {:match?, meta, args}, acc when is_list(args) ->
        {{:match?, meta, args}, acc}

      {:match?, meta, ctx}, acc when is_atom(ctx) ->
        {{:match?, meta, ctx}, acc}

      node, acc ->
        {node, acc}
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
