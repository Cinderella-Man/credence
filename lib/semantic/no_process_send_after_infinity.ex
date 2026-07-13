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
      {:ok, ast} -> source_has_send_after_issue?(ast)
      _ -> false
    end
  end

  defp source_has_send_after_issue?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        node, acc ->
          {node, acc || contains_send_after_infinity?(node) || contains_send_after_variable_arg?(node)}
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
            patched = Sourceror.patch_string(acc, [patch])
            # Sourceror may leave trailing whitespace on blank lines;
            # strip it to keep output clean.
            strip_trailing_ws_per_line(patched, acc)
          end)
      end
    else
      _ -> source
    end
  end

  # Strip trailing whitespace from lines that the patch introduced,
  # leaving untouched lines byte-for-byte.
  defp strip_trailing_ws_per_line(text, original) do
    original
    |> String.split("\n")
    |> List.myers_difference(String.split(text, "\n"))
    |> Enum.flat_map(fn
      {:eq, lines} -> lines
      {:del, _lines} -> []
      {:ins, lines} ->
        Enum.map(lines, fn line -> if String.trim(line) == "", do: "", else: line end)
    end)
    |> Enum.join("\n")
  end

  # Walk the AST and collect patches for def bodies containing
  # Process.send_after(_, _, :infinity) or Process.send_after(_, _, var).
  defp collect_patches(ast, _source) do
    {_, patches} =
      Macro.prewalk(ast, [], fn
        {:def, _meta, [head, kw_list]} = node, acc when is_list(kw_list) ->
          case find_do_body_and_range(kw_list) do
            {:ok, body, range} ->
              cond do
                contains_send_after_infinity?(body) ->
                  # Literal :infinity — replace entire body with :ok
                  patch = %{range: range, change: replacement()}
                  {node, [patch | acc]}

                contains_send_after_variable_arg?(body) ->
                  # Variable arg — split into guarded def + catch-all clause
                  case build_guard_patch(node, head, body) do
                    {:ok, patch} -> {node, [patch | acc]}
                    :error -> {node, acc}
                  end

                true ->
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

  # Build a patch that adds a `when` guard to the def head and appends a
  # catch-all clause for Process.send_after with a variable third argument.
  defp build_guard_patch(def_node, head, body) do
    with %Sourceror.Range{} = def_range <- Sourceror.get_range(def_node),
         third_arg when not is_nil(third_arg) <- find_variable_third_arg(body) do
      {func_name, _head_meta, params} = head

      # Build the guard expression: third_arg != :infinity
      guard = {:!=, [], [third_arg, {:__block__, [], [:infinity]}]}

      # Build the guarded head: original_head when guard
      guarded_head = {:when, [], [head, guard]}

      # Build the guarded def with the original body
      guarded_def = {:def, [], [guarded_head, [do: body]]}

      # Render the guarded def as a string
      guarded_str = Sourceror.to_string(guarded_def) |> String.trim_trailing("\n")

      # Build the catch-all as a plain string: def func(_param1, _param2), do: :ok
      func_name_str = Atom.to_string(func_name)

      catch_all_params_str =
        Enum.map_join(params, ", ", fn
          {name, _, nil} when is_atom(name) -> "_" <> Atom.to_string(name)
          _ -> "_"
        end)

      catch_all_str = "def #{func_name_str}(#{catch_all_params_str}), do: :ok"

      replacement = guarded_str <> "\n\n" <> catch_all_str

      {:ok, %{range: def_range, change: replacement}}
    else
      _ -> :error
    end
  end

  # Find the first Process.send_after call in the body with a variable
  # (non-literal) third argument. Returns the third arg AST node, or nil.
  defp find_variable_third_arg(body) do
    {_ast, result} =
      Macro.prewalk(body, nil, fn
        {{:., _, [{:__aliases__, _, [:Process]}, :send_after]}, _, [_, _, third_arg]} = node,
        nil ->
          if not literal?(third_arg), do: {node, third_arg}, else: {node, nil}

        node, acc ->
          {node, acc}
      end)

    result
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

  # Check if an AST node contains Process.send_after(_, _, var) where the
  # third argument is not a literal (i.e. it could be :infinity at runtime).
  defp contains_send_after_variable_arg?(
         {{:., _, [{:__aliases__, _, [:Process]}, :send_after]}, _,
          [_, _, third_arg]}
       ),
       do: not literal?(third_arg)

  defp contains_send_after_variable_arg?({:__block__, _, stmts}) when is_list(stmts) do
    Enum.any?(stmts, &contains_send_after_variable_arg?/1)
  end

  defp contains_send_after_variable_arg?({:=, _, [_, rhs]}) do
    contains_send_after_variable_arg?(rhs)
  end

  defp contains_send_after_variable_arg?(_), do: false

  # A literal is an atom, number, or string wrapped in {:__block__, meta, [value]}.
  defp literal?({:__block__, _, [v]}) when is_atom(v) or is_number(v) or is_binary(v), do: true
  defp literal?(_), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
