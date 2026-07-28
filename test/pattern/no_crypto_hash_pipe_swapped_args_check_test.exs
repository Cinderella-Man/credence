defmodule Credence.Pattern.NoCryptoHashPipeSwappedArgsCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoCryptoHashPipeSwappedArgs

  test "flags data piped into :crypto.hash/2" do
    assert flagged?(NoCryptoHashPipeSwappedArgs, """
           defmodule PipeSwappedCryptoHash do
             def hash_file(path) do
               path
               |> File.read!()
               |> :crypto.hash(:sha256)
               |> Base.encode16(case: :lower)
             end
           end
           """)
  end

  test "leaves the correct argument order alone" do
    assert clean?(NoCryptoHashPipeSwappedArgs, """
           defmodule CleanExample do
             def hash_data(data) do
               :crypto.hash(:sha256, data)
             end
           end
           """)
  end

  test "leaves a two-argument pipe alone — the piped value is the data already" do
    assert clean?(NoCryptoHashPipeSwappedArgs, """
           defmodule TwoArg do
             def hash_data(data, salt) do
               data
               |> :crypto.hash(:sha256, salt)
             end
           end
           """)
  end

  test "leaves a piped call whose algorithm is a variable alone" do
    assert clean?(NoCryptoHashPipeSwappedArgs, """
           defmodule AlgoVar do
             def hash_data(data, algo) do
               data
               |> :crypto.hash(algo)
             end
           end
           """)
  end

  test "anchors the issue to the offending call" do
    [issue] =
      check(NoCryptoHashPipeSwappedArgs, """
      defmodule Anchored do
        def hash_file(path) do
          path
          |> File.read!()
          |> :crypto.hash(:sha256)
        end
      end
      """)

    assert issue.rule == :no_crypto_hash_pipe_swapped_args
    assert issue.meta.line == 5
  end
end
