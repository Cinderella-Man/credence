defmodule Credence.Semantic.NoPlugUploadSizeFieldCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoPlugUploadSizeField

  test "matches the diagnostic" do
    diag = %{severity: :error, message: "unknown key :size for struct Plug.Upload", position: {12, 16}}
    assert NoPlugUploadSizeField.match?(diag)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :error, message: "unrelated", position: {1, 1}}
    refute NoPlugUploadSizeField.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :error, message: "unknown key :size for struct Plug.Upload", position: {12, 16}}
    assert NoPlugUploadSizeField.to_issue(diag).rule == :no_plug_upload_size_field
  end
end
