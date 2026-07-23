defmodule Credence.Semantic.FixInvalidListTypespecSyntaxCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixInvalidListTypespecSyntax

  @real_diag %{
    severity: :error,
    message: "credence_check.ex:6: unexpected list in typespec: [integer(), integer()]",
    position: 6,
    file: "credence_check.ex"
  }

  describe "match?/1" do
    test "matches the real diagnostic" do
      assert FixInvalidListTypespecSyntax.match?(@real_diag)
    end

    test "matches with warning severity" do
      diag = %{@real_diag | severity: :warning}
      assert FixInvalidListTypespecSyntax.match?(diag)
    end

    test "matches with tuple position" do
      diag = %{@real_diag | position: {6, 3}}
      assert FixInvalidListTypespecSyntax.match?(diag)
    end

    test "ignores unrelated diagnostics" do
      diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
      refute FixInvalidListTypespecSyntax.match?(diag)
    end

    test "ignores nil message" do
      diag = %{severity: :error, message: nil, position: {1, 1}}
      refute FixInvalidListTypespecSyntax.match?(diag)
    end
  end

  describe "to_issue/1" do
    test "attributes the issue to this rule" do
      assert FixInvalidListTypespecSyntax.to_issue(@real_diag).rule ==
               :fix_invalid_list_typespec_syntax
    end

    test "preserves the message" do
      assert FixInvalidListTypespecSyntax.to_issue(@real_diag).message == @real_diag.message
    end

    test "extracts line from tuple position" do
      diag = %{severity: :error, message: "unexpected list in typespec", position: {7, 3}}
      assert FixInvalidListTypespecSyntax.to_issue(diag).meta.line == 7
    end

    test "extracts line from integer position" do
      assert FixInvalidListTypespecSyntax.to_issue(@real_diag).meta.line == 6
    end
  end
end
