defmodule Credence.Semantic.MissingUseExUnitCase do
  @moduledoc """
  Fixes test modules that are missing `use ExUnit.Case`.

  ExUnit's `test/2`, `describe/2`, `setup/1`, etc. are macros provided
  by `use ExUnit.Case`. Without it, the module fails to compile:

      error: undefined function describe/2 (there is no such import)

  LLMs sometimes omit the `use` line because Python's `unittest` and
  `pytest` don't require an equivalent setup.

  ## Auto-fix

  Inserts `use ExUnit.Case` at the top of the module body, after any
  existing `@moduledoc`, `use`, `import`, `require`, or `alias` directives.
  """

  @behaviour Credence.Semantic.Rule
  alias Credence.Issue

  # ── Rule callbacks ────────────────────────────────────────────

  @impl true
  def priority, do: 100

  @impl true
  def match?(%{severity: :error, message: message}) do
    String.contains?(message, "undefined function test/") or
      String.contains?(message, "undefined function describe/") or
      String.contains?(message, "undefined function setup/")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :missing_use_exunit_case,
      message: "Test module is missing `use ExUnit.Case`.",
      meta: %{line: extract_line(diagnostic.position)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        if needs_fix?(ast) do
          ast
          |> Macro.prewalk(&maybe_insert_use/1)
          |> Sourceror.to_string()
        else
          source
        end

      {:error, _} ->
        source
    end
  end

  # ── Detection ─────────────────────────────────────────────────

  defp needs_fix?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        _node, true ->
          {nil, true}

        {:defmodule, _, [_name, kw]}, false ->
          case extract_do_body(kw) do
            nil ->
              {:__skip__, false}

            body ->
              statements = block_to_list(body)

              if has_exunit_calls?(body) and not has_use_exunit?(statements) do
                {:__skip__, true}
              else
                {:__skip__, false}
              end
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Checks top-level statements of the module body for ExUnit macro
  # calls (test, describe, setup). Only checks direct children — these
  # macros are always at the module's top level. This avoids false
  # positives from `def test(value)` where {:test, _, _} appears as
  # a function head inside {:def, _, _}.
  defp has_exunit_calls?(body) do
    statements = block_to_list(body)

    Enum.any?(statements, fn
      {:test, _, args} when is_list(args) -> true
      {:describe, _, args} when is_list(args) -> true
      {:setup, _, args} when is_list(args) -> true
      {:setup_all, _, args} when is_list(args) -> true
      _ -> false
    end)
  end

  defp has_use_exunit?(statements) do
    Enum.any?(statements, fn
      {:use, _, [{:__aliases__, _, [:ExUnit, :Case]} | _]} -> true
      _ -> false
    end)
  end

  # ── Fix ───────────────────────────────────────────────────────

  defp maybe_insert_use({:defmodule, meta, [name, kw]}) do
    case extract_do_body(kw) do
      nil ->
        {:defmodule, meta, [name, kw]}

      body ->
        statements = block_to_list(body)

        if has_exunit_calls?(body) and not has_use_exunit?(statements) do
          use_ast = Code.string_to_quoted!("use ExUnit.Case")
          insert_idx = find_insert_position(statements)
          new_statements = List.insert_at(statements, insert_idx, use_ast)
          new_body = {:__block__, [], new_statements}
          {:defmodule, meta, [name, replace_do_body(kw, new_body)]}
        else
          {:defmodule, meta, [name, kw]}
        end
    end
  end

  defp maybe_insert_use(node), do: node

  # ── AST helpers ───────────────────────────────────────────────

  defp extract_line({line, _col}), do: line
  defp extract_line(line) when is_integer(line), do: line

  defp block_to_list({:__block__, _, stmts}), do: stmts
  defp block_to_list(single), do: [single]

  defp extract_do_body([{:do, body}]), do: body
  defp extract_do_body([{{:__block__, _, [:do]}, body}]), do: body
  defp extract_do_body(_), do: nil

  defp replace_do_body([{:do, _}], new), do: [{:do, new}]
  defp replace_do_body([{{:__block__, m, [:do]}, _}], new), do: [{{:__block__, m, [:do]}, new}]
  defp replace_do_body(other, _), do: other

  @directives [:use, :import, :require, :alias]

  defp find_insert_position(statements) do
    statements
    |> Enum.with_index()
    |> Enum.reduce(0, fn {stmt, idx}, last ->
      if directive_like?(stmt), do: idx + 1, else: last
    end)
  end

  defp directive_like?({tag, _, _}) when tag in @directives, do: true
  defp directive_like?({:@, _, [{:moduledoc, _, _}]}), do: true
  defp directive_like?(_), do: false
end
