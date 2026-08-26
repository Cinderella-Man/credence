defmodule Credence.Semantic.NoModuleLevelInit do
  @moduledoc """
  Fixes the Elixir compiler error when a bare `init()` call appears at
  module top-level (Python-style), causing "undefined function init/0".

  LLMs frequently write:

      defmodule FactoryNMLI do
        def init do
          # initialization logic
        end
        init()
      end

  The bare `init()` call executes at compile time before the function is
  defined, producing:

      ** (CompileError) ... undefined function init/0

  The fix removes the bare `init()` call and adds an `@on_load` wrapper as the
  first expression in the module body. The wrapper preserves `init/0`'s return
  value for ordinary callers while satisfying the callback's `:ok` contract:

      defmodule FactoryNMLI do
        @on_load :__credence_on_load__

        def __credence_on_load__ do
          init()
          :ok
        end

        def init do
          # initialization logic
        end
      end

  ## Ordering

  `Credence.Semantic.UndefinedFunction` (500) is the catch-all for
  `undefined function …` and claims this rule's diagnostic too. Semantic
  dispatch is `Enum.find` — first match wins, no fall-through — so at equal
  priority the winner would have been decided by `NoModuleLevelInit` sorting
  before `UndefinedFunction` alphabetically. The catch-all therefore declares
  501 so that every specific rule beats it by declaration rather than by
  spelling. This rule owns the `init/0` diagnostic because the repair is
  `@on_load`, not a renamed call.

  ## Bad

      defmodule FactoryNMLI do
        def init do
          :ok
        end

        init()
        init()
      end

  ## Good

      defmodule FactoryNMLI do
        @on_load :__credence_on_load__

        def __credence_on_load__ do
          init()
          :ok
        end

        def init do
          :ok
        end

      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue
  alias Credence.SourceMask

  @match_message "undefined function init/0"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_message)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_module_level_init,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, call_lines, dm_line} <- find_bare_init_info(ast) do
      call_counts = Enum.frequencies(call_lines)

      lines =
        source
        |> SourceMask.lines()
        |> Enum.with_index(1)
        |> Enum.map(fn {{line, shadow}, line_no} ->
          remove_bare_init_calls(line, shadow, Map.get(call_counts, line_no, 0))
        end)
        |> Enum.reject(&is_nil/1)

      callback = [
        "  @on_load :__credence_on_load__",
        "",
        "  def __credence_on_load__ do",
        "    init()",
        "    :ok",
        "  end",
        ""
      ]

      lines = List.insert_at(lines, dm_line, callback) |> List.flatten()

      Enum.join(lines, "\n")
    else
      _ -> source
    end
  end

  # Walk AST to find a defmodule that has bare init() calls AND def init
  defp find_bare_init_info({:defmodule, dm_meta, [_alias, [{{:__block__, _, [:do]}, body}]]}) do
    children =
      case body do
        {:__block__, _, c} -> c
        single -> [single]
      end

    bare_calls = Enum.filter(children, &bare_init_call?/1)

    if bare_calls != [] and has_def_init?(children) do
      call_lines = Enum.map(bare_calls, &get_line/1)
      dm_line = Keyword.get(dm_meta, :line, 1)
      {:ok, call_lines, dm_line}
    else
      nil
    end
  end

  defp find_bare_init_info({_, _, children}) when is_list(children) do
    Enum.find_value(children, &find_bare_init_info/1)
  end

  defp find_bare_init_info(_), do: nil

  # A bare init() call: {:init, meta, []}
  defp bare_init_call?({:init, meta, []}) when is_list(meta), do: true
  defp bare_init_call?(_), do: false

  # Check if def init exists in the module body
  defp has_def_init?(children) do
    Enum.any?(children, fn
      {:def, _, [{:init, _, args}, _]} when args in [nil, []] -> true
      _ -> false
    end)
  end

  defp get_line({_, meta, _}) when is_list(meta), do: Keyword.get(meta, :line, 1)
  defp get_line(_), do: 1

  defp remove_bare_init_calls(line, _shadow, 0), do: line

  defp remove_bare_init_calls(line, _shadow, count) do
    pattern = ~r/\binit[\t ]*\([\t ]*\)(?:[\t ]*;[\t ]*)?/

    edited =
      Enum.reduce(1..count, line, fn _, current ->
        [{_, current_shadow}] = SourceMask.lines(current)
        SourceMask.replace_code(current, current_shadow, pattern, "", global: false)
      end)

    if String.trim(edited) == "", do: nil, else: edited
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
