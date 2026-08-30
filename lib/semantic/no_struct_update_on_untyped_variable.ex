defmodule Credence.Semantic.NoStructUpdateOnUntypedVariable do
  @moduledoc """
  Removes the misleading struct qualifier from an update whose source is an
  untyped variable.

  LLMs commonly write:

      def execute(context, action_fn) when is_function(action_fn, 1) do
        %__MODULE__{context | steps: context.steps ++ [action_fn]}
      end

  Elixir's type checker cannot prove `context` is a `%Saga{}`, so it emits
  (severity `:warning`, verified on Elixir 1.20.2):

      a struct for Saga is expected on struct update:

          %Saga{context | steps: context.steps ++ [action_fn]}

      but got type:

          dynamic()

      where "context" was given the type:

          # type: dynamic()
          # from: credence_check.ex:4:15
          context

      when defining the variable "context", you must also pattern match on "%Saga{}"

  The message names the variable, which is all `match?/1` gets — the phase hands
  rules a diagnostic only, and its `file` is the synthetic `credence_check.ex`
  that `RuleHelpers.compile_and_capture/1` compiles under, so nothing may be read
  from disk. `should_report?/2` re-runs `fix/2` to keep `analyze` from flagging a
  shape the fix declines.

  The fix keeps the update's runtime semantics while dropping the assertion the
  compiler cannot prove:

      def execute(context, action_fn) when is_function(action_fn, 1) do
        %{context | steps: context.steps ++ [action_fn]}

  It is applied as a `Sourceror` patch over the struct name alone, so every other
  byte of the file (layout, comments, unrelated lines) survives verbatim.

  ## What is deliberately left alone

  The rule remains deliberately narrow. All three conditions must hold:

    * **The clause body is exactly the struct update** — nested updates and
      clauses with preceding statements remain outside this rule's established
      matching envelope.
    * **The name/arity has exactly one clause in the file.**
    * **The variable appears exactly once as a bare parameter**, and the struct
      being updated is spelled `__MODULE__` or a plain alias.

  `%Struct{value | fields}` and `%{value | fields}` perform the same map-update
  operation at runtime; the struct name supplies compile-time field validation
  and the warning, but does not coerce or validate `value`. Removing only that
  qualifier therefore preserves returned values and the original `KeyError` or
  `BadMapError` for invalid maps and non-maps.

  ## Bad

      defmodule SagaNSUOUV do
        defstruct steps: []

        def execute(other, action_fn) do
          %__MODULE__{other | steps: [action_fn]}
        end
      end

  ## Good

      defmodule SagaNSUOUV do
        defstruct steps: []

        def execute(other, action_fn) do
          %{other | steps: [action_fn]}
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "is expected on struct update"
  @var_regex ~r/when defining the variable "([a-z_][A-Za-z0-9_]*)", you must also pattern match on/

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring) and extract_var_name(msg) != nil
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source. The same message is emitted for
  every un-narrowed struct update, most of which this rule leaves alone.
  """
  def should_report?(diagnostic, source), do: fix(source, diagnostic) != source

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_struct_update_on_untyped_variable,
      message:
        "struct update on an untyped variable — pattern match the struct in the function head",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) when is_binary(source) and is_binary(msg) do
    with var_name when is_binary(var_name) <- extract_var_name(msg),
         {:ok, ast} <- Sourceror.parse_string(source) do
      apply_patches(source, patches(ast, String.to_atom(var_name)))
    else
      _ -> source
    end
  end

  def fix(source, _), do: source

  defp apply_patches(source, []), do: source

  defp apply_patches(source, patches) do
    patched = Sourceror.patch_string(source, patches)

    case Sourceror.parse_string(patched) do
      {:ok, _} -> patched
      _ -> source
    end
  end

  # One patch per clause that satisfies every condition in the moduledoc.
  defp patches(ast, var_atom) do
    counts = clause_counts(ast)

    {_, patches} =
      Macro.prewalk(ast, [], fn
        {kind, _, [head, [{{:__block__, _, [:do]}, body}]]} = node, acc
        when kind in [:def, :defp] ->
          {node, prepend_patch(acc, head, body, var_atom, counts)}

        node, acc ->
          {node, acc}
      end)

    patches
  end

  defp prepend_patch(acc, head, body, var_atom, counts) do
    with {name, _, params} when is_atom(name) and is_list(params) <- unwrap_when(head),
         true <- Map.get(counts, {name, length(params)}) == 1,
         {:ok, prefix_range} <- sole_struct_update(body, var_atom),
         {:ok, _var_node} <- sole_bare_param(params, var_atom) do
      [%{range: prefix_range, change: ""} | acc]
    else
      _ -> acc
    end
  end

  defp unwrap_when({:when, _, [call, _guard]}), do: call
  defp unwrap_when(head), do: head

  # The body must BE `%Struct{var | ...}` — see "What is deliberately left
  # alone". Returns the range covering `%Struct`, immediately before the map.
  defp sole_struct_update(
         {:%, _, [struct_expr, {:%{}, _, [{:|, _, [{var_atom, _, nil} | _]}]}]} = update,
         var_atom
       ),
       do: struct_prefix_range(update, struct_expr)

  defp sole_struct_update(_, _), do: :error

  defp struct_prefix_range(update, {:__MODULE__, _, ctx} = struct_expr) when is_atom(ctx),
    do: prefix_range(update, struct_expr)

  defp struct_prefix_range(update, {:__aliases__, _, segments} = struct_expr) do
    if segments != [] and Enum.all?(segments, &is_atom/1) do
      prefix_range(update, struct_expr)
    else
      :error
    end
  end

  defp struct_prefix_range(_, _), do: :error

  defp prefix_range(_update, struct_expr), do: {:ok, Sourceror.get_range(struct_expr)}

  defp sole_bare_param(params, var_atom) do
    case Enum.filter(params, &match?({^var_atom, _, nil}, &1)) do
      [var_node] -> {:ok, var_node}
      _ -> :error
    end
  end

  # `{name, arity} => number of def/defp clauses in the file`. Bodyless heads
  # (default-argument declarations) count too, so those functions are skipped.
  defp clause_counts(ast) do
    {_, counts} =
      Macro.prewalk(ast, %{}, fn
        {kind, _, [head | _]} = node, acc when kind in [:def, :defp] ->
          case signature(head) do
            {:ok, sig} -> {node, Map.update(acc, sig, 1, &(&1 + 1))}
            :error -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    counts
  end

  defp signature(head) do
    case unwrap_when(head) do
      {name, _, params} when is_atom(name) and is_list(params) -> {:ok, {name, length(params)}}
      {name, _, ctx} when is_atom(name) and is_atom(ctx) -> {:ok, {name, 0}}
      _ -> :error
    end
  end

  defp extract_var_name(msg) do
    case Regex.run(@var_regex, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp line(%{position: {line, _col}}) when is_integer(line), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_), do: nil
end
