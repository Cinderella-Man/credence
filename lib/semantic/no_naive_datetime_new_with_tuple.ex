defmodule Credence.Semantic.NoNaiveDatetimeNewWithTuple do
  @moduledoc """
  Repairs the compiler warning when a bare tuple is passed to
  `NaiveDateTime.new!/2` instead of a `%Time{}` struct.

  LLMs frequently pass `{hour, minute, second, microsecond}` as the second
  argument to `NaiveDateTime.new!/2`, but the function expects a `%Time{}`
  struct.  Under `--warnings-as-errors` the resulting "incompatible types"
  warning blocks compilation.

  The fix replaces the bare tuple with an `Elixir.Time.new!/3` (or
  `Elixir.Time.new!/4`)
  call, preserving every element the user wrote: a `{hour, minute, second}`
  tuple becomes `Elixir.Time.new!(hour, minute, second)` and a
  `{hour, minute, second, microsecond}` tuple becomes
  `Elixir.Time.new!(hour, minute, second, {microsecond, 6})`. Tuples with any
  other arity have no `Time.new!` equivalent, so they are left untouched.

  ## Bad

      defmodule ExampleNNDNWT do
        def make_ndt(year, month, day, hour, minute) do
          NaiveDateTime.new!(Date.new!(year, month, day), {hour, minute, 0, 0})
        end
      end

  ## Good

      defmodule ExampleNNDNWT do
        def make_ndt(year, month, day, hour, minute) do
          NaiveDateTime.new!(Date.new!(year, month, day), Elixir.Time.new!(hour, minute, 0, {0, 6}))
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "incompatible types given to NaiveDateTime.new!/2"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg) and repairable_tuple_type?(msg)
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
  def fix(source, diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        diagnostic_line = line(diagnostic)

        {result, changed?} =
          Macro.traverse(
            ast,
            {0, false},
            fn
              {:quote, _, _} = node, {quote_depth, changed?} ->
                {node, {quote_depth + 1, changed?}}

              {{:., dot_meta, [{:__aliases__, alias_meta, [:NaiveDateTime]}, :new!]}, call_meta,
               [first_arg, {:{}, _tuple_meta, tuple_args}]} = node,
              {0, _changed?} = acc
              when is_list(tuple_args) and length(tuple_args) in [3, 4] ->
                if call_meta[:line] == diagnostic_line do
                  time_args =
                    case tuple_args do
                      [hour, minute, second, microsecond] ->
                        [hour, minute, second, {:{}, [], [microsecond, 6]}]

                      args ->
                        args
                    end

                  time_call =
                    {{:., dot_meta, [{:__aliases__, alias_meta, [:"Elixir", :Time]}, :new!]},
                     call_meta, time_args}

                  new_node =
                    {{:., dot_meta, [{:__aliases__, alias_meta, [:NaiveDateTime]}, :new!]},
                     call_meta, [first_arg, time_call]}

                  {new_node, {0, true}}
                else
                  {node, acc}
                end

              node, acc ->
                {node, acc}
            end,
            fn
              {:quote, _, _} = node, {quote_depth, changed?} ->
                {node, {quote_depth - 1, changed?}}

              node, acc ->
                {node, acc}
            end
          )

        {_quote_depth, changed?} = changed?

        if changed?, do: Sourceror.to_string(result), else: source

      _ ->
        source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line

  defp repairable_tuple_type?(message) do
    given_types =
      message
      |> String.split("given types:", parts: 2)
      |> List.last()
      |> String.split("but expected", parts: 2)
      |> List.first()

    Regex.scan(~r/dynamic\(\{([^{}\n]+)\}\)/, given_types, capture: :all_but_first)
    |> Enum.any?(fn [elements] -> length(String.split(elements, ",")) in [3, 4] end)
  end
end
