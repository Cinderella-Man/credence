defmodule Credence.Semantic.NoPrivateNamedEtsReadableExternally do
  @moduledoc """
  Fixes the common LLM pattern of creating a named ETS table with `:private`
  access inside a GenServer's `init/1`, then reading it from a public API
  function outside the server callbacks.

  A `:private` named table is only accessible by the owning process. When a
  public function (not a `handle_call`/`handle_cast`/`handle_info` callback)
  calls `:ets.lookup`/`:ets.insert`/etc. on it from a different process, the
  runtime raises `ArgumentError: access rights are insufficient`.

  The compiler emits a type warning because the table name is constructed with
  `String.to_atom(to_string(name))` in binary construction context — the
  dynamic atom type doesn't match the expected binary type.

  The fix changes `:private` to `:protected` in the `:ets.new` options list,
  which allows any process to read from the table while only the owner can
  write — the correct access level for a named table read externally.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # The distinctive substring of the real diagnostic this rule matches.
  @match_text "incompatible types in binary construction"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_text)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_private_named_ets_readable_externally,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {new_ast, changed} =
          Macro.prewalk(ast, false, fn
            # Match :ets.new(name, [..., :private, ...]) calls
            {{:., _, [{:__block__, _, [:ets]}, :new]}, meta, args} = node, acc ->
              case args do
                [name_ast, opts_ast] ->
                  case replace_private_in_opts(opts_ast) do
                    {:ok, new_opts} ->
                      {{{:., [], [{:__block__, [], [:ets]}, :new]}, meta, [name_ast, new_opts]}, true}

                    :error ->
                      {node, acc}
                  end

                _ ->
                  {node, acc}
              end

            node, acc ->
              {node, acc}
          end)

        if changed do
          Sourceror.to_string(new_ast)
        else
          source
        end

      _ ->
        source
    end
  end

  # Replace :private with :protected in an ETS options list AST node.
  defp replace_private_in_opts({:__block__, meta, [list]}) when is_list(list) do
    case do_replace(list) do
      {:ok, new_list} -> {:ok, {:__block__, meta, [new_list]}}
      :error -> :error
    end
  end

  defp replace_private_in_opts(list) when is_list(list) do
    case do_replace(list) do
      {:ok, new_list} -> {:ok, new_list}
      :error -> :error
    end
  end

  defp replace_private_in_opts(_), do: :error

  defp do_replace(list) do
    if Enum.any?(list, &is_private_atom?/1) do
      {:ok, Enum.map(list, fn item -> if is_private_atom?(item), do: protected_atom(item), else: item end)}
    else
      :error
    end
  end

  defp is_private_atom?({:__block__, _, [:private]}), do: true
  defp is_private_atom?(:private), do: true
  defp is_private_atom?(_), do: false

  defp protected_atom({:__block__, meta, [:private]}), do: {:__block__, meta, [:protected]}
  defp protected_atom(:private), do: :protected

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
