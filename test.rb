#!/usr/bin/env ruby

require_relative "lib/lexer"

lexer = Lexer.from_file(ARGV.first)
lexer.parse!
lexer.preprocess!

pp (lexer.tokens.select { |token| !token.transparent?})
