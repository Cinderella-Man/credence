defmodule Credence.Semantic.NoModuleLevelInit do
  @moduledoc """
  Fixes the Elixir compiler error when a bare `init()` call appears at
  module top-level (Python-style), causing "undefined function init/0".

  LLMs frequently write:

      defmodule Factory do
        def init do
          # initialization logic
        end
        init()
      end

  The bare `init()` call executes at compile time before the function is
  defined, producing:

      ** (CompileError) ... undefined function init/0

  The fix removes the bare `init()` call and adds `@on_load :init` as the
  first expression in the module body — the idiomatic Elixir callback:

      defmodule Factory do
        @on_load :init

        def init do
          # initialization logic
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "undefined function"
  @match_fn "init/0"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_prefix) and String.contains?(msg, @match_fn)
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
      lines = String.split(source, "\n")

      # Remove bare init() lines (descending to preserve indices)
      lines =
        Enum.reduce(Enum.sort(call_lines, :desc), lines, fn line_no, acc ->
          List.replace_at(acc, line_no - 1, nil)
        end)
        |> Enum.reject(&is_nil/1)

      # Insert @on_load :init + blank line after defmodule ... do
      lines =
        lines
        |> List.insert_at(dm_line, "  @on_load :init")
        |> List.insert_at(dm_line + 1, "")

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
      {:def, _, [{:init, _, nil}, _]} -> true
      _ -> false
    end)
  end

  defp get_line({_, meta, _}) when is_list(meta), do: Keyword.get(meta, :line, 1)
  defp get_line(_), do: 1

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
