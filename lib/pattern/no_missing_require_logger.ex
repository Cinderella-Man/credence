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
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:defmodule, meta, [_name, [{:do, body}]]} = node, acc ->
          statements = block_to_list(body)

          if has_logger_macro_call?(body) and not has_logger_require?(statements) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        if needs_fix?(ast) do
          ast
          |> Macro.prewalk(&maybe_fix_module/1)
          |> Sourceror.to_string()
        else
          source
        end

      {:error, _} ->
        source
    end
  end

  # ── Detection ─────────────────────────────────────────────────

  # Walks the body looking for Logger.macro_name(...) calls.
  # Stops at nested defmodule nodes so inner modules don't get
  # attributed to the outer module.
  defp has_logger_macro_call?(body) do
    {_, found} =
      Macro.prewalk(body, false, fn
        _node, true ->
          {nil, true}

        # Replace nested defmodule with an atom to prevent descent
        {:defmodule, _, _}, acc ->
          {:__skip__, acc}

        {{:., _, [{:__aliases__, _, [:Logger]}, func]}, _, _}, _acc
        when func in @logger_macros ->
          {nil, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Checks whether any top-level statement in the module body is
  # `require Logger`, `import Logger`, or `use Logger`.
  defp has_logger_require?(statements) do
    Enum.any?(statements, fn
      {:require, _, [{:__aliases__, _, [:Logger]} | _]} -> true
      {:import, _, [{:__aliases__, _, [:Logger]} | _]} -> true
      {:use, _, [{:__aliases__, _, [:Logger]} | _]} -> true
      _ -> false
    end)
  end

  defp block_to_list({:__block__, _, stmts}), do: stmts
  defp block_to_list(single), do: [single]

  # ── Fix ───────────────────────────────────────────────────────

  defp needs_fix?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        _node, true ->
          {nil, true}

        {:defmodule, _, [_name, kw]} = node, false ->
          case extract_do_body(kw) do
            nil ->
              {node, false}

            body ->
              statements = block_to_list(body)

              if has_logger_macro_call?(body) and not has_logger_require?(statements) do
                {node, true}
              else
                {node, false}
              end
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp maybe_fix_module({:defmodule, meta, [name, kw]}) do
    case extract_do_body(kw) do
      nil ->
        {:defmodule, meta, [name, kw]}

      body ->
        statements = block_to_list(body)

        if has_logger_macro_call?(body) and not has_logger_require?(statements) do
          new_statements = insert_require(statements)
          new_body = {:__block__, [], new_statements}
          {:defmodule, meta, [name, replace_do_body(kw, new_body)]}
        else
          {:defmodule, meta, [name, kw]}
        end
    end
  end

  defp maybe_fix_module(node), do: node

  # Extracts the body from a defmodule's keyword argument list,
  # handling both standard and Sourceror AST forms.
  defp extract_do_body([{:do, body}]), do: body
  defp extract_do_body([{{:__block__, _, [:do]}, body}]), do: body
  defp extract_do_body(_), do: nil

  defp replace_do_body([{:do, _old}], new_body),
    do: [{:do, new_body}]

  defp replace_do_body([{{:__block__, m, [:do]}, _old}], new_body),
    do: [{{:__block__, m, [:do]}, new_body}]

  defp replace_do_body(other, _new_body), do: other

  # Inserts `require Logger` after the last directive-like statement
  # at the top of the module body.
  defp insert_require(statements) do
    require_ast = Code.string_to_quoted!("require Logger")
    insert_idx = find_directive_end(statements)
    List.insert_at(statements, insert_idx, require_ast)
  end

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

  # ── Issue ─────────────────────────────────────────────────────

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
