defmodule Credence.Semantic.NoStructUpdateOnUntypedVariable do
  @moduledoc """
  Fixes `undefined variable` errors when an LLM uses a bare variable in a
  struct update (`%__MODULE__{var | ...}`) without declaring it as a typed
  function parameter.

  LLMs commonly write:

      def execute(context, action_fn) do
        %__MODULE__{context | steps: context.steps}
      end

  The compiler emits `undefined variable "context"` because `context` lacks
  a struct type annotation. The fix adds `%__MODULE__{} =` to the parameter:

      def execute(%__MODULE__{} = context, action_fn) do
        %__MODULE__{context | steps: context.steps}
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "undefined variable"

  @impl true
  def match?(%{severity: :error, message: msg, file: file} = diagnostic)
      when is_binary(msg) and is_binary(file) do
    String.contains?(msg, @match_msg) and
      source_has_struct_update_on_untyped_var?(diagnostic)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_struct_update_on_untyped_variable,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    var_name = extract_var_name(msg)

    with true <- is_binary(var_name) and var_name != "",
         {:ok, ast} <- Sourceror.parse_string(source) do
      var_atom = String.to_atom(var_name)

      result =
        Macro.prewalk(ast, fn
          {:def, meta, [{:when, when_meta, [fun_head, guard]}, body]} = node ->
            if struct_update_with_var?(body, var_atom) do
              case try_fix_fun_head(fun_head, var_atom) do
                {:ok, new_head} -> {:def, meta, [{:when, when_meta, [new_head, guard]}, body]}
                :error -> node
              end
            else
              node
            end

          {:def, meta, [fun_head, body]} = node ->
            if struct_update_with_var?(body, var_atom) do
              case try_fix_fun_head(fun_head, var_atom) do
                {:ok, new_head} -> {:def, meta, [new_head, body]}
                :error -> node
              end
            else
              node
            end

          {:defp, meta, [{:when, when_meta, [fun_head, guard]}, body]} = node ->
            if struct_update_with_var?(body, var_atom) do
              case try_fix_fun_head(fun_head, var_atom) do
                {:ok, new_head} -> {:defp, meta, [{:when, when_meta, [new_head, guard]}, body]}
                :error -> node
              end
            else
              node
            end

          {:defp, meta, [fun_head, body]} = node ->
            if struct_update_with_var?(body, var_atom) do
              case try_fix_fun_head(fun_head, var_atom) do
                {:ok, new_head} -> {:defp, meta, [new_head, body]}
                :error -> node
              end
            else
              node
            end

          node ->
            node
        end)

      Sourceror.to_string(result)
    else
      _ -> source
    end
  end

  # Check that the source file contains a def/defp where `var_atom` is a bare
  # function parameter AND the body uses `%__MODULE__{var | ...}`.
  defp source_has_struct_update_on_untyped_var?(%{message: msg, file: file}) do
    with var_name when is_binary(var_name) <- extract_var_name(msg),
         true <- File.exists?(file),
         {:ok, source} <- File.read(file),
         {:ok, ast} <- Sourceror.parse_string(source) do
      var_atom = String.to_atom(var_name)
      has_def_with_struct_update?(ast, var_atom)
    else
      _ -> false
    end
  end

  defp has_def_with_struct_update?(ast, var_atom) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:def, _, [{:when, _, [fun_head, _]}, body]} = node, acc ->
          if var_in_params?(fun_head, var_atom) and struct_update_with_var?(body, var_atom) do
            {node, true}
          else
            {node, acc}
          end

        {:def, _, [fun_head, body]} = node, acc ->
          if var_in_params?(fun_head, var_atom) and struct_update_with_var?(body, var_atom) do
            {node, true}
          else
            {node, acc}
          end

        {:defp, _, [{:when, _, [fun_head, _]}, body]} = node, acc ->
          if var_in_params?(fun_head, var_atom) and struct_update_with_var?(body, var_atom) do
            {node, true}
          else
            {node, acc}
          end

        {:defp, _, [fun_head, body]} = node, acc ->
          if var_in_params?(fun_head, var_atom) and struct_update_with_var?(body, var_atom) do
            {node, true}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  # True when `var_atom` is a bare (untyped) parameter in the function head.
  defp var_in_params?({_, _, params}, var_atom) when is_list(params) do
    Enum.any?(params, fn
      {^var_atom, _, nil} -> true
      _ -> false
    end)
  end

  defp var_in_params?(_, _), do: false

  # True when `ast` contains `%__MODULE__{var_atom | ...}`.
  defp struct_update_with_var?(ast, var_atom) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:%, _, [{:__MODULE__, _, _}, {:%{}, _, [{:|, _, [{var, _, nil} | _]}]}]} = node, _acc
        when var == var_atom ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp try_fix_fun_head({fn_name, fn_meta, params}, var_atom) when is_list(params) do
    # Skip if the variable is already typed with %__MODULE__{} =
    already_typed? =
      Enum.any?(params, fn
        {:=, _, [{:%, _, [{:__MODULE__, _, _}, _]}, {^var_atom, _, _}]} -> true
        _ -> false
      end)

    if already_typed? do
      :error
    else
      case Enum.find_index(params, fn
             {^var_atom, _, nil} -> true
             _ -> false
           end) do
        nil ->
          :error

        idx ->
          new_params =
            List.update_at(params, idx, fn {var, meta, nil} ->
              struct_pattern = {:%, [], [{:__MODULE__, [], nil}, {:%{}, [], []}]}
              {:=, [], [struct_pattern, {var, meta, nil}]}
            end)

          {:ok, {fn_name, fn_meta, new_params}}
      end
    end
  end

  defp try_fix_fun_head(_, _), do: :error

  defp extract_var_name(msg) do
    case Regex.run(~r/undefined variable "(\w+)"/, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
