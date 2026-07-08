defmodule Credence.Syntax.NoRescueOptionInCaseAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoRescueOptionInCase

  defp analyze(code), do: NoRescueOptionInCase.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :no_rescue_option_in_case}] =
             analyze("""
             defmodule TestModule do
               def analyze(path) do
                 case File.stream!(path) do
                   {:ok, stream} -> stream
                   {:error, reason} -> raise reason
                 rescue
                   e -> {:error, e}
                 end
               end
             end
             """)
  end

  test "leaves good code alone" do
    assert analyze("""
           defmodule TestModule do
             def analyze(path) do
               case File.stream!(path) do
                 {:ok, stream} -> stream
                 {:error, reason} -> raise reason
               end
             end
           end
           """) == []
  end

  test "leaves try-rescue alone" do
    assert analyze("""
           defmodule TestModule do
             def analyze(path) do
               try do
                 case File.stream!(path) do
                   {:ok, stream} -> stream
                   {:error, reason} -> raise reason
                 end
               rescue
                 e -> {:error, e}
               end
             end
           end
           """) == []
  end
end
