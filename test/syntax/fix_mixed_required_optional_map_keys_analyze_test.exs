defmodule Credence.Syntax.FixMixedRequiredOptionalMapKeysAnalyzeTest do
  use ExUnit.Case, async: true

  alias Credence.Issue
  alias Credence.Syntax.FixMixedRequiredOptionalMapKeys

  defp analyze(code), do: FixMixedRequiredOptionalMapKeys.analyze(code)

  describe "flags a keyword entry before an arrow entry in a map" do
    # Both field samples from docs/18: the `@type` shape the rule is named for, and the
    # map literal that raises the byte-identical error.
    test "the type field sample" do
      assert [%Issue{rule: :fix_mixed_required_optional_map_keys}] =
               analyze("@type t :: %{state: atom(), optional(atom()) => any()}")
    end

    test "the literal field sample" do
      assert [%Issue{rule: :fix_mixed_required_optional_map_keys}] =
               analyze("x = %{state: :init, optional(k) => v}")
    end

    test "a quoted key" do
      assert analyze(~S'x = %{"a b": 1, "k" => 2}') != []
    end

    test "a key ending in a question mark" do
      assert analyze(~S'x = %{valid?: 1, "k" => 2}') != []
    end

    test "a multi-line map" do
      assert analyze("""
             x = %{
               a: 1,
               "k" => 2
             }
             """) != []
    end

    # The parser stops inside the INNER map, and that is the one repaired — the outer
    # `ok:` is the container's only entry and so perfectly legal.
    test "an inner map is the culprit, not the outer one" do
      assert [_one] = analyze(~S'x = %{ok: %{a: 1, "k" => 2}}')
    end
  end

  # `analyze/1` and `fix/1` share one loop, so the issue count is the repair count.
  test "reports one issue per entry that needs rewriting" do
    assert length(analyze(~S'x = %{a: 1, b: 2, "k" => 3}')) == 2
  end

  test "reports the line the key is on" do
    assert [issue] =
             analyze("""
             # a comment
             x = 1
             z = %{a: 1, "k" => 2}
             """)

    assert issue.meta.line == 3
  end

  describe "declines" do
    test "source that parses" do
      assert analyze(~S'x = %{"k" => 2, a: 1}') == []
    end

    test "a map that was already arrow form" do
      assert analyze(~S'x = %{:a => 1, "k" => 2}') == []
    end

    # A list and a tuple raise the SAME parse error, and arrow-ifying them is invalid
    # (`[:a => 1, 2]` is `syntax error before: '=>'`). Their repair is move-last, a
    # different rule with a different argument.
    test "a list, where arrow form is not valid syntax" do
      assert analyze("x = [a: 1, 2]") == []
    end

    test "a tuple, where arrow form is not valid syntax" do
      assert analyze("x = {a: 1, 2}") == []
    end

    # `FixKeywordBeforePositionalArgument` already owns this shape.
    test "a call, which is the sibling rule's job" do
      assert analyze("f(a: 1, 2)") == []
    end

    # Requiring `%` immediately before the `{` is what excludes structs, and it should:
    # a struct cannot take a `=>` key at all, so arrow-ifying makes the file parse
    # while leaving the module just as broken. That is a different defect.
    test "a struct, where the repair would not fix the module" do
      assert analyze(~S'x = %Foo{a: 1, "k" => 2}') == []
    end

    test "a decoy inside a string, with an unrelated parse error elsewhere" do
      assert analyze("""
             x = "%{a: 1, 2}"
             y = (
             """) == []
    end

    test "an unrelated syntax error" do
      assert analyze("x = foo((1") == []
    end
  end
end
