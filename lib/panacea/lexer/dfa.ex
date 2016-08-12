defmodule Panacea.Lexer.Dfa do
  defstruct id: nil, nfa: [], trans: [], accept: nil

  def build(nfa, nfa_first) do
    {dfa, dfa_first} = do_build(nfa, nfa_first)
    {dfa, dfa_first} = minimise(dfa, dfa_first)
    dfa = Enum.map(dfa, &pack_transitions/1)
    {dfa, dfa_first}
  end

  defp do_build(nfa, nfa_first) do
    dfa = %__MODULE__{id: 0, nfa: eclosure([nfa_first], nfa)}
    {build([dfa], 1, [], nfa), 0}
  end

  defp build([unmarked | rest], next, marked_set, nfa) do
    {trans, new_unmarked, next} =
      build(unmarked.nfa, rest, next, [], [unmarked | marked_set], nfa)
    marked = %{unmarked | trans: trans, accept: accept(unmarked.nfa, nfa)}
    build(new_unmarked, next, [marked | marked_set], nfa)
  end
  defp build([], _, marked_set, _), do: marked_set

  defp build(set, unmarked, next, transitions, marked, nfa) do
    ranges = transition_ranges(set, nfa)
    build(ranges, set, unmarked, next, transitions, marked, nfa)
  end

  defp transition_ranges(set, nfa) do
    ranges =
      for id <- set,
        {ranges, _} <- elem(nfa, id).edges,
        ranges != :epsilon,
        range <- ranges,
      do: range

    ranges
    |> :ordsets.from_list
    |> disjoint_ranges
  end

  import :ordsets, only: [add_element: 2, union: 2, is_element: 2]
  import :orddict, only: [store: 3]

  defp disjoint_ranges([{_, c2} = r1, {c3, _} = r2 | rest]) when c2 < c3,
    do: [r1 | disjoint_ranges([r2 | rest])]
  defp disjoint_ranges([{c1, c2}, {c3, c4} | rest]) when c1 == c3,
    do: [{c1, c2} | disjoint_ranges(add_element({c2 + 1, c4}, rest))]
  defp disjoint_ranges([{c1, c2}, {c3, c4} | rest])
      when c1 < c3 and c2 >= c3 and c2 < c4,
    do: [{c1, c3 - 1} | disjoint_ranges(union([{c3, c2}, {c2 + 1, c4}], rest))]
  defp disjoint_ranges([{c1, c2}, {c3, c4} | rest]) when c1 < c3 and c2 == c4,
    do: [{c1, c3 - 1} | disjoint_ranges(add_element({c3, c4}, rest))]
  defp disjoint_ranges([{c1, c2}, {c3, c4} | rest]) when c1 < c3 and c2 > c4,
    do: [{c1, c3 - 1} | disjoint_ranges(union([{c3, c4}, {c4 + 1, c2}], rest))]
  defp disjoint_ranges([range | rest]),
    do: [range | disjoint_ranges(rest)]
  defp disjoint_ranges([]),
    do: []

  defp build([range | rest], set, unmarked, next, transitions, marked, nfa) do
    case set |> move(range, nfa) |> eclosure(nfa) do
      [] ->
        build(rest, set, unmarked, next, transitions, marked, nfa)
      state ->
        case fetch_state(unmarked, marked, state) do
          {:ok, transition} ->
            transitions = store(range, transition, transitions)
            build(rest, set, unmarked, next, transitions, marked, nfa)
          :error ->
            dfa         = %__MODULE__{id: next, nfa: state}
            transitions = store(range, next, transitions)
            unmarked    = [dfa | unmarked]
            next        = next + 1
            build(rest, set, unmarked, next, transitions, marked, nfa)
        end
    end
  end
  defp build([], _, unmarked, next, transitions, _, _) do
    {transitions, unmarked, next}
  end

  defp fetch_state(unmarked, marked, state) do
    finder = &(&1.nfa == state)
    case Enum.find(unmarked, finder) || Enum.find(marked, finder) do
      nil   -> :error
      value -> {:ok, value.id}
    end
  end

  defp eclosure(states, nfa, acc \\ :ordsets.new)
  defp eclosure([state | rest], nfa, acc) do
    edges      = elem(nfa, state).edges
    new_states = for {:epsilon, n} <- edges, not is_element(n, acc), do: n
    eclosure(new_states ++ rest, nfa, add_element(state, acc))
  end
  defp eclosure([], _, acc), do: acc

  defp move(states, range, nfa) do
    for n <- states,
      {ranges, state} <- elem(nfa, n).edges,
      ranges != :epsilon,
      contained?(range, ranges),
      do: state
  end

  defp contained?({c1, c2} = range, ranges) do
    Enum.any?(ranges, fn
      ^range   -> true
      {c3, c4} -> c1 >= c3 and c2 <= c4
    end)
  end

  import :ordsets, only: []
  import :orddict, only: []

  defp accept(states, nfa) do
    Enum.find_value(states, &(elem(nfa, &1).accept))
  end

  defp minimise(dfa, first) do
    case minimise(dfa, [], []) do
      {dfa, []} ->
        {dfa, reds} = pack(dfa)
        {min_update(dfa, reds), min_use(first, reds)}
      {dfa, reds} ->
        minimise(min_update(dfa, reds), min_use(first, reds))
    end
  end

  defp minimise([dfa | rest], reds, minimized) do
    {rest, nfa, reducible} = min_delete(rest, dfa.trans, dfa.accept, dfa.id)
    dfa = Map.update!(dfa, :nfa, &:ordsets.union(&1, nfa))
    minimise(rest, reducible ++ reds, [dfa | minimized])
  end
  defp minimise([], reds, minimized), do: {minimized, reds}

  defp min_delete(dfa, trans, accept, new_id) do
    {rejected, minimized} =
      Enum.partition(dfa, &match?(%{trans: ^trans, accept: ^accept}, &1))
    reds = Enum.map(rejected, &{&1.id, new_id})
    nfa  = Enum.reduce(rejected, :ordsets.new, &:ordsets.union(&1.nfa, &2))
    {minimized, nfa, reds}
  end

  defp min_update(dfa, reds) do
    Enum.map(dfa, fn dfa -> Map.update!(dfa, :trans, &min_update_trans(&1, reds)) end)
  end

  defp min_update_trans(trans, reds) do
    Enum.map(trans, fn {range, state} -> {range, min_use(state, reds)} end)
  end

  defp min_use(old, reds) do
    Enum.find_value(reds, old, fn
      {^old, new} -> new
      _           -> nil
    end)
  end

  defp pack(dfa) do
    dfa
    |> Enum.with_index
    |> Enum.map(fn {dfa, id} -> {%{dfa | id: id}, {dfa.id, id}} end)
    |> Enum.unzip
  end

  defp pack_transitions(dfa) do
    %{dfa | trans: pack_transitions(dfa.trans, [], [])}
  end

  defp pack_transitions([{{c, c}, s} | rest], acch, acct),
    do: pack_transitions(rest, [{c, s} | acch], acct)
  defp pack_transitions([{{c, ?\n}, s} | rest], acch, acct),
    do: pack_transitions([{{c, ?\n - 1}, s} | rest], [{?\n, s} | acch], acct)
  defp pack_transitions([{{?\n, c}, s} | rest], acch, acct),
    do: pack_transitions([{{?\n + 1, c}, s} | rest], [{?\n, s} | acch], acct)
  defp pack_transitions([{{c1, c2}, s} | rest], acch, acct) when c1 < ?\n and c2 > ?\n,
    do: pack_transitions([{{c1, ?\n - 1}, s}, {{?\n + 1, c2}, s} | rest], [{?\n, s} | acch], acct)
  defp pack_transitions([{{c1, c2}, s} | rest], acch, acct) when c1 - c2 == 1,
    do: pack_transitions(rest, [{c1, s}, {c2, s} | acch], acct)
  defp pack_transitions([trans | rest], acch, acct),
    do: pack_transitions(rest, acch, [trans | acct])
  defp pack_transitions([], acch, acct),
    do: acch ++ Enum.reverse(acct)
end
