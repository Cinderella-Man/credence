defmodule Credence.Semantic.NoDuplicateDefstruct do
  @moduledoc """
  Fixes the compiler error when `defstruct` is called more than once in a module.

  The compiler emits:

      "defstruct has already been called for X, defstruct can only be called once per module"

  LLMs iterate on struct definitions and emit multiple `defstruct` calls in the
  same module. The fix keeps only the last `defstruct` call, removing all
  preceding ones.

  ## Bad

      defmodule FooNDD do
        defstruct [:a]
        defstruct name: nil
        defstruct name: nil, age: 0
      end

  ## Good

      defmodule FooNDD do
        defstruct name: nil, age: 0
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "defstruct has already been called for"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_duplicate_defstruct,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      patches =
        ast
        |> module_nodes()
        |> Enum.flat_map(fn module ->
          module
          |> defstructs_in_module()
          |> Enum.drop(-1)
          |> Enum.map(&remove_statement_patch/1)
        end)

      if patches == [], do: source, else: Sourceror.patch_string(source, patches)
    else
      _ -> source
    end
  end

  defp module_nodes({:quote, _, _}), do: []

  defp module_nodes({:defmodule, _, args} = node) do
    [node | module_nodes(args)]
  end

  defp module_nodes(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.flat_map(&module_nodes/1)
  end

  defp module_nodes(list) when is_list(list), do: Enum.flat_map(list, &module_nodes/1)
  defp module_nodes(_), do: []

  defp defstructs_in_module({:defmodule, _, [_name, body]}), do: collect_defstructs(body)

  defp collect_defstructs({:defmodule, _, _}), do: []
  defp collect_defstructs({:quote, _, _}), do: []
  defp collect_defstructs({:defstruct, _, _} = node), do: [node]

  defp collect_defstructs(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.flat_map(&collect_defstructs/1)
  end

  defp collect_defstructs(list) when is_list(list), do: Enum.flat_map(list, &collect_defstructs/1)
  defp collect_defstructs(_), do: []

  defp remove_statement_patch(node) do
    %{end: end_position} = Sourceror.get_range(node)

    %{
      range: %{
        start: [line: Sourceror.get_start_position(node)[:line], column: 1],
        end: [line: end_position[:line] + 1, column: 1]
      },
      change: ""
    }
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
