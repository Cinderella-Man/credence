defmodule Credence.Semantic.NoNaiveDatetimeNewWithTuple do
  @moduledoc """
  Repairs the compiler warning when a bare tuple is passed to
  `NaiveDateTime.new!/2` instead of a `%Time{}` struct.

  LLMs frequently pass `{hour, minute, second, microsecond}` as the second
  argument to `NaiveDateTime.new!/2`, but the function expects a `%Time{}`
  struct.  Under `--warnings-as-errors` the resulting "incompatible types"
  warning blocks compilation.

  The fix replaces the bare tuple with a `Time.new!/3` (or `Time.new!/4`)
  call, preserving every element the user wrote: a `{hour, minute, second}`
  tuple becomes `Time.new!(hour, minute, second)` and a
  `{hour, minute, second, microsecond}` tuple becomes
  `Time.new!(hour, minute, second, microsecond)`. Tuples with any other
  arity have no `Time.new!` equivalent, so they are left untouched.

  ## Bad

      defmodule ExampleNNDNWT do
        def make_ndt(year, month, day, hour, minute) do
          NaiveDateTime.new!(Date.new!(year, month, day), {hour, minute, 0, 0})
        end
      end

  ## Good

      defmodule ExampleNNDNWT do
        def make_ndt(year, month, day, hour, minute) do
          NaiveDateTime.new!(Date.new!(year, month, day), Time.new!(hour, minute, 0, 0))
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "incompatible types given to NaiveDateTime.new!/2"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_naive_datetime_new_with_tuple,
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
            {{:., dot_meta, [{:__aliases__, alias_meta, [:NaiveDateTime]}, :new!]}, call_meta,
             [first_arg, {:{}, _tuple_meta, tuple_args}]},
            _acc
            when is_list(tuple_args) and length(tuple_args) in [3, 4] ->
              time_call =
                {{:., dot_meta, [{:__aliases__, alias_meta, [:Time]}, :new!]}, call_meta,
                 tuple_args}

              new_node =
                {{:., dot_meta, [{:__aliases__, alias_meta, [:NaiveDateTime]}, :new!]}, call_meta,
                 [first_arg, time_call]}

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
