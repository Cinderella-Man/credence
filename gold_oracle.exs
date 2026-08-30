dataset_root = System.get_env("DATASET_ROOT", "../elixir-sft-dataset")

golds =
  dataset_root
  |> Path.join("tasks/*_01/solution.ex")
  |> Path.wildcard()
  |> Enum.sort()

if golds == [], do: raise("no gold solutions found under #{dataset_root}")

{elapsed_us, results} =
  :timer.tc(fn ->
    golds
    |> Task.async_stream(
      fn path ->
        source = File.read!(path)
        task = path |> Path.dirname() |> Path.basename()

        issues =
          try do
            Credence.Pattern.analyze(source)
          rescue
            error -> [%{rule: {:crash, inspect(error.__struct__)}}]
          end

        {task, Enum.map(issues, & &1.rule)}
      end,
      max_concurrency: System.schedulers_online(),
      timeout: 120_000,
      ordered: false
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> raise "gold analysis task exited: #{inspect(reason)}"
    end)
  end)

findings =
  Enum.flat_map(results, fn {task, rules} ->
    for rule <- rules,
        rule != :parse_error,
        not match?({:crash, _}, rule),
        do: {rule, task}
  end)

IO.puts("golds=#{length(results)} time=#{Float.round(elapsed_us / 1_000_000, 1)}s")
IO.puts("clean=#{Enum.count(results, fn {_, rules} -> rules == [] end)}")

findings
|> Enum.frequencies_by(&elem(&1, 0))
|> Enum.sort_by(fn {_, count} -> -count end)
|> Enum.each(fn {rule, count} -> IO.puts("  #{count}\t#{rule}") end)
