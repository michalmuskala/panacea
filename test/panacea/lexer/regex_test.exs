defmodule Panacea.Lexer.RegexTest do
  use ExUnit.Case, async: true

  describe "parse/1" do
    import Panacea.Lexer.Regex, only: [parse: 1]

    test "empty" do
      assert {:ok, :epsilon} == parse("")
    end

    test "sequence" do
      assert {:ok, {:alt, [lit: 'a', lit: 'b', lit: 'c']}} == parse("a|b|c")
      assert {:ok, {:seq, [lit: 'a', lit: 'b', lit: 'c']}} == parse("abc")
      assert {:ok, {:alt, [{:lit, 'a'}, :epsilon]}} == parse("a|")
      assert {:error, {:illegal_char, "*"}} == parse("a|*")
    end

    test "repeat" do
      assert {:ok, {:kclosure, {:lit, 'a'}}} == parse("a*")
      assert {:ok, {:pclosure, {:lit, 'a'}}} == parse("a+")
      assert {:ok, {:optional, {:lit, 'a'}}} == parse("a?")
      assert {:ok, {:seq, [{:lit, 'a'}, {:optional, {:lit, 'a'}}]}} == parse("a{1,2}")
      assert {:ok, {:seq, [{:pclosure, {:lit, 'a'}}]}} == parse("a{1,}")
      assert {:ok, {:seq, [{:lit, 'a'}]}}              == parse("a{1}")
    end

    test "classes" do
      assert {:ok, {:char_class, [{:range, ?a, ?z}, ?K]}} == parse("[a-zK]")
      assert {:ok, {:comp_class, [{:range, ?0, ?9}, {:range, ?1, ?2}]}} == parse("[^0-91-2]")
      assert {:ok, {:comp_class, [?\n]}} == parse(".")
    end
  end
end
