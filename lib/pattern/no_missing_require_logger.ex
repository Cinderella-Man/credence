defmodule Credence.Pattern.NoMissingRequireLogger do
  @moduledoc """
  Detects Logger macro calls without a `require Logger` in the enclosing module.

  Logger's logging functions (`info`, `debug`, `warning`, `error`, etc.) are
  macros, not regular functions. Calling them without `require Logger` compiles
  fine but crashes at runtime with `UndefinedFunctionError`:

      ** (UndefinedFunctionError) function Logger.info/1 is undefined or private.
         However, there is a macro with the same name and arity.
         Be sure to require Logger if you intend to invoke this macro

  LLMs frequently forget the `require` because Python's `logging.info()` needs
  no equivalent setup.

  ## Bad

      defmodule MyApp do
        def run do
          Logger.info("starting")
        end
      end

  ## Good

      defmodule MyApp do
        require Logger

        def run do
          Logger.info("starting")
        end
      end

  ## What is flagged

  Any `defmodule` whose body calls a Logger macro (`debug`, `info`, `notice`,
  `warning`, `warn`, `error`, `critical`, `alert`, `emergency`, `log`) without
  a corresponding `require Logger`, `import Logger`, or `use Logger`.

  Logger function calls like `Logger.configure/1` or `Logger.metadata/1` are
  not flagged — they are regular functions that don't need `require`.

  ## Auto-fix

  Inserts `require Logger` at the top of the module body, after any existing
  `@moduledoc`, `use`, `import`, `require`, or `alias` directives.

  ## Known limitations

  Aliased Logger (`alias Logger, as: L` then `L.info(...)`) is not detected.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @logger_macros ~w(debug info notice warning warn error critical alert emergency log)a

  @impl true
  def check(ast, _opts) do
    for {{:defmodule, meta, _}, _kw} <- unsatisfied_modules(ast), do: build_issue(meta)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Enum.flat_map(unsatisfied_modules(ast), fn {_node, kw} -> require_patch(kw) end)
  end

  # Modules (innermost-first within each scope) that call a Logger macro and have
  # NOTHING in scope that would provide `require Logger`. "In scope" includes the
  # module's own directives AND those inherited from enclosing modules / file
  # scope, because `require`/`alias` propagate lexically downward. A module is
  # treated as satisfied (not flagged, not auto-required) when, anywhere in scope:
  #   * `require`/`import`/`use Logger`,
  #   * an `alias` that makes `Logger` refer to a *different* module
  #     (`alias Conform.Logger` / `alias X, as: Logger`) — then `Logger.*` is not
  #     the stdlib macro at all, or
  #   * any `use SomeModule` — whose `__using__` may inject `require Logger`
  #     (common for app/web base modules and logging mix-ins); we can't expand it.
  defp unsatisfied_modules(ast) do
    collect_unsatisfied(top_statements(ast), false, [])
    |> Enum.reverse()
  end

  defp collect_unsatisfied(statements, inherited?, acc) do
    scope_provides? = inherited? or Enum.any?(statements, &provides_logger?/1)

    Enum.reduce(statements, acc, fn
      {:defmodule, _meta, [_name, kw]} = node, acc when is_list(kw) ->
        case extract_do_body(kw) do
          nil ->
            acc

          body ->
            stmts = block_to_list(body)

            self_provides? =
              scope_provides? or Enum.any?(stmts, &provides_logger?/1) or
                has_logger_require?(body)

            acc =
              if has_logger_macro_call?(body) and not self_provides?,
                do: [{node, kw} | acc],
                else: acc

            collect_unsatisfied(stmts, self_provides?, acc)
        end

      _other, acc ->
        acc
    end)
  end

  defp top_statements({:__block__, _, stmts}), do: stmts
  defp top_statements(single), do: [single]

  # OTP/stdlib behaviour modules whose `use` does NOT inject `require Logger`.
  # Other `use X` are custom mix-ins (app/web bases, logging helpers) whose
  # `__using__` commonly injects `require Logger` / `alias …Logger`, which we
  # cannot expand — so we conservatively treat them as providing it.
  @stdlib_use_targets [
    [:GenServer],
    [:Agent],
    [:Task],
    [:Supervisor],
    [:DynamicSupervisor],
    [:Application],
    [:GenEvent],
    [:GenStage],
    [:Registry],
    [:Bitwise]
  ]

  # Does a single statement bring `require Logger` into scope, alias `Logger` to a
  # non-stdlib module, or possibly inject a require via a custom `use`?
  defp provides_logger?({:use, _, [{:__aliases__, _, parts} | _]}) when is_list(parts),
    do: parts not in @stdlib_use_targets

  defp provides_logger?({:use, _, [_ | _]}), do: true

  defp provides_logger?({d, _, [{:__aliases__, _, parts} | _]})
       when d in [:require, :import] and is_list(parts),
       do: List.last(parts) == :Logger

  defp provides_logger?({:alias, _, args}), do: alias_targets_logger?(args)
  defp provides_logger?(_), do: false

  # `alias Conform.Logger` (multi-segment ending in Logger) or
  # `alias X, as: Logger` (X ≠ Logger) make `Logger` refer to a non-stdlib module.
  defp alias_targets_logger?([{:__aliases__, _, parts}])
       when is_list(parts),
       do: length(parts) > 1 and List.last(parts) == :Logger

  defp alias_targets_logger?([{:__aliases__, _, target}, opts]) when is_list(opts) do
    match?({:__aliases__, _, [:Logger]}, Keyword.get(opts, :as)) and target != [:Logger]
  end

  defp alias_targets_logger?(_), do: false

  # A single zero-width insertion patch placing `require Logger` (as its own
  # paragraph) just before the first non-directive statement. Inserting
  # surgically — rather than rebuilding the module body with the extra statement
  # — avoids re-rendering, and thereby reformatting, the rest of the module.
  defp require_patch(kw) do
    with body when not is_nil(body) <- extract_do_body(kw),
         true <- has_logger_macro_call?(body) and not has_logger_require?(body),
         statements = block_to_list(body),
         anchor when not is_nil(anchor) <- Enum.at(statements, find_directive_end(statements)),
         %Sourceror.Range{start: start} <- Sourceror.get_range(anchor) do
      # Anchor the insertion at column 1 of the statement's line (not its own
      # column): `Sourceror.patch_string` re-indents a multi-line change to the
      # patch's start column, which would double the indentation. At column 1 the
      # change is inserted verbatim, so we bake the indent in ourselves.
      indent = String.duplicate(" ", start[:column] - 1)

      [
        %{
          range: %{start: [line: start[:line], column: 1], end: [line: start[:line], column: 1]},
          change: indent <> "require Logger\n\n"
        }
      ]
    else
      _ -> []
    end
  end

  # Walks the body looking for Logger.macro_name(...) calls.
  # Stops at nested defmodule nodes so inner modules don't get
  # attributed to the outer module.
  defp has_logger_macro_call?(body) do
    {_, found} =
      Macro.prewalk(body, false, fn
        _node, true ->
          {nil, true}

        # Replace nested defmodule / quote with an atom to prevent descent.
        # A Logger call inside a `quote` belongs to the *generated* code (which
        # carries its own `require Logger`), not the module defining the macro.
        {:defmodule, _, _}, acc ->
          {:__skip__, acc}

        {:quote, _, _}, acc ->
          {:__skip__, acc}

        {{:., _, [{:__aliases__, _, [:Logger]}, func]}, _, _}, _acc
        when func in @logger_macros ->
          {nil, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # A `require Logger` (or import/use) anywhere in the module body satisfies the
  # requirement — including inside a function body or a `quote`. Checking only
  # top-level statements falsely flags a module whose require is co-located with
  # the call inside a function, or lives in the `quote` alongside the call.
  defp has_logger_require?(body) do
    {_, found} =
      Macro.prewalk(body, false, fn
        _node, true ->
          {nil, true}

        {directive, _, [{:__aliases__, _, [:Logger]} | _]}, _acc
        when directive in [:require, :import, :use] ->
          {nil, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp block_to_list({:__block__, _, stmts}), do: stmts
  defp block_to_list(single), do: [single]

  # Extracts the body from a defmodule's keyword argument list.
  defp extract_do_body([{{:__block__, _, [:do]}, body}]), do: body
  defp extract_do_body(_), do: nil

  @directives [:use, :import, :require, :alias]

  defp find_directive_end(statements) do
    statements
    |> Enum.with_index()
    |> Enum.reduce(0, fn {stmt, idx}, last ->
      if directive_like?(stmt), do: idx + 1, else: last
    end)
  end

  defp directive_like?({tag, _, _}) when tag in @directives, do: true
  defp directive_like?({:@, _, [{:moduledoc, _, _}]}), do: true
  defp directive_like?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_missing_require_logger,
      message:
        "Logger macros (info, debug, warning, error, etc.) need " <>
          "`require Logger` in the enclosing module. Without it, the code " <>
          "compiles but crashes at runtime with UndefinedFunctionError.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
