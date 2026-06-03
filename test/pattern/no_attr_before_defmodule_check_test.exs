defmodule Credence.Pattern.NoAttrBeforeDefmoduleCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoAttrBeforeDefmodule
  alias Credence.Issue

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoAttrBeforeDefmodule.check(ast, [])
  end

  describe "detects" do
    test "@moduledoc before defmodule" do
      code = "@moduledoc \"some doc\"\ndefmodule Foo do\n  def bar, do: :ok\nend\n"
      assert [%Issue{rule: :no_attr_before_defmodule}] = check(code)
    end

    test "multiple doc/spec attrs before defmodule" do
      code = "@moduledoc \"m\"\n@doc \"f\"\n@spec foo() :: :ok\ndefmodule Foo do\n  def foo, do: :ok\nend\n"
      assert [%Issue{}] = check(code)
    end

    test "heredoc @moduledoc before defmodule" do
      code = "@moduledoc \"\"\"\nSome doc\n\"\"\"\ndefmodule Foo do\n  def bar, do: :ok\nend\n"
      assert [%Issue{}] = check(code)
    end

    test "fires even when other code precedes the attrs" do
      code = "IO.puts(\"hi\")\n@moduledoc \"d\"\ndefmodule Foo do\n  def bar, do: :ok\nend\n"
      assert [%Issue{}] = check(code)
    end

    test "reports the attribute's line number" do
      code = "@moduledoc \"d\"\ndefmodule Foo do\n  def bar, do: :ok\nend\n"
      assert [%Issue{meta: %{line: 1}}] = check(code)
    end
  end

  describe "does not flag" do
    test "attribute already inside the module" do
      code = "defmodule Foo do\n  @moduledoc \"d\"\n  def bar, do: :ok\nend\n"
      assert check(code) == []
    end

    test "no defmodule at all (we never invent a module)" do
      code = "@moduledoc \"d\"\ndef foo, do: :ok\n"
      assert check(code) == []
    end

    test "non doc/spec attribute (@impl) is left where it is" do
      code = "@impl true\ndefmodule Foo do\n  def bar, do: :ok\nend\n"
      assert check(code) == []
    end

    test "plain module with no leading attrs" do
      code = "defmodule Foo do\n  def bar, do: :ok\nend\n"
      assert check(code) == []
    end
  end
end
