defmodule Credence.Semantic.FixHallucinatedNaiveDatetimeAccessor do
  @moduledoc """
  Fixes compiler warnings about hallucinated `NaiveDateTime` accessor calls.

  LLMs frequently hallucinate `NaiveDateTime.minute/1`, `NaiveDateTime.hour/1`,
  `NaiveDateTime.day/1`, and `NaiveDateTime.month/1` — accessor functions that
  do not exist (`NaiveDateTime` exports none of these names), producing an
  undefined-function compile warning:

      "NaiveDateTime.minute/1 is undefined or private"

  Each of these is a plain field of the `%NaiveDateTime{}` struct carrying
  exactly the intended value, so the fix rewrites the flagged call into field
  access on its argument — `NaiveDateTime.minute(dt)` becomes `dt.minute` —
  anchored at the diagnostic's line and column, leaving every other byte
  untouched.

  `day_of_week` is deliberately not claimed: LLMs hallucinate
  `NaiveDateTime.day_of_week/1` too, but `%NaiveDateTime{}` has no
  `:day_of_week` field, so the same rewrite would trade the compile warning
  for a runtime `KeyError`, and the intended week convention
  (`Date.day_of_week/2` takes a `starting_on`) cannot be read off the call
  site.

  The compiler's diagnostic position anchors the accessor token, while a
  Sourceror range supplies the complete call. This lets the rule repair alias,
  pipe, capture, computed-argument, multiline, and Unicode spellings without
  searching strings or comments. (The compiler reports the expanded module
  path, so a user's own `MyApp.NaiveDateTime` is never claimed.)

  `UndefinedFunction` claims every "… is undefined or private", this warning
  included, and declares `priority: 501` against this rule's default 500, so
  the ordering is declared rather than alphabetical (docs/20 §1). Its repair
  is a table lookup with no `NaiveDateTime` row, and the `FunctionMatcher`
  fallback ranks only functions defined in the file under repair, so it hands
  back the source unchanged — no rename it can spell produces `dt.minute`.

  ## Bad

      defmodule ExampleFHNDA do
        def due?(dt) do
          minute = NaiveDateTime.minute(dt)
          minute
        end
      end

  ## Good

      defmodule ExampleFHNDA do
        def due?(dt) do
          minute = dt.minute
          minute
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @accessors ~w(minute hour day month)
  @module_prefix "NaiveDateTime."

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    accessor(msg) != nil
  end

  def match?(_), do: false

  def should_report?(diagnostic, source), do: fix(source, diagnostic) != source

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_naive_datetime_accessor,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: {line_no, col}})
      when is_integer(line_no) and is_integer(col) do
    with accessor when accessor != nil <- accessor(msg),
         {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, node, range} <- flagged_call(ast, line_no, col, String.to_atom(accessor)) do
      change = node |> replacement(String.to_atom(accessor)) |> Sourceror.to_string()
      Sourceror.patch_string(source, [%{range: range, change: change}])
    else
      _ -> source
    end
  end

  def fix(source, _diagnostic), do: source

  # `starts_with?` (not `contains?`) so a user module whose path merely ends
  # in `NaiveDateTime` (e.g. `MyApp.NaiveDateTime.minute/1`) is never claimed.
  # The " is undefined or private" suffix keeps `/1` from matching `/12`, and
  # `day` never claims a `day_of_week/1` message (`_` breaks the `/1` match).
  defp accessor(msg) do
    Enum.find(@accessors, fn accessor ->
      String.starts_with?(msg, "#{@module_prefix}#{accessor}/1 is undefined or private")
    end)
  end

  defp flagged_call(ast, line_no, col, accessor) do
    {_, candidates} =
      Macro.prewalk(ast, [], fn node, acc ->
        if candidate?(node, accessor) and function_position(node) == {line_no, col} do
          case Sourceror.get_range(node) do
            nil -> {node, acc}
            range -> {node, [{node, range} | acc]}
          end
        else
          {node, acc}
        end
      end)

    case candidates do
      [{node, range}] -> {:ok, node, range}
      _ -> :error
    end
  end

  defp candidate?({{:., _, [{:__aliases__, _, _}, accessor]}, _, [argument]}, accessor),
    do: safe_argument?(argument)

  defp candidate?(
         {:|>, _, [_, {{:., _, [{:__aliases__, _, _}, accessor]}, _, []}]},
         accessor
       ),
       do: true

  defp candidate?(
         {:&, _, [{:/, _, [{{:., _, [{:__aliases__, _, _}, accessor]}, _, []}, arity]}]},
         accessor
       ),
       do: literal_one?(arity)

  defp candidate?(_, _), do: false

  defp function_position({{:., meta, _}, _, _}), do: {meta[:line], meta[:column] + 1}

  defp function_position({:|>, _, [_, {{:., meta, _}, _, []}]}),
    do: {meta[:line], meta[:column] + 1}

  defp function_position({:&, _, [{:/, _, [{{:., meta, _}, _, []}, _]}]}),
    do: {meta[:line], meta[:column] + 1}

  defp function_position(_), do: nil

  defp replacement({{:., _, _}, _, [argument]}, accessor), do: field_access(argument, accessor)

  defp replacement({:|>, _, [argument, _]}, accessor), do: field_access(argument, accessor)

  defp replacement({:&, _, _}, accessor) do
    value = {:value, [], nil}
    {:fn, [], [{:->, [], [[value], field_access(value, accessor)]}]}
  end

  defp field_access(argument, accessor),
    do: {{:., [], [argument, accessor]}, [no_parens: true], []}

  defp safe_argument?({:__block__, _, [value]}) when value in [nil, true, false], do: false
  defp safe_argument?({:_, _, context}) when is_atom(context) or is_nil(context), do: false
  defp safe_argument?(_), do: true

  defp literal_one?({:__block__, _, [1]}), do: true
  defp literal_one?(_), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
