defmodule Panacea.Lexer.Regex do
  @moduledoc """
  This module implements a basic parser for regular expressions.

  Used grammar is similar to the one used by leex and it is equivalent to the
  one used in AWK, except that we allow ^ $ to be used anywhere and fail
  in the matching.

  The grammar of the current regular expressions. The actual parser
  is a recursive descent implementation of the grammar.

  reg -> alt : '$1'.
  alt -> seq "|" seq ... : {alt,['$1','$2'...]}.
  seq -> repeat repeat ... : {seq,['$1','$2'...]}.
  repeat -> repeat "*" : {kclosure,'$1'}.
  repeat -> repeat "+" : {pclosure,'$1'}.
  repeat -> repeat "?" : {optional,'$1'}.
  repeat -> repeat "{" [Min],[Max] "}" : {interval,'$1',Min,Max}
  repeat -> single : '$1'.
  single -> "(" reg ")" : {sub,'$2',Number}.
  single -> "^" : bos/bol.
  single -> "$" : eos/eol.
  single -> "." : any.
  single -> "[" class "]" : {char_class,char_class('$2')}
  single -> "[" "^" class "]" : {comp_class,char_class('$3')}.
  single -> "\"" chars "\"" : {lit,'$2'}.
  single -> "\\" char : {lit,['$2']}.
  single -> char : {lit,['$1']}.
  single -> empty : epsilon.

  It handles regular elixir escapes.

  """

  def parse!(string) do
    case parse(string) do
      {:ok, reg} ->
        reg
      {:error, error} ->
        raise "error parsing regex: #{inspect error}"
    end
  end

  def parse(string) do
    # string = unescape_string(string)
    try do
      reg(string, 0, %{})
    catch
      {:parse_error, error} ->
        {:error, error}
    else
      {re, _, ""} ->
        {:ok, re}
      {_, _, <<c :: utf8, _rest :: binary>>} ->
        {:error, {:illegal_char, <<c :: utf8>>}}
    end
  end

  defp parse_error(error), do: throw({:parse_error, error})

  defp reg(str, idx, state), do: alt(str, idx, state)

  defp alt(str, idx, state) do
    {seq, idx, rest} = seq(str, idx, state)
    case alt_rest(rest, idx, state) do
      {[],   idx, rest} -> {seq, idx, rest}
      {seqs, idx, rest} -> {{:alt, [seq | seqs]}, idx, rest}
    end
  end

  defp alt_rest("|" <> rest, idx, state) do
    {seq,  idx, rest} = seq(rest, idx, state)
    {seqs, idx, rest} = alt_rest(rest, idx, state)
    {[seq | seqs], idx, rest}
  end
  defp alt_rest(rest, idx, _), do: {[], idx, rest}

  # Parse a sequence, for empty return epsilon
  defp seq(str, idx, state) do
    case seq_rest(str, idx, state) do
      {[],    idx, rest} -> {:epsilon, idx, rest}
      {[seq], idx, rest} -> {seq, idx, rest}
      {seqs,  idx, rest} -> {{:seq, seqs}, idx, rest}
    end
  end

  defp seq_rest(<<c :: utf8, _ :: binary>> = str, idx, state) when not c in '|)' do
    {repeat, idx, rest} = repeat(str, idx, state)
    {seqs,   idx, rest} = seq_rest(rest, idx, state)
    {[repeat | seqs], idx, rest}
  end
  defp seq_rest(rest, idx, _), do: {[], idx, rest}

  defp repeat(str, idx, state) do
    {single, idx, rest} = single(str, idx, str)
    repeat_rest(rest, idx, single, state)
  end

  defp repeat_rest("*" <> rest, idx, single, state),
    do: repeat_rest(rest, idx, {:kclosure, single}, state)
  defp repeat_rest("+" <> rest, idx, single, state),
    do: repeat_rest(rest, idx, {:pclosure, single}, state)
  defp repeat_rest("?" <> rest, idx, single, state),
    do: repeat_rest(rest, idx, {:optional, single}, state)
  defp repeat_rest("{" <> rest, idx, single, state) do
    case interval_range(rest) do
      {min, max, "}" <> rest} when is_integer(min) and (is_integer(max) and min <= max) or is_atom(max) ->
        repeat_rest(rest, idx, unroll_interval(single, min, max), state)
      {_, _, error_rest} ->
        parse_error({:interval_range, string_between("{" <> rest, error_rest)})
    end
  end
  defp repeat_rest(rest, idx, single, _), do: {single, idx, rest}

  defp single("(" <> rest, idx, state) do
    case reg(rest, idx + 1, state) do
      {reg, idx, ")" <> rest} -> {reg, idx, rest}
      _                       -> parse_error({:unterminated, "("})
    end
  end
  defp single("." <> rest, idx, _state),
    do: {{:comp_class, '\n'}, idx, rest}
  defp single("[^" <> rest, idx, state) do
    case char_class(rest, state) do
      {class, "]" <> rest} -> {{:comp_class, class}, idx, rest}
      _                    -> parse_error({:unterminated, "["})
    end
  end
  defp single("[" <> rest, idx, state) do
    case char_class(rest, state) do
      {class, "]" <> rest} -> {{:char_class, class}, idx, rest}
      _                    -> parse_error({:unterminated, "["})
    end
  end
  defp single(<<char :: utf8, rest :: binary>>, idx, state) do
    if special_char?(char, state) do
      parse_error({:illegal_char, <<char :: utf8>>, rest})
    else
      {char, rest} = char(char, rest)
      {{:lit, [char]}, idx, rest}
    end
  end

  defp char(?\\, <<char :: utf8, rest :: binary>>), do: {char, rest}
  defp char(char, rest),                            do: {char, rest}

  defp char_class("]" <> rest, state),
    do: char_class(rest, [?\]], state)
  defp char_class(rest, state),
    do: char_class(rest, [], state)

  defp char_class("]" <> _ = str, class, _state) do
    {Enum.reverse(class), str}
  end
  defp char_class(<<char :: utf8, rest :: binary>> = str, class, state) do
    case char(char, rest) do
      {char_beg, <<?-, char :: utf8, rest :: binary>>} when char != ?\] ->
        case char(char, rest) do
          {char_end, rest}  when char_beg < char_end ->
            char_class(rest, [{:range, char_beg, char_end} | class], state)
          {_, rest} ->
            parse_error({:char_class, string_between(str, rest)})
        end
      {char, rest} ->
        char_class(rest, [char | class], state)
    end
  end

  defp special_char?(c, _state), do: c in '^.[]$()|*+?{}'

  defp unescape_string(string) do
    Macro.unescape_string(string, &unescape_map/1)
  end

  defp unescape_map(?0), do: ?0
  defp unescape_map(?a), do: ?\a
  defp unescape_map(?b), do: ?\b
  defp unescape_map(?d), do: ?\d
  defp unescape_map(?e), do: ?\e
  defp unescape_map(?f), do: ?\f
  defp unescape_map(?n), do: ?\n
  defp unescape_map(?r), do: ?\r
  defp unescape_map(?s), do: ?\s
  defp unescape_map(?t), do: ?\t
  defp unescape_map(?v), do: ?\v
  defp unescape_map(?x), do: true
  defp unescape_map(?u), do: true
  defp unescape_map(_),  do: false

  defp unroll_interval(single, min, :none) do
    {:seq, List.duplicate(single, min)}
  end
  defp unroll_interval(single, min, :any) do
    {:seq, List.duplicate(single, min - 1) ++ [{:pclosure, single}]}
  end
  defp unroll_interval(single, min, max) do
    required = List.duplicate(single, min)
    optional = List.duplicate({:optional, single}, max - min)
    {:seq, required ++ optional}
  end

  defp interval_range(str) do
    case Integer.parse(str) do
      :error ->
        {:none, :none, str}
      {n, "," <> rest} ->
        case Integer.parse(rest) do
          :error    -> {n, :any, rest}
          {m, rest} -> {n, m,    rest}
        end
      {n, rest} ->
        {n, :none, rest}
    end
  end

  defp string_between(left, right) do
    binary_part(left, 0, byte_size(left) - byte_size(right))
  end
end
