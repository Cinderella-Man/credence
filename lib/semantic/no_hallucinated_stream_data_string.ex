defmodule Credence.Semantic.NoHallucinatedStreamDataString do
  @moduledoc """
  Fixes compile errors caused by LLM-hallucinated `StreamData.alpha_string/0`
  and `StreamData.string_of_length/2`.

  LLMs repeatedly hallucinate these functions; neither exists in StreamData.
  The compiler emits:

      "function StreamData.alpha_string/0 is undefined or private"
      "function StreamData.string_of_length/2 is undefined or private"

  The existing `undefined_function` rule matches the diagnostic but returns
  identical source (no fix), causing repeated compile failures.

  The fix:
    1. `StreamData.alpha_string()` → `StreamData.string(:alphanumeric)`
    2. `StreamData.string_of_length(lo..hi, type)` →
       `StreamData.string(type, min_length: lo, max_length: hi)`
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, "alpha_string") or String.contains?(msg, "string_of_length")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_stream_data_string,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {new_ast, changed?} =
          Macro.prewalk(ast, false, fn
            {{:., _dot_meta, [{:__aliases__, _mod_meta, [:StreamData]}, :alpha_string]},
             _call_meta, _args} = node,
            _acc ->
              {transform_alpha_string(node), true}

            {{:., _dot_meta, [{:__aliases__, _mod_meta, [:StreamData]}, :string_of_length]},
             _call_meta, [range_arg, type_arg]} = node,
            _acc ->
              case transform_string_of_length(node, range_arg, type_arg) do
                {:ok, new_node} -> {new_node, true}
                :error -> {node, false}
              end

            node, acc ->
              {node, acc}
          end)

        if changed?, do: Sourceror.to_string(new_ast), else: source

      _ ->
        source
    end
  end

  defp transform_alpha_string({{:., dot_meta, [mod_alias, :alpha_string]}, call_meta, _args}) do
    alphanumeric = {:__block__, [line: dot_meta[:line]], [:alphanumeric]}
    {{:., dot_meta, [mod_alias, :string]}, call_meta, [alphanumeric]}
  end

  defp transform_string_of_length(
         {{:., dot_meta, [mod_alias, :string_of_length]}, call_meta, _args},
         range_arg,
         type_arg
       ) do
    case range_arg do
      {:.., _meta, [lo, hi]} ->
        new_args = [
          type_arg,
          [
            {{:__block__, [format: :keyword], [:min_length]}, lo},
            {{:__block__, [format: :keyword], [:max_length]}, hi}
          ]
        ]

        {:ok, {{:., dot_meta, [mod_alias, :string]}, call_meta, new_args}}

      _ ->
        :error
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
