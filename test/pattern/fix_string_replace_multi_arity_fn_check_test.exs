defmodule Credence.Pattern.FixStringReplaceMultiArityFnCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.FixStringReplaceMultiArityFn

  test "flags String.replace/4 with arity-2 fn and empty list options" do
    assert flagged?(FixStringReplaceMultiArityFn, ~S"""
    String.replace("abc", ~r/\d/, fn match, acc -> {"*", acc} end, [])
    """)
  end

  test "flags with multi-line arity-2 fn" do
    assert flagged?(FixStringReplaceMultiArityFn, ~S"""
    String.replace("abc123", ~r/\d/, fn match, acc ->
      {"*", acc}
    end, [])
    """)
  end

  test "leaves arity-2 fn without trailing [] alone" do
    assert clean?(FixStringReplaceMultiArityFn, ~S"""
    String.replace("abc", ~r/\d/, fn match, acc -> {"*", acc} end)
    """)
  end

  test "leaves arity-1 fn with [] alone" do
    assert clean?(FixStringReplaceMultiArityFn, ~S"""
    String.replace("abc", ~r/\d/, fn match -> "*" end, [])
    """)
  end

  test "leaves string replacement with [] alone" do
    assert clean?(FixStringReplaceMultiArityFn, ~S"""
    String.replace("abc", ~r/\d/, "*", [])
    """)
  end
end
