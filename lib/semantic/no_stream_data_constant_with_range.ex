defmodule Credence.Semantic.NoStreamDataConstantWithRange do
  @moduledoc """
  Repairs the compiler warning when `StreamData.constant/1` is called with
  a Range argument, producing a `%Range{}` struct instead of integers from
  the range.

  LLMs consistently write `StreamData.constant(?a..?z)` intending to generate
  characters, but `constant/1` wraps the value literally — yielding the
  `%Range{}` struct itself rather than individual integers from `?a` to `?z`.

  The fix replaces `StreamData.constant` with `StreamData.member_of`, which
  correctly enumerates elements from the range.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "incompatible types given to StreamData."

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg) and String.contains?(msg, "%Range")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_stream_data_constant_with_range,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {result, changed?} =
          Macro.prewalk(ast, false, fn
            {{:., dot_meta, [{:__aliases__, alias_meta, [:StreamData]}, :constant]}, call_meta,
             [range_arg]},
            _acc ->
              new_node =
                {{:., dot_meta, [{:__aliases__, alias_meta, [:StreamData]}, :member_of]},
                 call_meta, [range_arg]}

              {new_node, true}

            node, acc ->
              {node, acc}
          end)

        if changed?, do: Sourceror.to_string(result), else: source

      _ ->
        source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
