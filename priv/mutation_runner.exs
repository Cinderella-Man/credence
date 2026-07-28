# Runs ONE mutant of ONE rule against that rule's own test files, in a fresh
# BEAM, and prints a single machine-readable line. Driven by
# `Credence.Mutation.Sweep` (docs/12 C18); not meant to be run by hand.
#
# One OS process per mutant is deliberate. A mutant is arbitrary edited code: it
# can loop forever, blow the heap, or leave a rule module half-defined. In-VM
# reuse would let one bad mutant poison every later measurement in the same
# sweep, and a poisoned measurement here reads as "killed" — silently inflating
# the kill rate, which is the one number this whole task exists to report.
#
# The job is passed as an `:erlang.term_to_binary/1` file rather than argv so
# that source paths, test paths and code paths need no shell quoting.
[job_path] = System.argv()

job = job_path |> File.read!() |> :erlang.binary_to_term()

Enum.each(job.code_paths, &Code.prepend_path/1)
{:ok, _} = Application.ensure_all_started(:credence)

# The rule module is redefined on top of the one compiled into `_build`.
Code.compiler_options(ignore_module_conflict: true)

marker = fn parts -> IO.puts(Enum.join(["CREDENCE_MUTANT" | parts], " ")) end

compiled? =
  try do
    # `with_diagnostics` keeps the mutant's warnings (unused clause, always-true
    # guard, …) out of the transcript; they are noise, not signal.
    Code.with_diagnostics(fn -> Code.compile_string(job.source, job.as_path) end)
    :ok
  rescue
    error -> {:invalid, Exception.message(error)}
  catch
    kind, reason -> {:invalid, Exception.format(kind, reason)}
  end

case compiled? do
  :ok ->
    ExUnit.start(autorun: false, formatters: [], timeout: job.test_timeout_ms)

    loaded =
      try do
        Enum.each(job.test_files, &Code.require_file/1)
        :ok
      rescue
        error -> {:error, Exception.message(error)}
      catch
        kind, reason -> {:error, Exception.format(kind, reason)}
      end

    case loaded do
      :ok ->
        result = ExUnit.run()
        marker.(["RESULT", result.total, result.failures, result.excluded, result.skipped])

      {:error, message} ->
        marker.(["ERROR", inspect(message)])
    end

  {:invalid, message} ->
    marker.(["INVALID", inspect(message)])
end
