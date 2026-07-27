defmodule Credence.Semantic.FixJasonDecodeErrorMessageField do
  @moduledoc """
  Fixes compile errors caused by LLMs pattern-matching `%Jason.DecodeError{message: msg}`
  when `:message` is not a field on `Jason.DecodeError` (only `:data` exists).

  The compiler emits:

      "unknown key :message for struct Jason.DecodeError"

  The fix replaces the struct pattern with a bare variable and uses
  `Exception.message/1` to extract the message in the clause body:

      # Before (compile error):
      {:error, %Jason.DecodeError{message: msg}} -> "Invalid JSON: \#{msg}"

      # After (compiles correctly):
      {:error, error} -> "Invalid JSON: \#{Exception.message(error)}"
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "unknown key :message for struct Jason.DecodeError"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_jason_decode_error_message_field,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:->, clause_meta, [patterns, body]}, acc ->
            case find_and_fix_clause(patterns, body) do
              {:ok, new_patterns, new_body} ->
                {{:->, clause_meta, [new_patterns, new_body]}, true}

              :error ->
                {{:->, clause_meta, [patterns, body]}, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp find_and_fix_clause(patterns, body) do
    case find_jason_decode_error_struct(patterns) do
      nil ->
        :error

      var_name ->
        new_var = :error
        new_patterns = replace_struct_pattern(patterns, new_var)
        new_body = replace_var_in_body(body, var_name, new_var)
        {:ok, new_patterns, new_body}
    end
  end

  defp find_jason_decode_error_struct(patterns) do
    {_, found} =
      Macro.prewalk(patterns, nil, fn
        {:%, _, [{:__aliases__, _, [:Jason, :DecodeError]}, {:%{}, _, entries}]} = node,
        nil ->
          case find_message_var(entries) do
            {var_name, _meta} -> {node, var_name}
            nil -> {node, nil}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp find_message_var(entries) do
    Enum.find_value(entries, fn
      {{:__block__, _, [:message]}, {var_name, meta, nil}} when is_atom(var_name) ->
        {var_name, meta}

      _ ->
        nil
    end)
  end

  defp replace_struct_pattern(patterns, new_var) do
    Macro.prewalk(patterns, fn
      {:%, meta, [{:__aliases__, _, [:Jason, :DecodeError]}, {:%{}, _, _}]} ->
        {new_var, meta, nil}

      node ->
        node
    end)
  end

  defp replace_var_in_body(body, var_name, new_var) do
    Macro.prewalk(body, fn
      {^var_name, meta, nil} ->
        {{:., [], [{:__aliases__, [], [:Exception]}, :message]}, [],
         [{new_var, meta, nil}]}

      node ->
        node
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
