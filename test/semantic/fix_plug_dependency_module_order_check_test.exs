defmodule Credence.Semantic.FixPlugDependencyModuleOrderCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixPlugDependencyModuleOrder

  @matching_diag %{
    severity: :error,
    message:
      "function MediaVersionApi.Plugs.AcceptVersion.init/1 is undefined (module MediaVersionApi.Plugs.AcceptVersion is not available)",
    position: 0,
    file: "credence_check.ex"
  }

  test "matches the diagnostic" do
    assert FixPlugDependencyModuleOrder.match?(@matching_diag)
  end

  test "matches the real compiler message including the trailing hint" do
    diag = %{
      severity: :error,
      message:
        "function Foo.Plugs.Bar.init/1 is undefined (module Foo.Plugs.Bar is not available). " <>
          "Make sure the module name is correct and has been specified in full (or that an alias has been defined)",
      position: 0
    }

    assert FixPlugDependencyModuleOrder.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute FixPlugDependencyModuleOrder.match?(diag)
  end

  test "ignores generic undefined function without module-not-available" do
    diag = %{severity: :error, message: "undefined function foo/1", position: 1}
    refute FixPlugDependencyModuleOrder.match?(diag)
  end

  test "ignores undefined functions other than init/1" do
    diag = %{
      severity: :error,
      message: "function Foo.bar/2 is undefined (module Foo is not available)",
      position: 0
    }

    refute FixPlugDependencyModuleOrder.match?(diag)
  end

  test "ignores the warning-severity yet-to-be-defined form" do
    diag = %{
      severity: :warning,
      message: "Foo.init/1 is undefined (module Foo is not available or is yet to be defined)",
      position: {1, 1}
    }

    refute FixPlugDependencyModuleOrder.match?(diag)
  end

  test "ignores messages where the unavailable module differs from the called one" do
    diag = %{
      severity: :error,
      message: "function Foo.init/1 is undefined (module Bar is not available)",
      position: 0
    }

    refute FixPlugDependencyModuleOrder.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert FixPlugDependencyModuleOrder.to_issue(@matching_diag).rule ==
             :fix_plug_dependency_module_order
  end

  test "should_report? is true only when the fix would reorder the source" do
    fixable = ~S"""
    defmodule MediaVersionApi.Router do
      use Plug.Router

      plug(MediaVersionApi.Plugs.AcceptVersion)
      plug(:match)
      plug(:dispatch)
    end

    defmodule MediaVersionApi.Plugs.AcceptVersion do
      def init(opts), do: opts
      def call(conn, _opts), do: conn
    end
    """

    assert FixPlugDependencyModuleOrder.should_report?(@matching_diag, fixable)

    no_dep_module = ~S"""
    defmodule MediaVersionApi.Router do
      use Plug.Router

      plug(MediaVersionApi.Plugs.AcceptVersion)
      plug(:match)
      plug(:dispatch)
    end
    """

    refute FixPlugDependencyModuleOrder.should_report?(@matching_diag, no_dep_module)
  end
end
