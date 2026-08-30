defmodule Credence.Semantic.FixApplyArityOne do
  @moduledoc """
  Fixes the compile error caused by calling `apply/1`.

  Elixir has only `apply/2` and `apply/3`; `apply/1` does not exist. LLMs
  frequently write `apply(func)` thinking `apply` takes just a function.
  The compiler emits:

      "undefined function apply/1"

  The deterministic fix is `apply(func)` → `apply(func, [])`, which calls
  `func` with zero arguments — the intended semantics. The piped spelling
  `x |> apply()` (also `apply/1` after pipe expansion) becomes
  `x |> apply([])`, i.e. `apply(x, [])`.

  ## Why the rewrite is scoped to the diagnostic line

  A one-arg `apply` AST node is not always an erroneous `apply/1` call, so a
  whole-file rewrite would break valid code:

  - `def apply(x)` / `defdelegate apply(x)` heads have the same node shape —
    adding an argument changes that module's API. If the module containing the
    diagnostic defines `apply`, the fix bails (a rewritten call could resolve
    to the local, not `Kernel.apply/2`). Definitions in sibling modules do not
    affect resolution in the failing module.
  - `x |> apply(f)` is a valid `apply/2` whose AST node has one argument;
    pipe right-hand sides are never given an extra argument (the zero-arg
    `x |> apply()` form is fixed at the pipe instead).
  - `apply(f)` inside a `quote` block is valid meta-code; line scoping keeps
    the fix off it.
  - `apply do ... end` renders badly with an inserted argument, and
    `&apply/1` cannot take one — both are left for a human.

  ## Why this rule beats `UndefinedFunction`

  Both claim `undefined function apply/1 …` — this rule by regex on that
  exact arity, `UndefinedFunction` by the bare substring. This rule keeps the
  default 500 against that rule's declared 501, so the ordering is stated
  rather than inherited from where the module names sort (docs/20 §1).
  `UndefinedFunction` repairs bare calls by table lookup, has no `apply` row
  and no fuzzy fallback for local calls, and would return the source
  unchanged — the `[]` insertion, the pipe spelling and the bail on a
  file-defined `apply` exist only here.

  ## Bad

      defmodule FixApplyArityOneExampleFAAO do
        def call_clock(state) do
          current_time = apply(state.clock)
          current_time
        end
      end

  ## Good

      defmodule FixApplyArityOneExampleFAAO do
        def call_clock(state) do
          current_time = apply(state.clock, [])
          current_time
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # `(?!\d)` keeps e.g. "undefined function apply/12" from matching.
  @match_re ~r{undefined function apply/1(?!\d)}

  # Meta key marking pipe right-hand sides so the bare-call clause skips
  # them; Sourceror ignores unknown meta keys when rendering.
  @skip :credence_apply_skip

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    Regex.match?(@match_re, msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_apply_arity_one,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with target when is_integer(target) <- line(diagnostic),
         {:ok, ast} <- Sourceror.parse_string(source),
         false <- defines_apply?(ast, target) do
      {new_ast, changed} = rewrite(ast, target)

      if changed, do: Sourceror.to_string(new_ast) <> "\n", else: source
    else
      _ -> source
    end
  end

  defp rewrite(ast, target) do
    pre = fn
      {:quote, _, _} = node, {changed, depth} ->
        {node, {changed, depth + 1}}

      # Pipe RHS: `x |> apply()` / `x |> apply` at the target line means
      # apply/1 — insert `[]` there so it becomes `apply(x, [])`. Any other
      # apply RHS (e.g. the valid `x |> apply(f)` = apply/2) is only marked
      # so the bare-call clause below leaves it alone.
      {:|>, pmeta, [lhs, {:apply, ameta, args}]}, {changed, 0} ->
        if args in [nil, []] and ameta[:line] == target do
          fixed = {:apply, mark(ameta), [empty_list(ameta)]}
          {{:|>, pmeta, [lhs, fixed]}, {true, 0}}
        else
          {{:|>, pmeta, [lhs, {:apply, mark(ameta), args}]}, {changed, 0}}
        end

      # Bare call with exactly one argument at the target line. Do-block
      # calls (`apply do ... end`) carry `do:` meta and are skipped.
      {:apply, meta, [single_arg]} = node, {changed, 0} ->
        if meta[:line] == target and meta[@skip] == nil and meta[:do] == nil do
          {{:apply, meta, [single_arg, empty_list(meta)]}, {true, 0}}
        else
          {node, {changed, 0}}
        end

      node, acc ->
        {node, acc}
    end

    post = fn
      {:quote, _, _} = node, {changed, depth} -> {node, {changed, depth - 1}}
      node, acc -> {node, acc}
    end

    {new_ast, {changed, 0}} = Macro.traverse(ast, {false, 0}, pre, post)
    {new_ast, changed}
  end

  defp mark(meta), do: [{@skip, true} | meta]

  defp empty_list(meta), do: {:__block__, [line: meta[:line]], [[]]}

  # True if the module containing the diagnostic defines `apply` (any arity)
  # via def, defp, defmacro(p), defguard(p) or defdelegate. Then a one-arg
  # `apply` node may be a definition head or a valid local call, so the fix
  # bails. An apply definition in a sibling module cannot affect resolution.
  defp defines_apply?(ast, target) do
    {_, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, _} = node, modules ->
          if contains_line?(node, target), do: {node, [node | modules]}, else: {node, modules}

        node, modules ->
          {node, modules}
      end)

    case Enum.min_by(modules, &range_size/1, fn -> nil end) do
      {:defmodule, _, [_name, [do: body]]} -> module_defines_apply?(body)
      {:defmodule, _, [_name, [{{:__block__, _, [:do]}, body}]]} -> module_defines_apply?(body)
      _ -> false
    end
  end

  defp module_defines_apply?(body) do
    {_, found} =
      Macro.prewalk(body, false, fn
        {:defmodule, _, _} = node, found ->
          {Macro.escape(node), found}

        {kind, _, [head | _]} = node, found
        when kind in [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp, :defdelegate] ->
          {node, found or apply_head?(head)}

        node, found ->
          {node, found}
      end)

    found
  end

  defp contains_line?({:defmodule, meta, _}, target) do
    first = meta[:line]
    last = meta[:end][:line] || meta[:end_of_expression][:line]
    is_integer(first) and is_integer(last) and target >= first and target <= last
  end

  defp range_size({:defmodule, meta, _}) do
    (meta[:end][:line] || meta[:end_of_expression][:line]) - meta[:line]
  end

  defp apply_head?({:when, _, [head | _]}), do: apply_head?(head)
  defp apply_head?({:apply, _, _}), do: true
  defp apply_head?(_), do: false

  defp line(%{position: {line, _col}}) when is_integer(line), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_), do: nil
end
