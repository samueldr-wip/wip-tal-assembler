#!/usr/bin/env ruby

require_relative "lib/lexer"

lexer = Lexer.from_file(ARGV.first)
lexer.parse!
pp lexer.tokens
