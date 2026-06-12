defmodule Credence.NormalizeTestsTaskTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Credence.NormalizeTests

  # The task prints `[normalize] …` via `Mix.shell().info/1` — correct as a CLI,
  # but pure noise interleaved with the test dots here. Silence `info` (errors
  # still print) for this module only and restore it afterwards.
  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Quiet)
    on_exit(fn -> Mix.shell(shell) end)
    :ok
  end

  # Two `\`-terminated heredocs: SAFE (removal tolerated) + LOADBEARING (removal
  # would change the byte-exact value). Markers let a fake runner decide.
  @content ~S'''
  defmodule Probe do
    test "safe" do
      code = """
      SAFE\
      """
      _ = code
    end

    test "load-bearing" do
      code = """
      LOADBEARING\
      """
      _ = code
    end
  end
  '''

  defp in_temp(content, fun) do
    path = Path.join(System.tmp_dir!(), "norm_#{System.unique_integer([:positive])}_test.exs")
    File.write!(path, content)
    try do
      fun.(path)
    after
      File.rm(path)
    end
  end

  test "candidates/1 finds only the trailing-`\\` heredoc lines" do
    cands = NormalizeTests.candidates(@content)
    assert length(cands) == 2
  end

  test "removes every `\\` when the file stays green (fast path)" do
    in_temp(@content, fn path ->
      assert {:ok, 2} = NormalizeTests.normalize_file(path, run: fn _ -> 0 end)
      out = File.read!(path)
      refute out =~ "SAFE\\"
      refute out =~ "LOADBEARING\\"
      # bodies otherwise intact
      assert out =~ "SAFE"
      assert out =~ "LOADBEARING"
    end)
  end

  test "keeps a load-bearing `\\` (reverts) while removing the safe one (greedy)" do
    # red iff LOADBEARING lost its `\` (i.e. "LOADBEARING" is immediately followed
    # by a newline). SAFE's removal is always tolerated.
    run = fn p ->
      if String.contains?(File.read!(p), "LOADBEARING\n"), do: 1, else: 0
    end

    in_temp(@content, fn path ->
      assert {:ok, 1} = NormalizeTests.normalize_file(path, run: run)
      out = File.read!(path)
      refute out =~ "SAFE\\"
      assert out =~ "LOADBEARING\\"
    end)
  end

  test "skips a file whose baseline is already red" do
    in_temp(@content, fn path ->
      assert {:skip, 0} = NormalizeTests.normalize_file(path, run: fn _ -> 1 end)
      # untouched
      assert File.read!(path) == @content
    end)
  end

  test "no-op when there are no trailing-`\\` heredocs" do
    in_temp("defmodule X do\nend\n", fn path ->
      assert {:noop, 0} = NormalizeTests.normalize_file(path, run: fn _ -> 0 end)
    end)
  end
end
