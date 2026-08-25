defmodule Credence.Syntax.NoPythonMultiReturnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.{RuleHelpers, Syntax.NoPythonMultiReturn}

  defp analyze(code), do: NoPythonMultiReturn.analyze(code)
  defp fix(code), do: NoPythonMultiReturn.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule BareCommaMultiReturn do
      def validate_create(nil, plan_name) do
        event = %{type: :subscription_created, plan: plan_name}
        new_state = %{plan: plan_name, status: :pending, reason: nil}
        {:ok, new_state}, [event]
      end
    end
    """

    expected = """
    defmodule BareCommaMultiReturn do
      def validate_create(nil, plan_name) do
        event = %{type: :subscription_created, plan: plan_name}
        new_state = %{plan: plan_name, status: :pending, reason: nil}
        {{:ok, new_state}, [event]}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "syntax pipeline discovers, accepts, and commits the flagship repair" do
    input = """
    defmodule BareCommaMultiReturnPipeline do
      def validate_create(nil, plan_name) do
        event = %{type: :subscription_created, plan: plan_name}
        new_state = %{plan: plan_name, status: :pending, reason: nil}
        {:ok, new_state}, [event]
      end
    end
    """

    expected = """
    defmodule BareCommaMultiReturnPipeline do
      def validate_create(nil, plan_name) do
        event = %{type: :subscription_created, plan: plan_name}
        new_state = %{plan: plan_name, status: :pending, reason: nil}
        {{:ok, new_state}, [event]}
      end
    end
    """

    {emitted, applied} = Credence.Syntax.fix_with_trace(input)

    confirm_fix(emitted, expected)
    assert RuleHelpers.compile_and_capture(emitted) == RuleHelpers.compile_and_capture(expected)
    assert {NoPythonMultiReturn, 1} in applied
  end

  test "fixes an operator expression followed by another return value" do
    input = """
    defmodule NoPythonMultiReturnOperatorExpression do
      def run(a, b, c) do
        a + b, c
      end
    end
    """

    expected = """
    defmodule NoPythonMultiReturnOperatorExpression do
      def run(a, b, c) do
        {a + b, c}
      end
    end
    """

    fixed = fix(input)

    confirm_fix(fixed, expected)
    assert RuleHelpers.compile_and_capture(fixed) == RuleHelpers.compile_and_capture(expected)
  end

  test "keeps an inline comment outside the generated tuple" do
    input = """
    defmodule NoPythonMultiReturnInlineComment do
      def run(a, b) do
        a, b # explanation
      end
    end
    """

    expected = """
    defmodule NoPythonMultiReturnInlineComment do
      def run(a, b) do
        {a, b} # explanation
      end
    end
    """

    fixed = fix(input)

    confirm_fix(fixed, expected)
    assert RuleHelpers.compile_and_capture(fixed) == RuleHelpers.compile_and_capture(expected)
  end

  test "fixed output no longer flags" do
    input = """
    defmodule BareCommaMultiReturn do
      def validate_create(nil, plan_name) do
        event = %{type: :subscription_created, plan: plan_name}
        new_state = %{plan: plan_name, status: :pending, reason: nil}
        {:ok, new_state}, [event]
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule BareCommaMultiReturn do
      def validate_create(nil, plan_name) do
        event = %{type: :subscription_created, plan: plan_name}
        new_state = %{plan: plan_name, status: :pending, reason: nil}
        {:ok, new_state}, [event]
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "does not modify map keyword entries" do
    input = """
    defmodule MapKeywords do
      def build do
        name = get_name()
        %{name: name, age: 30}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify line comments" do
    input = """
    defmodule Comments do
      # a, b, c
      def foo, do: :ok
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify catch-clause arrows" do
    input = """
    defmodule CatchClause do
      def run do
        try do
          risky()
        catch
          :exit, reason -> {:error, reason}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify multi-line map literals" do
    input = """
    defmodule MultiLineMap do
      def build do
        %{
          name: "foo",
          age: 30
        }
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify multi-line map with string keys" do
    input = """
    defmodule MultiLineMapStringKeys do
      def build do
        %{
          "name" => "foo",
          "age" => 30
        }
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify with-pipeline clauses" do
    input = """
    defmodule WithPipeline do
      def run do
        with {:ok, a} <- foo(),
             {:ok, b} <- bar() do
          {:ok, a, b}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify with-pipeline on single line" do
    input = """
    defmodule WithSingleLine do
      def run do
        with {:ok, a} <- foo(), {:ok, b} <- bar() do
          {:ok, a, b}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify multi-line keyword list" do
    input = """
    defmodule MultiLineKeywords do
      def build do
        [
          name: "foo",
          age: 30
        ]
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify multi-line function call args" do
    input = """
    defmodule MultiLineArgs do
      def build do
        some_function(
          arg1,
          arg2
        )
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixes bare comma even when preceded by multi-line map" do
    input = """
    defmodule BareCommaAfterMap do
      def build do
        x = %{
          name: "foo"
        }
        a, b
      end
    end
    """

    expected = """
    defmodule BareCommaAfterMap do
      def build do
        x = %{
          name: "foo"
        }
        {a, b}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "does not modify raise with two arguments" do
    input = """
    defmodule NoPythonMultiReturnOverFire do
      use GenServer

      def init(opts) do
        threshold = Keyword.get(opts, :threshold, 5.0)

        unless is_number(threshold) and threshold > 0 do
          raise ArgumentError, "threshold must be positive"
        end

        state = %{
          threshold: threshold,
          streams: %{}
        }

        {:ok, state}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify struct-update pipe with trailing comma and keyword on next line" do
    input = """
    | users: Map.put(m, :k, v),
      user_ids: Map.put(m2, :k2, v2)
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify struct-update pipe in a module" do
    input = """
    defmodule StructUpdate do
      def update(state) do
        %{state |
          users: Map.put(state.users, :key, :val),
          user_ids: Map.put(state.user_ids, :key, [:val])}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify mismatched ) closing a map literal" do
    input = """
    defmodule MismatchedDelimiter do
      def build do
        %{type: :test, plan: name), extra
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify paren-less module function call" do
    input = """
    defmodule OverFire do
      def run do
        Map.update state.queues, priority, [queue_data]
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify Map.get without parens" do
    input = """
    defmodule OverFire do
      def run do
        Map.get state.queues, :key, []
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify paren-less atom-module function call (ETS options)" do
    input = ":ets.new :metrics, [:named_table, :public, :set]"

    confirm_fix(fix(input), input)
  end

  test "does not modify ETS GenServer init with option list" do
    input = """
    defmodule Metrics do
      use GenServer

      def start_link(opts \\\\ []) do
        GenServer.start_link(__MODULE__, [], name: __MODULE__)
      end

      @impl true
      def init(_state) do
        :ets.new(:metrics, [
          :named_table,
          :public,
          :set,
          {:read_concurrency, true}
        ])
        {:ok, %{}}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify end keyword before comma in Enum.sort_by closure (paren-less)" do
    input = """
    defmodule BugDemo do
      def sort_list(list) do
        direction = :asc
        Enum.sort_by list, fn item ->
          item.value
        end, direction
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify end keyword before comma in Enum.sort_by closure (parenthesized)" do
    input = """
    defmodule BugDemo do
      def sort_list(list) do
        direction = :asc

        Enum.sort_by(list, fn item ->
          item.value
        end, direction)
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify for comprehension guard on separate line" do
    input = """
    defmodule ForGuard do
      def run(state) do
        for {name, job_data} <- state.jobs,
            job_data.status == :active,
            do: {name, job_data}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify for comprehension with multiple guards on separate lines" do
    input = """
    defmodule ForMultiGuard do
      def run(state) do
        for {name, job_data} <- state.jobs,
            job_data.status == :active,
            NaiveDateTime.compare(job_data.next_run_at, DateTime.utc_now()) != :gt,
            do: {name, job_data}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify for comprehension with do block and guard on separate line" do
    input = """
    defmodule ForDoBlock do
      def run(state) do
        for {name, job_data} <- state.jobs,
            job_data.status == :active do
          {name, job_data}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixes bare comma after for comprehension ends" do
    input = """
    defmodule BareCommaAfterFor do
      def run do
        for x <- [1,2,3], do: x
        a, b
      end
    end
    """

    expected = """
    defmodule BareCommaAfterFor do
      def run do
        for x <- [1,2,3], do: x
        {a, b}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "does not modify defstruct with bare atoms in bracket form" do
    input = """
    defmodule DefstructExample do
      defstruct [
        :field_a,
        :field_b,
        :field_c,
        field_d: %{},
        field_e: nil
      ]
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify defstruct with bare atoms without brackets" do
    input = """
    defmodule DefstructBare do
      defstruct :field_a,
                :field_b,
                :field_c
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify defstruct with mixed bare atoms and keywords" do
    input = """
    defmodule DefstructMixed do
      defstruct :field_a,
                :field_b,
                field_c: nil,
                field_d: %{}
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify multi-line call args after a line comment" do
    input = """
    defmodule CommentThenCall do
      # a note
      def build do
        some_function(
          arg1,
          arg2
        )
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify prose inside a moduledoc heredoc" do
    input = """
    defmodule DocProse do
      @moduledoc \"\"\"
      Parses the AST, then diffs the original and emits one patch.

      - `:strict` — you make no promises, so only safe rules run.
      \"\"\"
      def f, do: :ok
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify the last line of a multi-line when guard" do
    input = """
    defmodule WhenGuard do
      defp same?({n, _, c1}, {n, _, c2})
           when is_atom(n) and (is_nil(c1) or is_atom(c1)) and
                  (is_nil(c2) or is_atom(c2)),
           do: true
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify a clause head whose arrow wrapped past a when guard" do
    input = """
    defmodule WrappedClauseHead do
      def f(m, a) do
        try do
          apply(m, a, [])
        catch
          :exit, value
          when value == :normal ->
            :error
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not modify after a quote character literal" do
    input = """
    defmodule CharLiteral do
      def q(ch) when ch == ?", do: :quote

      def opts do
        [
          :named_table,
          :public
        ]
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixes only the real bare comma, not lookalikes in a doc or comment" do
    input = """
    defmodule OnlyTheRealOne do
      @moduledoc \"\"\"
      Returns a, b like Python does.
      \"\"\"
      def f(x) do
        # returns x, y
        x, :ok
      end
    end
    """

    expected = """
    defmodule OnlyTheRealOne do
      @moduledoc \"\"\"
      Returns a, b like Python does.
      \"\"\"
      def f(x) do
        # returns x, y
        {x, :ok}
      end
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  test "fixes a three-element Python multi-return" do
    input = """
    defmodule ThreeValues do
      def f(x) do
        {:ok, x}, %{a: 1}, [1, 2]
      end
    end
    """

    expected = """
    defmodule ThreeValues do
      def f(x) do
        {{:ok, x}, %{a: 1}, [1, 2]}
      end
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end
end
