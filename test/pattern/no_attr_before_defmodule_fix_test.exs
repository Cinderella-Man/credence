defmodule Credence.Pattern.NoAttrBeforeDefmoduleFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoAttrBeforeDefmodule

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoAttrBeforeDefmodule, code, [])
  end

  describe "moves attrs into the module" do
    test "single @moduledoc" do
      code = "@moduledoc \"some doc\"\ndefmodule Foo do\n  def bar, do: :ok\nend\n"
      expected = "defmodule Foo do\n  @moduledoc \"some doc\"\n  def bar, do: :ok\nend\n"
      assert fix(code) == expected
    end

    test "multiple doc/spec attrs, in order" do
      code = "@moduledoc \"m\"\n@doc \"f\"\n@spec foo() :: :ok\ndefmodule Foo do\n  def foo, do: :ok\nend\n"

      expected =
        "defmodule Foo do\n  @moduledoc \"m\"\n  @doc \"f\"\n  @spec foo() :: :ok\n  def foo, do: :ok\nend\n"

      assert fix(code) == expected
    end

    test "heredoc @moduledoc is re-indented inside the module" do
      code = "@moduledoc \"\"\"\nSome doc\n\"\"\"\ndefmodule Foo do\n  def bar, do: :ok\nend\n"

      expected =
        "defmodule Foo do\n  @moduledoc \"\"\"\n  Some doc\n  \"\"\"\n  def bar, do: :ok\nend\n"

      assert fix(code) == expected
    end

    test "non-attr code before the attrs stays at the top level" do
      code = "IO.puts(\"hi\")\n@moduledoc \"d\"\ndefmodule Foo do\n  def bar, do: :ok\nend\n"

# the blank line left where the attr was is cosmetic (mix format runs after rules)
      expected =
        "IO.puts(\"hi\")\n\ndefmodule Foo do\n  @moduledoc \"d\"\n  def bar, do: :ok\nend\n"

      assert fix(code) == expected
    end
  end

  describe "leaves code unchanged" do
    test "attribute already inside the module" do
      code = "defmodule Foo do\n  @moduledoc \"d\"\n  def bar, do: :ok\nend\n"
      assert fix(code) == code
    end

    test "no defmodule at all" do
      code = "@moduledoc \"d\"\ndef foo, do: :ok\n"
      assert fix(code) == code
    end

    test "non doc/spec attribute (@impl)" do
      code = "@impl true\ndefmodule Foo do\n  def bar, do: :ok\nend\n"
      assert fix(code) == code
    end

    test "plain module with no leading attrs" do
      code = "defmodule Foo do\n  def bar, do: :ok\nend\n"
      assert fix(code) == code
    end
  end

  describe "round-trip" do
    test "fixed code compiles and has no remaining issues" do
      code =
        "@moduledoc \"d\"\n@spec rt_foo() :: :ok\ndefmodule RtAttrFoo do\n  def rt_foo, do: :ok\nend\n"

      fixed = fix(code)

      assert NoAttrBeforeDefmodule.check(Sourceror.parse_string!(fixed), []) == []
      # the original does not compile (attr outside module); the fixed code must
      assert [{RtAttrFoo, _bytecode}] = Code.compile_string(fixed)
    end
  end
end
