defmodule Credence.Semantic.NoHallucinatedEtsKeytypeOption do
  @moduledoc """
  Repairs the LLM hallucination of `keytype: :term` in `:ets.new/2` options.

  LLMs translating Python dict key types frequently hallucinate
  `keytype: :term` as an option to `:ets.new/2`. This option does not
  exist in Erlang's ETS and produces an `ArgumentError` at runtime:

      errors were found at the given arguments:
        * 2nd argument: invalid options

  The fix removes the `keytype: :term` keyword pair from the options
  list, leaving all other options intact.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "2nd argument: invalid options"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_ets_keytype_option,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., _dot_meta, [{:__block__, _, [:ets]}, :new]}, _call_meta, args} = node, acc ->
            case remove_keytype_from_args(args) do
              {:ok, new_args} -> {put_elem(node, 2, new_args), true}
              :error -> {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # The options list is the last arg, wrapped in {:__block__, meta, [list]}
  defp remove_keytype_from_args(args) when is_list(args) do
    case List.last(args) do
      {:__block__, meta, [opts]} when is_list(opts) ->
        case do_remove_keytype(opts) do
          {:ok, new_opts} ->
            new_last = {:__block__, meta, [new_opts]}
            {:ok, List.replace_at(args, length(args) - 1, new_last)}

          :error ->
            :error
        end

      _ ->
        :error
    end
  end

  defp remove_keytype_from_args(_), do: :error

  defp do_remove_keytype(opts) when is_list(opts) do
    case Enum.find_index(opts, &keytype_option?/1) do
      nil -> :error
      idx -> {:ok, List.delete_at(opts, idx)}
    end
  end

  # Match a keyword pair: keytype: :term
  defp keytype_option?(
         {{:__block__, meta, [:keytype]}, {:__block__, _, [:term]}}
       )
       when is_list(meta) do
    Keyword.get(meta, :format) == :keyword
  end

  defp keytype_option?(_), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
