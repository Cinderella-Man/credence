defmodule Credence.Semantic.FixUndefinedVariableInWithElse do
  @moduledoc """
  Fixes `undefined variable` errors caused by LLMs assigning variables with
  `=` inside a `with` body and referencing them in the `else` clause.

  In Elixir, `=` assignments inside a `with` expression are scoped to the
  `with` body — they are not visible in `else` clauses. LLMs frequently write:

      with true <- header != "",
           sigs = String.split(header, ","),
           true <- sigs != [] do
        {:ok, :verified}
      else
        _ ->
          cond do
            sigs == [] -> {:error, :malformed}  # undefined variable!
          end
      end

  The compiler emits `undefined variable "sigs"` because `sigs` is only bound
  inside the `with` body. The fix extracts the `=` binding before the `with`,
  which preserves semantics when the RHS is independent of prior clauses:

      sigs = String.split(header, ",")

      with true <- header != "",
           true <- sigs != [] do
        {:ok, :verified}
      else
        _ ->
          cond do
            sigs == [] -> {:error, :malformed}
          end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, "undefined variable")
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :fix_undefined_variable_in_with_else,
      message: msg,
      meta: %{line: line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    case extract_var_name(msg) do
      nil ->
        source

      _var_name ->
        with {:ok, ast} <- Sourceror.parse_string(source) do
          new_ast = hoist_assignments(ast)

          if new_ast != ast do
            Sourceror.to_string(new_ast)
          else
            source
          end
        else
          _ -> source
        end
    end
  end

  # Walk the AST and replace each `with` node that has `=` assignments
  # with a __block__ containing the assignments followed by the cleaned `with`.
  defp hoist_assignments(ast) do
    Macro.prewalk(ast, fn
      {:with, meta, args} ->
        {clauses, opts} = split_with_args(args)

        assignments =
          Enum.filter(clauses, fn
            {:=, _, _} -> true
            _ -> false
          end)

        if assignments != [] do
          remaining = Enum.reject(clauses, &match?({:=, _, _}, &1))
          cleaned_with = {:with, meta, remaining ++ [opts]}
          {:__block__, [], assignments ++ [cleaned_with]}
        else
          {:with, meta, args}
        end

      node ->
        node
    end)
  end

  defp extract_var_name(msg) do
    case Regex.run(~r/undefined variable "(\w+)"/, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp split_with_args(args) do
    case Enum.split_while(args, &(not is_list(&1))) do
      {clauses, [opts]} -> {clauses, opts}
      {clauses, []} -> {clauses, []}
    end
  end

  defp line({l, _col}) when is_integer(l), do: l
  defp line(l) when is_integer(l), do: l
end
