defmodule Credence.Mutation.Sweep do
  @moduledoc """
  Runs the mutants of one rule against that rule's own test files and scores
  each one killed / survived (docs/12 C18, stage 1 — report only).

  `Mix.Tasks.Credence.Mutants` is the CLI over this; the engine is separate so
  the positive control can drive the *real* execution path against a planted
  fixture rather than a mocked one.

  ## The baseline is not optional

  Every subject runs its **unmutated** source through the identical path first.
  If that is not green, the subject's numbers are discarded (`:baseline_red`),
  because a triplet that is already failing kills every mutant for the wrong
  reason and reports a perfect 1.000. A sweep that cannot tell "the tests caught
  the mutant" from "the tests were broken to begin with" is not a measurement.

  ## Statuses

    * `:killed` — at least one test failed. The triplet noticed.
    * `:survived` — every test passed. A behaviour change the tests never
      noticed (or an equivalent mutant — see `Credence.Mutation`).
    * `:timeout` — the run exceeded the wall clock. Counted with `:killed`
      (the change is observable) but reported separately.
    * `:invalid` — the mutant did not compile. Not a behaviour change at all;
      excluded from the kill rate and reported separately.
    * `:error` — the runner produced no verdict (test file failed to load, VM
      died). Excluded from the kill rate; a nonzero count means the sweep
      itself is sick and the numbers should not be published.

  `kill_rate = (killed + timeout) / (killed + survived + timeout)`, `nil` when
  the denominator is zero.
  """

  alias Credence.Mutation
  alias Credence.Mutation.Mutant

  @type subject :: %{
          required(:name) => String.t(),
          required(:layer) => atom(),
          required(:source_path) => String.t(),
          required(:test_files) => [String.t()],
          optional(:module) => module()
        }

  @type status :: :killed | :survived | :timeout | :invalid | :error

  @type result :: %{
          mutant: Mutant.t(),
          status: status(),
          tests_total: non_neg_integer() | nil,
          tests_failed: non_neg_integer() | nil,
          detail: String.t() | nil
        }

  @type report :: %{
          subject: subject(),
          baseline:
            {:green, non_neg_integer()}
            | {:red, non_neg_integer(), non_neg_integer()}
            | {:error, String.t()},
          results: [result()],
          counts: %{status() => non_neg_integer()},
          kill_rate: float() | nil,
          skipped: nil | :baseline_red | :baseline_error | :no_tests | {:generator_error, term()}
        }

  @default_timeout_s 180
  @default_test_timeout_ms 30_000
  @marker "CREDENCE_MUTANT"

  @doc """
  Sweep one subject. Options:

    * `:cap` — mutants per subject (default `Credence.Mutation.default_cap/0`).
    * `:timeout_s` — wall clock per mutant run (default `#{@default_timeout_s}`).
    * `:test_timeout_ms` — ExUnit per-test timeout inside the run
      (default `#{@default_test_timeout_ms}`).
    * `:code_paths` — ebin dirs the runner prepends (default: every
      `lib/*/ebin` beside the loaded `:credence` build).
    * `:root` — project root the runner is executed from (default `File.cwd!/0`).
    * `:on_result` — `fun(result)` called as each mutant finishes, for progress.
  """
  @spec run(subject(), keyword()) :: report()
  def run(subject, opts \\ []) do
    source = File.read!(subject.source_path)

    if subject.test_files == [] do
      skip(subject, :no_tests, {:error, "no test files"})
    else
      case baseline(subject, source, opts) do
        {:green, _total} = ok -> sweep(subject, source, ok, opts)
        {:red, _, _} = red -> skip(subject, :baseline_red, red)
        {:error, _} = err -> skip(subject, :baseline_error, err)
      end
    end
  end

  @doc """
  The subprocess-visible verdict for one source text. Exposed so the baseline
  and the mutants provably travel the same code path.
  """
  @spec execute(subject(), String.t(), keyword()) ::
          {:ok, non_neg_integer(), non_neg_integer()}
          | {:invalid, String.t()}
          | {:timeout, String.t()}
          | {:error, String.t()}
  def execute(subject, source, opts) do
    root = Keyword.get_lazy(opts, :root, &File.cwd!/0)
    timeout_s = Keyword.get(opts, :timeout_s, @default_timeout_s)

    job = %{
      code_paths: Keyword.get_lazy(opts, :code_paths, &default_code_paths/0),
      source: source,
      as_path: subject.source_path,
      test_files: subject.test_files,
      test_timeout_ms: Keyword.get(opts, :test_timeout_ms, @default_test_timeout_ms)
    }

    job_path =
      Path.join(
        System.tmp_dir!(),
        "credence_mutant_#{System.unique_integer([:positive])}_#{:erlang.phash2(job)}.job"
      )

    File.write!(job_path, :erlang.term_to_binary(job))

    try do
      {command, args} = runner_command(job_path, timeout_s)
      {output, exit_code} = System.cmd(command, args, cd: root, stderr_to_stdout: true)
      interpret(output, exit_code)
    after
      File.rm(job_path)
    end
  end

  # --- internals -----------------------------------------------------------

  defp sweep(subject, source, baseline, opts) do
    cap = Keyword.get(opts, :cap, Mutation.default_cap())
    on_result = Keyword.get(opts, :on_result, fn _ -> :ok end)

    case Mutation.mutants(source, cap: cap, id_prefix: "#{subject.name}:") do
      {:error, reason} ->
        skip(subject, {:generator_error, reason}, baseline)

      {:ok, mutants} ->
        results =
          Enum.map(mutants, fn mutant ->
            result = score(subject, source, mutant, opts)
            on_result.(result)
            result
          end)

        finalize(subject, baseline, results, nil)
    end
  end

  defp score(subject, source, mutant, opts) do
    mutated = Mutation.apply_mutant(source, mutant)

    case execute(subject, mutated, opts) do
      {:ok, total, 0} ->
        %{mutant: mutant, status: :survived, tests_total: total, tests_failed: 0, detail: nil}

      {:ok, total, failed} ->
        %{mutant: mutant, status: :killed, tests_total: total, tests_failed: failed, detail: nil}

      {:invalid, detail} ->
        %{mutant: mutant, status: :invalid, tests_total: nil, tests_failed: nil, detail: detail}

      {:timeout, detail} ->
        %{mutant: mutant, status: :timeout, tests_total: nil, tests_failed: nil, detail: detail}

      {:error, detail} ->
        %{mutant: mutant, status: :error, tests_total: nil, tests_failed: nil, detail: detail}
    end
  end

  defp baseline(subject, source, opts) do
    case execute(subject, source, opts) do
      {:ok, total, 0} -> {:green, total}
      {:ok, total, failed} -> {:red, total, failed}
      {_other, detail} -> {:error, detail}
    end
  end

  defp skip(subject, reason, baseline) do
    finalize(subject, baseline, [], reason)
  end

  defp finalize(subject, baseline, results, skipped) do
    counts =
      Enum.reduce(results, empty_counts(), fn %{status: status}, acc ->
        Map.update!(acc, status, &(&1 + 1))
      end)

    %{
      subject: subject,
      baseline: baseline,
      results: results,
      counts: counts,
      kill_rate: kill_rate(counts),
      skipped: skipped
    }
  end

  defp empty_counts, do: %{killed: 0, survived: 0, timeout: 0, invalid: 0, error: 0}

  @doc "Kill rate from a status-count map. `nil` when nothing scorable ran."
  @spec kill_rate(%{status() => non_neg_integer()}) :: float() | nil
  def kill_rate(counts) do
    denominator = counts.killed + counts.survived + counts.timeout

    if denominator == 0, do: nil, else: (counts.killed + counts.timeout) / denominator
  end

  defp interpret(output, exit_code) do
    line =
      output
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, @marker <> " "))

    case {line, exit_code} do
      {nil, 124} ->
        {:timeout, "wall clock exceeded"}

      {nil, 137} ->
        {:timeout, "killed after wall clock exceeded"}

      {nil, code} ->
        {:error, "no verdict (exit #{code}): #{String.slice(output, -400..-1//1)}"}

      {marker_line, _} ->
        case String.split(marker_line, " ", parts: 3) do
          [@marker, "RESULT", rest] ->
            [total, failures | _] = String.split(rest, " ")
            {:ok, String.to_integer(total), String.to_integer(failures)}

          [@marker, "INVALID", detail] ->
            {:invalid, detail}

          [@marker, "ERROR", detail] ->
            {:error, detail}

          other ->
            {:error, "unparseable verdict #{inspect(other)}"}
        end
    end
  end

  # `timeout(1)` is the backstop for a mutant that hangs past ExUnit's own
  # per-test timeout (an infinite loop inside a `Macro.prewalk` never yields to
  # the test's timer, so ExUnit alone cannot always cut it short). Where the
  # coreutils binary is absent the sweep still runs — it just loses that
  # backstop, which the task reports.
  defp runner_command(job_path, timeout_s) do
    elixir = System.find_executable("elixir") || "elixir"
    runner = runner_script()

    case System.find_executable("timeout") do
      nil -> {elixir, [runner, job_path]}
      timeout -> {timeout, ["--kill-after=5", "#{timeout_s}", elixir, runner, job_path]}
    end
  end

  @doc "Absolute path of the per-mutant runner script."
  @spec runner_script() :: String.t()
  def runner_script do
    :credence
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("mutation_runner.exs")
  end

  @doc "True when the `timeout(1)` backstop is available on this machine."
  @spec timeout_backstop?() :: boolean()
  def timeout_backstop?, do: System.find_executable("timeout") != nil

  # Derived from the running build rather than from `Mix.Project`, so the engine
  # stays usable from a plain `elixir` shell and from the sweep's own tests.
  defp default_code_paths do
    lib_root = :credence |> :code.lib_dir() |> to_string() |> Path.dirname()
    Path.wildcard(Path.join([lib_root, "*", "ebin"]))
  end
end
