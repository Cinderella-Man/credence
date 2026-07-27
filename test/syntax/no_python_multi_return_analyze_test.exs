defmodule Credence.Syntax.NoPythonMultiReturnAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoPythonMultiReturn

  defp analyze(code), do: NoPythonMultiReturn.analyze(code)

  test "flags the unparseable code" do
    code = """
    defmodule BareCommaMultiReturn do
      def validate_create(nil, plan_name) do
        event = %{type: :subscription_created, plan: plan_name}
        new_state = %{plan: plan_name, status: :pending, reason: nil}
        {:ok, new_state}, [event]
      end
    end
    """

    assert [%Issue{rule: :no_python_multi_return, meta: %{line: 5}}] = analyze(code)
  end

  test "leaves good code alone" do
    code = """
    defmodule GoodCode do
      def validate_create(nil, plan_name) do
        event = %{type: :subscription_created, plan: plan_name}
        new_state = %{plan: plan_name, status: :pending, reason: nil}
        {{:ok, new_state}, [event]}
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag map keyword entries" do
    code = """
    defmodule MapKeywords do
      def build do
        name = get_name()
        %{name: name, age: 30}
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag line comments" do
    code = """
    defmodule Comments do
      # a, b, c
      def foo, do: :ok
    end
    """

    assert analyze(code) == []
  end

  test "does not flag catch-clause arrows" do
    code = """
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

    assert analyze(code) == []
  end

  test "does not flag multi-line map literals" do
    code = """
    defmodule MultiLineMap do
      def build do
        %{
          name: "foo",
          age: 30
        }
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag multi-line map with string keys" do
    code = """
    defmodule MultiLineMapStringKeys do
      def build do
        %{
          "name" => "foo",
          "age" => 30
        }
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag with-pipeline clauses" do
    code = """
    defmodule WithPipeline do
      def run do
        with {:ok, a} <- foo(),
             {:ok, b} <- bar() do
          {:ok, a, b}
        end
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag with-pipeline on single line" do
    code = """
    defmodule WithSingleLine do
      def run do
        with {:ok, a} <- foo(), {:ok, b} <- bar() do
          {:ok, a, b}
        end
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag multi-line keyword list" do
    code = """
    defmodule MultiLineKeywords do
      def build do
        [
          name: "foo",
          age: 30
        ]
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag multi-line function call args" do
    code = """
    defmodule MultiLineArgs do
      def build do
        some_function(
          arg1,
          arg2
        )
      end
    end
    """

    assert analyze(code) == []
  end

  test "flags bare comma even when preceded by multi-line map" do
    code = """
    defmodule BareCommaAfterMap do
      def build do
        x = %{
          name: "foo"
        }
        a, b
      end
    end
    """

    assert [%Issue{rule: :no_python_multi_return, meta: %{line: 6}}] = analyze(code)
  end

  test "does not flag raise with two arguments" do
    code = """
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

    assert analyze(code) == []
  end

  test "does not flag struct-update pipe with trailing comma and keyword on next line" do
    code = """
    | users: Map.put(m, :k, v),
      user_ids: Map.put(m2, :k2, v2)
    """

    assert analyze(code) == []
  end

  test "does not flag struct-update pipe in a module" do
    code = """
    defmodule StructUpdate do
      def update(state) do
        %{state |
          users: Map.put(state.users, :key, :val),
          user_ids: Map.put(state.user_ids, :key, [:val])}
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag mismatched ) closing a map literal" do
    code = """
    defmodule MismatchedDelimiter do
      def build do
        %{type: :test, plan: name), extra
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag paren-less module function call" do
    code = """
    defmodule OverFire do
      def run do
        Map.update state.queues, priority, [queue_data]
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag Map.get without parens" do
    code = """
    defmodule OverFire do
      def run do
        Map.get state.queues, :key, []
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag paren-less atom-module function call (ETS options)" do
    code = ":ets.new :metrics, [:named_table, :public, :set]"

    assert analyze(code) == []
  end

  test "does not flag ETS GenServer init with option list" do
    code = """
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

    assert analyze(code) == []
  end

  test "does not flag end keyword before comma in Enum.sort_by closure (paren-less)" do
    code = """
    defmodule BugDemo do
      def sort_list(list) do
        direction = :asc
        Enum.sort_by list, fn item ->
          item.value
        end, direction
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag end keyword before comma in Enum.sort_by closure (parenthesized)" do
    code = """
    defmodule BugDemo do
      def sort_list(list) do
        direction = :asc

        Enum.sort_by(list, fn item ->
          item.value
        end, direction)
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag for comprehension guard on separate line" do
    code = """
    defmodule ForGuard do
      def run(state) do
        for {name, job_data} <- state.jobs,
            job_data.status == :active,
            do: {name, job_data}
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag for comprehension with multiple guards on separate lines" do
    code = """
    defmodule ForMultiGuard do
      def run(state) do
        for {name, job_data} <- state.jobs,
            job_data.status == :active,
            NaiveDateTime.compare(job_data.next_run_at, DateTime.utc_now()) != :gt,
            do: {name, job_data}
      end
    end
    """

    assert analyze(code) == []
  end

  test "does not flag for comprehension with do block and guard on separate line" do
    code = """
    defmodule ForDoBlock do
      def run(state) do
        for {name, job_data} <- state.jobs,
            job_data.status == :active do
          {name, job_data}
        end
      end
    end
    """

    assert analyze(code) == []
  end

  test "flags bare comma after for comprehension ends" do
    code = """
    defmodule BareCommaAfterFor do
      def run do
        for x <- [1,2,3], do: x
        a, b
      end
    end
    """

    assert [%Issue{rule: :no_python_multi_return, meta: %{line: 4}}] = analyze(code)
  end

  test "does not flag defstruct with bare atoms in bracket form" do
    code = """
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

    assert analyze(code) == []
  end

  test "does not flag defstruct with bare atoms without brackets" do
    code = """
    defmodule DefstructBare do
      defstruct :field_a,
                :field_b,
                :field_c
    end
    """

    assert analyze(code) == []
  end

  test "does not flag defstruct with mixed bare atoms and keywords" do
    code = """
    defmodule DefstructMixed do
      defstruct :field_a,
                :field_b,
                field_c: nil,
                field_d: %{}
    end
    """

    assert analyze(code) == []
  end

  # A `#` comment ends at its newline. When it did not, the depth walker stayed
  # in comment context for the whole rest of the file, froze the nesting depth
  # at 0, and every later multi-line construct looked like a bare comma.
  test "does not flag multi-line call args after a line comment" do
    code = """
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

    assert analyze(code) == []
  end

  # Heredoc contents are data, not code. Prose commas sit at depth 0 but are
  # never expressions.
  test "does not flag prose inside a moduledoc heredoc" do
    code = """
    defmodule DocProse do
      @moduledoc \"\"\"
      Parses the AST, then diffs the original and emits one patch.

      - `:strict` — you make no promises, so only safe rules run.
      \"\"\"
      def f, do: :ok
    end
    """

    assert analyze(code) == []
  end

  # `{(is_nil(c2) or is_atom(c2)),}` parses on its own — Elixir accepts a
  # trailing comma in a tuple — so only the trailing-comma test rejects this.
  test "does not flag the last line of a multi-line when guard" do
    code = """
    defmodule WhenGuard do
      defp same?({n, _, c1}, {n, _, c2})
           when is_atom(n) and (is_nil(c1) or is_atom(c1)) and
                  (is_nil(c2) or is_atom(c2)),
           do: true
    end
    """

    assert analyze(code) == []
  end

  # The clause's `->` is two lines below the patterns, past a `when` guard, so
  # the same-line arrow lookahead cannot see it.
  test "does not flag a clause head whose arrow wrapped past a when guard" do
    code = """
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

    assert analyze(code) == []
  end

  # `?"` is a character literal — the quote is a value, not a string delimiter.
  test "does not flag after a quote character literal" do
    code = """
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

    assert analyze(code) == []
  end

  # The bare comma is real; the identical-looking text in the comment and the
  # heredoc above it is not.
  test "flags only the real bare comma, not lookalikes in a doc or comment" do
    code = """
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

    assert [%Issue{rule: :no_python_multi_return, meta: %{line: 7}}] = analyze(code)
  end
end
