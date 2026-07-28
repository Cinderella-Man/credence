defmodule Credence.Pattern.NoHallucinatedEtsKeytypeOptionCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoHallucinatedEtsKeytypeOption

  test "flags keytype: :term in an :ets.new/2 option list" do
    assert flagged?(NoHallucinatedEtsKeytypeOption, """
           defmodule HallucinatedEtsKeyType do
             def create_table do
               :ets.new(:my_table, [:set, :public, :named_table, keytype: :term, read_concurrency: true])
             end
           end
           """)
  end

  test "leaves an option list without keytype alone" do
    assert clean?(NoHallucinatedEtsKeytypeOption, """
           defmodule CleanETS do
             def create_table do
               :ets.new(:my_table, [:set, :public, :named_table, read_concurrency: true])
             end
           end
           """)
  end

  test "leaves keytype with a non-:term value alone — out of scope" do
    assert clean?(NoHallucinatedEtsKeytypeOption, """
           defmodule KeytypeBag do
             def create do
               :ets.new(:test, [:set, keytype: :bag])
             end
           end
           """)
  end

  test "leaves the tuple form {:keytype, :term} alone — out of scope" do
    assert clean?(NoHallucinatedEtsKeytypeOption, """
           defmodule KeytypeTuple do
             def create do
               :ets.new(:test, [:set, {:keytype, :term}])
             end
           end
           """)
  end

  test "leaves options passed as a variable alone — not a literal list" do
    assert clean?(NoHallucinatedEtsKeytypeOption, """
           defmodule OptsVar do
             def create do
               opts = [keytype: :term]
               :ets.new(:test, opts)
             end
           end
           """)
  end

  test "anchors the issue to the offending call" do
    [issue] =
      check(NoHallucinatedEtsKeytypeOption, """
      defmodule Anchored do
        def create do
          :ets.new(:test, [:set, keytype: :term])
        end
      end
      """)

    assert issue.rule == :no_hallucinated_ets_keytype_option
    assert issue.meta.line == 3
  end
end
