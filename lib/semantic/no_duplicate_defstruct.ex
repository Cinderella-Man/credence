defmodule Credence.Semantic.NoDuplicateDefstruct do
  @moduledoc """
  Fixes the compiler error when `defstruct` is called more than once in a module.

  The compiler emits:

      "defstruct has already been called for X, defstruct can only be called once per module"

  LLMs iterate on struct definitions and emit multiple `defstruct` calls in the
  same module. The fix keeps only the last `defstruct` call, removing all
  preceding ones.
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
      case ast do
        {:defmodule, m_meta,
         [alias_node, [{{:__block__, do_meta, [:do]}, {:__block__, b_meta, body}}]]} ->
          defstruct_nodes =
            Enum.filter(body, fn
              {:defstruct, _, _} -> true
              _ -> false
            end)

          if length(defstruct_nodes) <= 1 do
            source
          else
            last = List.last(defstruct_nodes)

            cleaned =
              Enum.reject(body, fn node ->
                node != last and match?({:defstruct, _, _}, node)
              end)

            new_body = {:__block__, b_meta, cleaned}

            new_ast =
              {:defmodule, m_meta, [alias_node, [{{:__block__, do_meta, [:do]}, new_body}]]}

            Sourceror.to_string(new_ast)
          end

        _ ->
          source
      end
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
