defmodule Credence.RuleCaseTest do
  use ExUnit.Case, async: false

  alias Credence.RuleCase

  setup do
    timeout = Application.get_env(:credence, :compile_timeout_ms)
    Application.put_env(:credence, :compile_timeout_ms, 20)

    on_exit(fn ->
      if timeout == nil,
        do: Application.delete_env(:credence, :compile_timeout_ms),
        else: Application.put_env(:credence, :compile_timeout_ms, timeout)
    end)

    :ok
  end

  test "compiles?/1 contains top-level source that does not finish" do
    refute RuleCase.compiles?("Process.sleep(:infinity)")
  end

  test "call_fixed/4 contains top-level source that does not finish" do
    source = """
    defmodule Credence.RuleCaseCallFixedFixture do
      def value, do: :ok
    end

    Process.sleep(:infinity)
    """

    assert_raise MatchError, fn ->
      RuleCase.call_fixed(source, Credence.RuleCaseCallFixedFixture, :value, [])
    end
  end

  test "module_shape/1 includes guarded definitions" do
    source = """
    defmodule Credence.RuleCaseGuardedShapeFixture do
      def f(x) when is_integer(x), do: x
    end
    """

    assert RuleCase.module_shape(source) == %{docs: [], specs: [], defs: [{:f, 1}]}
  end
end
