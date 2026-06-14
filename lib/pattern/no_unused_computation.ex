defmodule Credence.Pattern.NoUnusedComputation do
  @moduledoc """
  Detects dead `_`-prefixed assignments of pure function calls.

  An assignment like `_n = length(chars)` computes a value that is never
  used (the `_` prefix signals intent to discard). If the right-hand side
  is a pure function call, removing the entire line is a safe, deterministic
  rewrite that avoids O(n) wasted computation.

  ## Bad

      def process(s) do
        chars = String.graphemes(s)
        _n = length(chars)

        chars
        |> Enum.with_index()
        |> Enum.into(%{}, fn {char, idx} -> {char, idx} end)
      end

  ## Good

      def process(s) do
        chars = String.graphemes(s)

        chars
        |> Enum.with_index()
        |> Enum.into(%{}, fn {char, idx} -> {char, idx} end)
      end

  ## What is detected

  An assignment to a `_`-prefixed variable (or bare `_`) whose right-hand
  side is a call to a **known-pure** function — Kernel utilities, String
  manipulation, List helpers, and other stateless functions. Only functions
  whose evaluation is provably side-effect-free are flagged.

  If the dead assignment is the **last** expression in a block, it is
  left alone (removing it would change the block's return value or make
  the block empty).
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source) || Sourceror.to_string(ast)

    Credence.RuleHelpers.patches_from_ast_transform(ast, source, fn ast ->
      Macro.prewalk(ast, fn
        {:__block__, meta, stmts} = node when is_list(stmts) ->
          filtered = remove_dead_assignments(stmts)

          if length(filtered) < length(stmts) do
            {:__block__, meta, filtered}
          else
            node
          end

        node ->
          node
      end)
    end)
  end

  # Remove dead assignments from a block's statement list.
  # Preserves assignments that are the last expression (removing them
  # would change the block's return value or make the block empty).
  defp remove_dead_assignments(stmts) when length(stmts) <= 1, do: stmts

  defp remove_dead_assignments(stmts) do
    {leading, [last]} = Enum.split(stmts, -1)

    filtered =
      Enum.reject(leading, fn stmt ->
        dead_assignment?(stmt)
      end)

    filtered ++ [last]
  end

  defp check_node({:=, meta, [lhs, rhs]}) do
    if underscore_var?(lhs) and pure_call?(rhs) do
      line = Keyword.get(meta, :line)

      {:ok,
       %Issue{
         rule: :no_unused_computation,
         message: build_message(lhs, rhs),
         meta: %{line: line}
       }}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  # Check if a variable name starts with underscore (including bare `_`).
  # Context must be nil or an atom (Sourceror uses nil for variables),
  # and we exclude __block__ and other AST meta-forms.
  defp underscore_var?({:_, _, ctx}) when is_atom(ctx), do: true

  defp underscore_var?({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    name != :__block__ and String.starts_with?(Atom.to_string(name), "_")
  end

  defp underscore_var?(_), do: false

  # Check if the RHS is a known-pure function call.
  #
  # A call that takes a function argument (`&f/1`, `fn -> … end`) is NEVER
  # treated as discardable even if the receiver is otherwise pure: the passed
  # function can raise or have side effects, so the call may be load-bearing
  # despite its result being thrown away (e.g. `_ = Enum.each(keys, &cast!/1)`,
  # where `cast!` validates by raising). Deleting it would silently drop that
  # work, so we bail out whenever any argument is a function.
  defp pure_call?({func, _, args}) when is_atom(func) and is_list(args) and args != [] do
    func in known_pure_functions() and not any_fun_arg?(args)
  end

  # Qualified call: Module.function(args)
  # NOTE: in the AST, __aliases__ stores bare atoms (:String, :Enum, etc.),
  # but the map keys are full module names (String, Enum). We convert
  # using Module.concat/1 so the lookup succeeds.
  defp pure_call?({{:., _, [{:__aliases__, _, [mod]}, func]}, _, args})
       when is_atom(mod) and is_atom(func) and is_list(args) and args != [] do
    full_mod = Module.concat([mod])

    case Map.fetch(known_pure_module_functions(), full_mod) do
      {:ok, fns} -> func in fns and not any_fun_arg?(args)
      :error -> false
    end
  end

  defp pure_call?(_), do: false

  # True if any argument is a function literal or capture (`fn … end`, `&…`).
  # Such an argument can raise or perform side effects, so a call carrying one
  # is not safely discardable.
  defp any_fun_arg?(args) do
    Enum.any?(args, fn
      {:fn, _, _} -> true
      {:&, _, _} -> true
      _ -> false
    end)
  end

  # Known-pure unqualified functions (Kernel and friends).
  defp known_pure_functions do
    MapSet.new([
      # Numeric
      :abs,
      :ceil,
      :floor,
      :round,
      :trunc,
      :div,
      :rem,
      :max,
      :min,
      :negate,
      # List/tuple
      :hd,
      :tl,
      :elem,
      :put_elem,
      :tuple_size,
      :map_size,
      :length,
      # Binary
      :byte_size,
      :bit_size,
      # Type predicates
      :is_nil,
      :is_atom,
      :is_binary,
      :is_bitstring,
      :is_boolean,
      :is_float,
      :is_function,
      :is_integer,
      :is_list,
      :is_map,
      :is_number,
      :is_pid,
      :is_port,
      :is_reference,
      :is_tuple,
      # Conversion
      :to_string,
      :to_charlist,
      :to_atom,
      :to_existing_atom,
      :to_charlist,
      :to_string
    ])
  end

  # Known-pure module-qualified functions.
  defp known_pure_module_functions do
    %{
      String => [
        :length,
        :graphemes,
        :codepoints,
        :split,
        :trim,
        :trim_leading,
        :trim_trailing,
        :upcase,
        :downcase,
        :capitalize,
        :reverse,
        :replace,
        :replace_leading,
        :replace_trailing,
        :at,
        :first,
        :last,
        :slice,
        :contains?,
        :starts_with?,
        :ends_with?,
        :match?,
        :myers_difference,
        :to_charlist,
        :to_integer,
        :to_float,
        :valid?
      ],
      Enum => [
        :count,
        :sum,
        :product,
        :min,
        :max,
        :min_max,
        :reverse,
        :sort,
        :uniq,
        :join,
        :map,
        :filter,
        :reject,
        :flat_map,
        :reduce,
        :zip,
        :with_index,
        :take,
        :drop,
        :slice,
        :chunk_every,
        :chunk_while,
        :scan,
        :dedup,
        :frequencies,
        :group_by,
        :into,
        :at,
        :fetch,
        :find,
        :any?,
        :all?,
        :member?,
        :empty?,
        :random,
        :sample,
        :take_every,
        :intersperse,
        :to_list,
        :concat,
        :map_join,
        :every?,
        :find_value,
        :find_index,
        :flat_map_reduce,
        :map_every,
        :map_intersperse,
        :reject,
        :scan,
        :slice,
        :split,
        :split_while,
        :split_with,
        :take_random,
        :take_while,
        :to_map,
        :uniq_by,
        :unzip,
        :with_index
      ],
      List => [
        :flatten,
        :wrap,
        :last,
        :first,
        :delete_at,
        :insert_at,
        :replace_at,
        :update_at,
        :pop_at,
        :keysort,
        :keystore,
        :keyfind,
        :keymember?,
        :keyreplace,
        :keydelete,
        :keytake,
        :myers_difference,
        :to_tuple,
        :to_string,
        :to_charlist,
        :duplicate,
        :starts_with?,
        :zip,
        :foldl,
        :foldr,
        :delete,
        :delete_all
      ],
      Map => [
        :keys,
        :values,
        :to_list,
        :get,
        :get_lazy,
        :get_and_update,
        :get_and_update_lazy,
        :fetch,
        :fetch!,
        :has_key?,
        :merge,
        :put,
        :delete,
        :drop,
        :take,
        :split,
        :pop,
        :pop_lazy,
        :update,
        :update!,
        :new,
        :new,
        :size,
        :equal?,
        :intersect,
        :disjoint?
      ],
      Tuple => [
        :append,
        :delete_at,
        :duplicate,
        :elem,
        :insert_at,
        :size,
        :to_list,
        :to_map
      ]
    }
  end

  defp dead_assignment?({:=, _, [lhs, rhs]}) do
    underscore_var?(lhs) and pure_call?(rhs)
  end

  defp dead_assignment?(_), do: false

  defp build_message(lhs, rhs) do
    var_name =
      case lhs do
        {:_, _, _} -> "_"
        {name, _, _} -> Atom.to_string(name)
      end

    func_name =
      case rhs do
        {func, _, _} when is_atom(func) ->
          "#{func}/#{length(elem(rhs, 2))}"

        {{:., _, [{:__aliases__, _, [mod]}, func]}, _, args} ->
          "#{mod}.#{func}/#{length(args)}"
      end

    "Dead assignment to `#{var_name}` — `#{func_name}` is pure but its result is unused. Remove this line."
  end
end
