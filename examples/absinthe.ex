defmodule Absinthe.Lexer do
  import Panacea.Lexer, only: [deflexer: 2]

  @compile :native

  # Ignored tokens
  whitespace = "[\u{0009}\u{000B}\u{000C}\u{0020}\u{00A0}]"
  line_terminator_ = "\u{000A}\u{000D}\u{2028}\u{2029}"
  line_terminator = "[#{line_terminator_}]"
  comment = "#[^#{line_terminator_}]*"
  comma = ","
  ignored = "#{whitespace}|#{line_terminator}|#{comment}|#{comma}"

  # Lexical tokens
  punctuator = "[!$():=@\\[\\]{|}]|\\.{3}"
  name = "[_A-Za-z][_0-9A-Za-z]*"

  # Int value
  digit = "[0-9]"
  non_zero_digit = "[1-9]"
  negative_sign = "-"
  integer_part = "#{negative_sign}?(0|#{non_zero_digit}#{digit}*)"
  int_value = "#{integer_part}"

  # Float value
  fractional_part = "\\.#{digit}+"
  sign = "+|-"
  exponent_indicator = "e|E"
  exponent_part = "#{exponent_indicator}#{sign}?#{digit}+"
  float_value = "#{integer_part}#{fractional_part}|#{integer_part}#{exponent_part}|#{integer_part}#{fractional_part}#{exponent_part}"

  # % String Value
  hex_digit = "[0-9A-Fa-f]"
  escaped_unicode = "u#{hex_digit}{4}"
  escaped_character = "[\"\/bfnrt]"
  string_character = "[^\"#{line_terminator_}]|\\\\#{escaped_unicode}|\\\\#{escaped_character}"
  string_value = ~s|"(#{string_character})*"|

  # % Boolean Value
  boolean_value = "true|false"

  # Reserved words
  reserved_word = "query|mutation|subscription|fragment|on|implements|interface|union|scalar|enum|input|extend|type|directive|ON|null|schema"

  deflexer :lexer do
    defrule ignored,
      do: :skip
    defrule punctuator, meta(token: token, line: line),
      do: {:token, {String.to_atom(token), line}}
    defrule reserved_word, meta(token: token, line: line),
      do: {:token, {String.to_atom(token), line}}
    defrule int_value, meta(token: token, line: line),
      do: {:token, {:int_value, line, token}}
    defrule float_value, meta(token: token, line: line),
      do: {:token, {:float_value, line, token}}
    defrule string_value, meta(token: token, line: line),
      do: {:token, {:string_value, line, token}}
    defrule boolean_value, meta(token: token, line: line),
      do: {:token, {:boolean_value, line, token}}
    defrule name, meta(token: token, line: line),
      do: {:token, {:name, line, token}}
  end
end
