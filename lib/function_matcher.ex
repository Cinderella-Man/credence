defmodule Credence.FunctionMatcher do
  @moduledoc """
  Finds the closest matching defined function for an undefined function call.

  When the compiler reports `undefined function NAME/ARITY`, this module
  searches the source for defined functions in the same module with matching
  arity and ranks them by name similarity. Used by `UndefinedLocalFunction`
  and `UndefinedFunction` to fix misspelled or mangled function calls.

  ## Scoring ladder

  | Score | Match type                                    |
  |-------|-----------------------------------------------|
  | 100   | Exact name + `?` suffix (`palindrome` → `palindrome?`) |
  | 95    | Exact name + `!` suffix (`save` → `save!`)    |
  | 90    | `__` demangles to `?` (`perfect__` → `perfect?`) |
  | 85    | `__` demangles to `!` (`save__` → `save!`)    |
  | 80    | Candidate is prefix of name (`fib` ← `fibonacci`) |
  | 75    | Name is prefix of candidate (`find` → `find_largest`) |
  | 70    | One contains the other (`fibonacci` ∈ `do_fibonacci`) |
  | 0–60  | Jaro distance scaled to 0–60                  |

  The module never "gives up" — if any function with matching arity exists,
  it's returned. The pipeline validates the fix by compiling.
  """

  @type candidate :: %{
          name: String.t(),
          arity: non_neg_integer(),
          visibility: :def | :defp,
          score: non_neg_integer()
        }

  @doc """
  Returns the best matching function name, or `:no_candidates` if the
  module has zero functions with the given arity.
  """
  @spec suggest(String.t(), String.t(), String.t(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | :no_candidates
  def suggest(source, module_name, undefined_name, arity, opts \\ []) do
    case candidates(source, module_name, undefined_name, arity, opts) do
      [] -> :no_candidates
      [best | _] -> {:ok, best.name}
    end
  end

  @doc """
  Returns all candidate functions with matching arity, sorted by score
  descending. Each candidate has `:name`, `:arity`, `:visibility`, and `:score`.
  """
  @spec candidates(String.t(), String.t(), String.t(), non_neg_integer(), keyword()) ::
          [candidate()]
  def candidates(source, module_name, undefined_name, arity, opts \\ []) do
    visibility = Keyword.get(opts, :visibility, :any)

    source
    |> defined_functions(module_name)
    |> Enum.uniq_by(fn %{name: name, arity: a} -> {name, a} end)
    |> filter_by_arity(arity)
    |> filter_by_visibility(visibility)
    |> Enum.map(fn func -> Map.put(func, :score, score(undefined_name, func.name)) end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  # ── Function extraction ────────────────────────────────────────

  defp defined_functions(source, module_name) do
    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        ast
        |> find_module_body(module_name)
        |> extract_functions()

      {:error, _} ->
        []
    end
  end

  defp find_module_body(ast, module_name) do
    {_, result} =
      Macro.prewalk(ast, nil, fn
        {:defmodule, _, [{:__aliases__, _, parts}, [do: body]]} = node, acc ->
          if module_parts_match?(parts, module_name) do
            {node, body}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    case result do
      nil -> []
      {:__block__, _, statements} -> statements
      single -> [single]
    end
  end

  defp module_parts_match?(parts, module_name) do
    parts
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(".")
    |> Kernel.==(module_name)
  end

  defp extract_functions(body) do
    Enum.flat_map(body, fn
      # def/defp with guard: def foo(x) when is_integer(x), do: ...
      {visibility, _, [{:when, _, [{name, _, args}, _guard]} | _]}
      when visibility in [:def, :defp] and is_atom(name) ->
        [%{name: Atom.to_string(name), arity: arg_count(args), visibility: visibility}]

      # def/defp without guard: def foo(x), do: ...
      {visibility, _, [{name, _, args} | _]}
      when visibility in [:def, :defp] and is_atom(name) ->
        [%{name: Atom.to_string(name), arity: arg_count(args), visibility: visibility}]

      _ ->
        []
    end)
  end

  defp arg_count(nil), do: 0
  defp arg_count(args) when is_list(args), do: length(args)
  defp arg_count(_), do: 0

  # ── Filtering ──────────────────────────────────────────────────

  defp filter_by_arity(functions, arity) do
    Enum.filter(functions, fn %{arity: a} -> a == arity end)
  end

  defp filter_by_visibility(functions, :any), do: functions

  defp filter_by_visibility(functions, :public_only) do
    Enum.filter(functions, fn %{visibility: v} -> v == :def end)
  end

  # ── Scoring ────────────────────────────────────────────────────

  defp score(undefined, candidate) do
    cond do
      # Exact name + ? suffix (palindrome → palindrome?)
      candidate == undefined <> "?" ->
        100

      # Exact name + ! suffix (save → save!)
      candidate == undefined <> "!" ->
        95

      # __ demangles to ? (perfect__ → perfect?)
      String.contains?(undefined, "__") and
          candidate == String.replace(undefined, "__", "?") ->
        90

      # __ demangles to ! (save__ → save!)
      String.contains?(undefined, "__") and
          candidate == String.replace(undefined, "__", "!") ->
        85

      # Candidate is a prefix of the undefined name (fib ← fibonacci)
      candidate != undefined and String.starts_with?(undefined, candidate) ->
        80

      # Undefined name is a prefix of the candidate (find → find_largest)
      candidate != undefined and String.starts_with?(candidate, undefined) ->
        75

      # One contains the other (fibonacci ∈ do_fibonacci)
      candidate != undefined and
          (String.contains?(candidate, undefined) or
             String.contains?(undefined, candidate)) ->
        70

      # Fall back to Jaro distance scaled to 0–60
      true ->
        jaro = String.jaro_distance(undefined, candidate)
        round(jaro * 60)
    end
  end
end
