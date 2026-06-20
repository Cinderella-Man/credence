defmodule Credence.QuietFormatter do
  @moduledoc """
  An ExUnit formatter that suppresses the per-test progress dots.

  It prints nothing for passing tests, the full (colored, diffed) failure report
  for failures / invalid (`setup` errored) tests and module (`setup_all`)
  failures, and the same one-line count summary `ExUnit.CLIFormatter` prints at
  the end — just without the `....F...` stream that scrolls a multi-thousand-test
  run off the screen.

  Wired up in `test/test_helper.exs` via `ExUnit.start(formatters: […])`.
  """

  use GenServer

  import ExUnit.Formatter,
    only: [format_times: 1, format_test_failure: 5, format_test_all_failure: 5]

  @impl true
  def init(opts) do
    state = %{
      seed: opts[:seed],
      width: width(),
      colors: colors(opts),
      # counts per test_type (:test / :property / :doctest), excluding excluded
      counter: %{},
      failures: 0,
      invalid: 0,
      skipped: 0,
      excluded: 0
    }

    {:ok, state}
  end

  @impl true
  # passing test — count only, no dot
  def handle_cast({:test_finished, %ExUnit.Test{state: nil} = test}, state),
    do: {:noreply, count(state, test)}

  def handle_cast({:test_finished, %ExUnit.Test{state: {:excluded, _}}}, state),
    do: {:noreply, %{state | excluded: state.excluded + 1}}

  def handle_cast({:test_finished, %ExUnit.Test{state: {:skipped, _}} = test}, state),
    do: {:noreply, count(%{state | skipped: state.skipped + 1}, test)}

  def handle_cast({:test_finished, %ExUnit.Test{state: {:invalid, _}} = test}, state) do
    counter = state.failures + 1
    IO.puts(format_test_failure(test, [], counter, state.width, &formatter(&1, &2, state)))
    {:noreply, count(%{state | invalid: state.invalid + 1, failures: counter}, test)}
  end

  def handle_cast({:test_finished, %ExUnit.Test{state: {:failed, failures}} = test}, state) do
    counter = state.failures + 1
    IO.puts(format_test_failure(test, failures, counter, state.width, &formatter(&1, &2, state)))
    {:noreply, count(%{state | failures: counter}, test)}
  end

  # setup_all failure: reported once at module level (its tests arrive as :invalid)
  def handle_cast(
        {:module_finished, %ExUnit.TestModule{state: {:failed, failures}} = module},
        state
      ) do
    counter = state.failures + 1

    IO.puts(
      format_test_all_failure(module, failures, counter, state.width, &formatter(&1, &2, state))
    )

    {:noreply, %{state | failures: counter}}
  end

  def handle_cast({:suite_finished, times_us}, state) do
    type_counts =
      state.counter
      |> Enum.sort()
      |> Enum.map(fn {type, n} ->
        "#{n} #{pluralize(n, type, ExUnit.plural_rule(to_string(type)))}"
      end)

    failures = "#{state.failures} #{pluralize(state.failures, "failure", "failures")}"

    extras =
      [{state.invalid, "invalid"}, {state.skipped, "skipped"}, {state.excluded, "excluded"}]
      |> Enum.filter(fn {n, _} -> n > 0 end)
      |> Enum.map(fn {n, label} -> "#{n} #{label}" end)

    summary = Enum.join(type_counts ++ [failures] ++ extras, ", ")
    color = if state.failures > 0, do: :red, else: :green

    IO.puts("")
    IO.puts(format_times(times_us))
    IO.puts(colorize(color, summary, state))
    if state.seed, do: IO.puts("Randomized with seed #{state.seed}")
    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}

  # bump the per-test_type counter (mirrors CLIFormatter's test_counter)
  defp count(state, %ExUnit.Test{tags: tags}) do
    type = Map.get(tags, :test_type, :test)
    %{state | counter: Map.update(state.counter, type, 1, &(&1 + 1))}
  end

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_, _singular, plural), do: plural

  defp width do
    case :io.columns() do
      {:ok, w} -> max(40, w)
      _ -> 80
    end
  end

  defp colors(opts), do: Keyword.put_new(opts[:colors] || [], :enabled, IO.ANSI.enabled?())

  # ── Color/diff hooks (same contract ExUnit.CLIFormatter uses) ──────────────

  defp formatter(:diff_enabled?, _, %{colors: colors}), do: colors[:enabled]
  defp formatter(:error_info, msg, config), do: colorize(:red, msg, config)
  defp formatter(:extra_info, msg, config), do: colorize(:cyan, msg, config)
  defp formatter(:location_info, msg, config), do: colorize([:bright, :black], msg, config)
  defp formatter(:diff_delete, msg, config), do: colorize(:red, msg, config)

  defp formatter(:diff_delete_whitespace, msg, config),
    do: colorize(IO.ANSI.color_background(2, 0, 0), msg, config)

  defp formatter(:diff_insert, msg, config), do: colorize(:green, msg, config)

  defp formatter(:diff_insert_whitespace, msg, config),
    do: colorize(IO.ANSI.color_background(0, 2, 0), msg, config)

  defp formatter(_, msg, _config), do: msg

  defp colorize(escape, string, %{colors: colors}) do
    if colors[:enabled] do
      [escape, string, :reset]
      |> IO.ANSI.format_fragment(true)
      |> IO.iodata_to_binary()
    else
      string
    end
  end
end
