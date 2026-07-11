defmodule Credence.Semantic.FixUndefinedStructInPattern do
  @moduledoc """
  Fixes compile errors caused by undefined struct literals in catch clause bodies.

  LLMs frequently wrap caught values in custom exception structs like:

      catch
        :exit, reason -> {:error, {:exception, %Exit{reason: reason}}}
        :throw, value -> {:error, {:exception, %ThrowError{value: value}}}

  When these structs are undefined (or defined later as nested modules), the
  compiler emits:

      "Exit.__struct__/1 is undefined, cannot expand struct Exit"

  The fix replaces the undefined struct literal with just the variable it wraps,
  so the catch clause compiles and captures the value directly:

      %Exit{reason: reason}       →  reason
      %ThrowError{value: value}   →  value
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "__struct__/1 is undefined"

  @impl true
  def match?(%{severity: :error, message: msg, file: file} = diagnostic)
      when is_binary(msg) and is_binary(file) do
    String.contains?(msg, @match_msg) and
      struct_in_catch_clause?(diagnostic)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_undefined_struct_in_pattern,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    struct_name = extract_struct_name(msg)

    with true <- not is_nil(struct_name),
         {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:try, try_meta, [clauses]} = node, acc when is_list(clauses) ->
            {new_clauses, clauses_changed} = fix_try_catch_bodies(clauses, struct_name)

            if clauses_changed do
              {{:try, try_meta, [new_clauses]}, true}
            else
              {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # --- match? helpers --------------------------------------------------------

  defp struct_in_catch_clause?(%{message: msg, file: file}) do
    struct_name = extract_struct_name(msg)

    with true <- not is_nil(struct_name),
         {:ok, source} <- File.read(file),
         {:ok, ast} <- Sourceror.parse_string(source) do
      ast_has_catch_struct?(ast, struct_name)
    else
      _ -> false
    end
  end

  defp ast_has_catch_struct?(ast, struct_name) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:try, _, [clauses]} = node, false when is_list(clauses) ->
          found =
            Enum.any?(clauses, fn
              {{:__block__, _, [:catch]}, catch_clauses} ->
                catch_body_has_struct?(catch_clauses, struct_name)

              _ ->
                false
            end)

          {node, found}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp catch_body_has_struct?(catch_clauses, struct_name) do
    Enum.any?(catch_clauses, fn
      {:->, _, [_patterns, body]} ->
        body_has_struct?(body, struct_name)

      _ ->
        false
    end)
  end

  defp body_has_struct?(body, struct_name) do
    {_, found} =
      Macro.prewalk(body, false, fn
        {:%, _, [{:__aliases__, _, parts}, {:%{}, _, _entries}]} = node, false ->
          if Module.concat(parts) == struct_name do
            {node, true}
          else
            {node, false}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  # --- fix helpers ------------------------------------------------------------

  defp fix_try_catch_bodies(clauses, struct_name) do
    Enum.map_reduce(clauses, false, fn
      {{:__block__, catch_meta, [:catch]}, catch_clauses}, acc ->
        {new_catch_clauses, catch_changed} =
          Enum.map_reduce(catch_clauses, false, fn
            {:->, arrow_meta, [patterns, body]}, clause_acc ->
              {new_body, body_changed} = replace_struct_in_body(body, struct_name)

              if body_changed do
                {{:->, arrow_meta, [patterns, new_body]}, true}
              else
                {{:->, arrow_meta, [patterns, body]}, clause_acc}
              end

            other, clause_acc ->
              {other, clause_acc}
          end)

        if catch_changed do
          {{{:__block__, catch_meta, [:catch]}, new_catch_clauses}, true}
        else
          {{{:__block__, catch_meta, [:catch]}, catch_clauses}, acc}
        end

      other, acc ->
        {other, acc}
    end)
  end

  defp replace_struct_in_body(body, struct_name) do
    Macro.prewalk(body, false, fn
      {:%, _meta, [{:__aliases__, _, parts}, {:%{}, _, entries}]} = node, acc ->
        if Module.concat(parts) == struct_name do
          case single_var_value(entries) do
            {:ok, var_ast} -> {var_ast, true}
            :error -> {node, acc}
          end
        else
          {node, acc}
        end

      node, acc ->
        {node, acc}
    end)
  end

  # A struct with exactly one field whose value is a plain variable.
  defp single_var_value([{_key, {var_name, var_meta, nil}}]) when is_atom(var_name) do
    {:ok, {var_name, var_meta, nil}}
  end

  defp single_var_value(_), do: :error

  # --- message parsing -------------------------------------------------------

  defp extract_struct_name(msg) do
    case Regex.run(~r/([A-Z][\w.]*)\.__struct__\/1 is undefined/, msg) do
      [_, name] ->
        name
        |> String.split(".")
        |> Enum.map(&String.to_atom/1)
        |> Module.concat()

      _ ->
        nil
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
