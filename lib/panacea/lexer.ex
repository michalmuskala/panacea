defmodule Panacea.Lexer do
  defmacro __using__(_) do
    quote do
      import Panacea.Lexer, only: [deflexer: 2]
    end
  end

  defmacro deflexer(name, [do: block]) do
    quote do
      Module.register_attribute(__MODULE__, :panacea_lexer_rules, accumulate: true)

      try do
        import Panacea.Lexer
        unquote(block)
      after
        :ok
      end

      reas = Module.get_attribute(__MODULE__, :panacea_lexer_rules)
      Module.delete_attribute(__MODULE__, :panacea_lexer_rules)
      Panacea.Lexer.Codegen.compile(unquote(name), reas)
    end
  end

  defmacro defrule(regex, meta \\ quote(do: _), [do: block]) do
    id = System.unique_integer([:positive])

    quote do
      rule = {Panacea.Lexer.Regex.parse!(unquote(regex)), unquote(id)}
      Module.put_attribute(__MODULE__, :panacea_lexer_rules, rule)
      unquote(action(id, meta, block))
    end
  end

  defp action(id, meta, block) do
    name = :"panacea_action_#{id}"
    quote do
      @compile {:inlne, {unquote(name), 1}}
      @doc false
      def unquote(name)(unquote(meta)), do: unquote(block)
    end
  end
end
