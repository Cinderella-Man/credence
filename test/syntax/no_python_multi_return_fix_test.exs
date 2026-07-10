defmodule Credence.Syntax.NoPythonMultiReturnFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoPythonMultiReturn

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
end
