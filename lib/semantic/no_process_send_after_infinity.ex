defmodule Credence.Semantic.NoProcessSendAfterInfinity do
  @moduledoc """
  Fixes calls to `Process.send_after/3` where the timeout is `:infinity`.

  LLMs routinely pass `:infinity` to `Process.send_after` (often from a
  configurable interval option) which always crashes at runtime since
  `:erlang.send_after/3` requires an integer. Removing the call is the only
  safe fix — the function body is replaced with `:ok`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "redefining module"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_process_send_after_infinity,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @doc false
  def should_report?(_diagnostic, source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> source_has_send_after_infinity?(ast)
      _ -> false
    end
  end

  defp source_has_send_after_infinity?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        node, acc -> {node, acc || contains_send_after_infinity?(node)}
      end)

    found
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      patches = collect_patches(ast, source)

      case patches do
        [] ->
          source

        _ ->
          Enum.reduce(patches, source, fn patch, acc ->
            Sourceror.patch_string(acc, [patch])
          end)
      end
    else
      _ -> source
    end
  end

  # Walk the AST and collect patches for def bodies containing
  # Process.send_after(_, _, :infinity).
  defp collect_patches(ast, _source) do
    {_, patches} =
      Macro.prewalk(ast, [], fn
        {:def, _meta, [_head, kw_list]} = node, acc when is_list(kw_list) ->
          case find_do_body_and_range(kw_list) do
            {:ok, body, range} ->
              if contains_send_after_infinity?(body) do
                patch = %{range: range, change: replacement()}
                {node, [patch | acc]}
              else
                {node, acc}
              end

            :error ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    patches
  end

  # Find the do body AST node and its source range.
  defp find_do_body_and_range(kw_list) do
    case Enum.find(kw_list, fn
           {{:__block__, _, [:do]}, _} -> true
           _ -> false
         end) do
      {{:__block__, _, [:do]}, body} ->
        case Sourceror.get_range(body) do
          %Sourceror.Range{} = range -> {:ok, body, range}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # Build the replacement string: comment + :ok
  # Sourceror.patch_string re-indents to match the range's start column,
  # so we don't include leading whitespace here.
  defp replacement do
    "# :infinity is not a valid argument for :erlang.send_after/3;\n" <>
      "# skip scheduling to avoid runtime crash.\n" <>
      ":ok"
  end

  # Check if an AST node contains Process.send_after(_, _, :infinity).
  # In Sourceror AST, :infinity is wrapped as {:__block__, _, [:infinity]}.
  defp contains_send_after_infinity?(
         {{:., _, [{:__aliases__, _, [:Process]}, :send_after]}, _,
          [_, _, {:__block__, _, [:infinity]}]}
       ),
       do: true

  defp contains_send_after_infinity?({:__block__, _, stmts}) when is_list(stmts) do
    Enum.any?(stmts, &contains_send_after_infinity?/1)
  end

  defp contains_send_after_infinity?({:=, _, [_, rhs]}) do
    contains_send_after_infinity?(rhs)
  end

  defp contains_send_after_infinity?(_), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
