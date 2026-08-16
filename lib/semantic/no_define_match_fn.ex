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
              {renamed, _} = rename_match_refs(body)
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

  # True when the module body defines a local `def`/`defp match?` (any clause,
  # including a guarded head).
  defp defines_local_match?(body) do
    {_, found?} =
      Macro.prewalk(body, false, fn
        {def_kind, _, [head | _]} = node, acc when def_kind in [:def, :defp] ->
          if match_head?(head), do: {node, true}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp match_head?({:match?, _, args}) when is_list(args), do: true
  defp match_head?({:when, _, [inner | _]}), do: match_head?(inner)
  defp match_head?(_), do: false

  # Rename every local `match?` reference — call sites, definition heads, and
  # `&match?/N` captures — to `match_pattern?`. Qualified calls (`Kernel.match?`)
  # are `{{:., …}, …}` nodes and are left untouched.
  defp rename_match_refs(ast) do
    Macro.prewalk(ast, false, fn
      {:match?, meta, args}, _acc when is_list(args) ->
        {{:match_pattern?, meta, args}, true}

      {:match?, meta, ctx}, _acc when is_atom(ctx) ->
        {{:match_pattern?, meta, ctx}, true}

      node, acc ->
        {node, acc}
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
