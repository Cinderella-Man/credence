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
end
