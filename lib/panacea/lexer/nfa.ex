defmodule Panacea.Lexer.Nfa do
  defstruct id: nil, accept: nil, edges: []

  def from_regex(reas) do
    {nfa, firsts, free} = build_list(reas, [], [], 0)
    root = %__MODULE__{id: free, edges: Enum.map(firsts, &{:epsilon, &1})}
    nfa = Enum.sort_by([root | nfa], &(&1.id))
    {List.to_tuple(nfa), free}
  end

  defp build_list([{reg, action} | reas], nfa, firsts, free) do
    {new_nfa, free, first} = build(reg, free, action)
    build_list(reas, new_nfa ++ nfa, [first | firsts], free)
  end
  defp build_list([], nfa, firsts, free) do
    {nfa, Enum.reverse(firsts), free}
  end

  defp build(reg, next, action) do
    {nfa, new_next, final} = build(reg, next + 1, next, [])
    {[%__MODULE__{id: final, accept: {:accept, action}} | nfa], new_next, next}
  end

  defp build({:alt, regs}, next, first, nfa),
    do: build_alt(regs, next, first, nfa)
  defp build({:seq, regs}, next, first, nfa),
    do: build_seq(regs, next, first, nfa)
  defp build({:kclosure, reg}, next, first, nfa),
    do: build_kclosure(reg, next, first, nfa)
  defp build({:pclosure, reg}, next, first, nfa),
    do: build_pclosure(reg, next, first, nfa)
  defp build({:optional, reg}, next, first, nfa),
    do: build_optional(reg, next, first, nfa)
  defp build({:char_class, class}, next, first, nfa),
    do: build_char_class(class, next, first, nfa)
  defp build({:comp_class, class}, next, first, nfa),
    do: build_comp_class(class, next, first, nfa)
  defp build({:lit, lit}, next, first, nfa),
    do: build_lit(lit, next, first, nfa)
  defp build(:epsilon, next, first, nfa),
    do: build_epsilon(next, first, nfa)

  defp build_epsilon(next, first, nfa),
    do: {%__MODULE__{id: first, edges: [{:epsilon, next} | nfa]}, next + 1, next}

  defp build_lit(chars, next, first, nfa) do
    Enum.reduce(chars, {nfa, next, first}, fn char, {nfa, next, first} ->
      {[%__MODULE__{id: first, edges: [{[{char, char}], next}]} | nfa], next + 1, next}
    end)
  end

  defp build_kclosure(reg, next, first, nfa) do
    {nfa, new_next, final} = build(reg, next + 1, next, nfa)
    {[%__MODULE__{id: first, edges: [{:epsilon, next}, {:epsilon, new_next}]},
      %__MODULE__{id: final, edges: [{:epsilon, next}, {:epsilon, new_next}]} | nfa],
     new_next + 1, new_next}
  end

  defp build_pclosure(reg, next, first, nfa) do
    {nfa, new_next, final} = build(reg, next + 1, next, nfa)
    {[%__MODULE__{id: first, edges: [{:epsilon, next}]},
      %__MODULE__{id: final, edges: [{:epsilon, next}, {:epsilon, new_next}]} | nfa],
    new_next + 1, new_next}
  end

  defp build_optional(reg, next, first, nfa) do
    {nfa, new_next, final} = build(reg, next + 1, next, nfa)
    {[%__MODULE__{id: first, edges: [{:epsilon, next}, {:epsilon, new_next}]},
      %__MODULE__{id: final, edges: [{:epsilon, new_next}]} | nfa],
     new_next + 1, new_next}
  end

  defp build_char_class(class, next, first, nfa) do
    {[%__MODULE__{id: first, edges: [{pack_char_class(class), next}]} | nfa],
     next + 1, next}
  end

  defp build_comp_class(class, next, first, nfa) do
    {[%__MODULE__{id: first, edges: [{pack_comp_class(class), next}]} | nfa],
     next + 1, next}
  end

  defp build_seq(regs, next, first, nfa) do
    Enum.reduce(regs, {nfa, next, first}, fn reg, {nfa, next, first} ->
      build(reg, next, first, nfa)
    end)
  end

  defp build_alt([reg], next, first, nfa) do
    build(reg, next, first, nfa)
  end
  defp build_alt([reg | regs], next, first, nfa) do
    {nfa, new_next, intermediate} = build(reg, next + 1, next, nfa)
    {nfa, newer_next, final} = build_alt(regs, new_next + 1, new_next, nfa)
    {[%__MODULE__{id: first, edges: [{:epsilon, next}, {:epsilon, new_next}]},
      %__MODULE__{id: intermediate, edges: [{:epsilon, newer_next}]},
      %__MODULE__{id: final, edges: [{:epsilon, newer_next}]} | nfa],
     newer_next + 1, newer_next}
  end

  defp pack_char_class(class) do
    class
    |> Enum.map(&char_class_to_char_range/1)
    |> Enum.sort
    |> Enum.dedup
    |> pack_char_ranges
  end

  defp char_class_to_char_range({:range, x, y}), do: {x, y}
  defp char_class_to_char_range(c),              do: {c, c}

  defp pack_char_ranges([{c1, c2} = range, {c3, c4} | rest]) when c1 <= c3 and c2 >= c4,
    do: pack_char_ranges([range | rest])
  defp pack_char_ranges([{c1, c2}, {c3, c4} | rest]) when c1 <= c3 and c2 >= c4,
    do: pack_char_ranges([{c1, c4} | rest])
  defp pack_char_ranges([{c1, c2}, {c3, c4} | rest]) when c2 + 1 == c3,
    do: pack_char_ranges([{c1, c4} | rest])
  defp pack_char_ranges([range | rest]),
    do: [range | pack_char_ranges(rest)]
  defp pack_char_ranges([]),
    do: []

  defp pack_comp_class(class) do
    class
    |> pack_char_class
    |> complement_ranges(0)
  end

  defp complement_ranges([{0, c2} | rest], 0),
    do: complement_ranges(rest, c2)
  defp complement_ranges([{c1, c2} | rest], last),
    do: [{last, c1 - 1} | complement_ranges(rest, c2 + 1)]
  defp complement_ranges([], last),
    do: [{last, :maxchar}]
end
