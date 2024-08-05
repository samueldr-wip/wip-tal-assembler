#!/usr/bin/env ruby

require_relative "lib/lexer"
require_relative "lib/parser"

def just_build(input)
  lexer = Lexer.from_source(input)
  lexer.parse!
  lexer.preprocess!
  parser = Parser.new(lexer.tokens)
  parser.parse!
  io = StringIO.new()
  parser.emit!(io)
  io.string()
end

OPCODE_TEST_CASES = OPCODES_BY_BYTE.map do |byte, opcode|
  {
    name: "Testing emission for opcode #{opcode.inspect}.",
    source: "#{opcode}",
    expected: [byte].pack("C"),
  }
end

SIMPLE_OUTPUT_TEST_CASES = [
  {
    name: "Emission of a single byte.",
    source: "99",
    expected: [0x99].pack("C")
  },
  {
    name: "Emission of a pair of bytes.",
    source: "12 34",
    expected: [0x12, 0x34].pack("CC")
  },
  {
    name: "Emission of a short.",
    source: "1234",
    expected: [0x1234].pack("S>")
  },
  {
    name: "Emission of a pair of shorts.",
    source: "1234 face",
    expected: [0x1234, 0xface].pack("S>S>")
  },
  {
    name: "Comment only",
    source: "( This is a comment )",
    expected: [].pack("")
  },
  {
    name: "More than a comment",
    source: "BRK ( This is a comment ) 1234",
    expected: [0, 0x1234].pack("CS>")
  },
  {
    name: "Implicit jump to label",
    source: "|0100 some-fn |0106 @some-fn JMP2r",
    #                                      rel +3
    expected: [OPCODES_BY_MNEMONIC["JSI"], 0x0003, 0x00, 0x00, 0x00, OPCODES_BY_MNEMONIC["JMP2r"]].pack("CS>C*")
  },
  {
    name: "Implicit jump to label (bis)",
    source: "|0100 some-fn @some-fn JMP2r",
    expected: [OPCODES_BY_MNEMONIC["JSI"], 0x0000, OPCODES_BY_MNEMONIC["JMP2r"]].pack("CS>C")
  },
]

RUNES_TEST_CASES = [
  # LIT
  {
    name: "Literal (byte)",
    source: "#45",
    expected: [OPCODES_BY_MNEMONIC["LIT"], 0x45].pack("CC"),
  },
  {
    name: "Literal (short)",
    source: "#b055",
    expected: [OPCODES_BY_MNEMONIC["LIT2"], 0xb055].pack("CS>"),
  },
  # ASCII
  {
    name: "Ascii runes (single char)",
    source: '"a',
    expected: "a",
  },
  {
    name: "Ascii runes (string)",
    source: '"Testing',
    expected: "Testing",
  },
  {
    name: "Ascii runes with bytes for spaces",
    source: '"Testing 20 "this',
    expected: "Testing this",
  },
  # PADDING
  {
    name: "Padding rune (absolute).",
    source: "|0104 abcd",
    expected: [0, 0, 0, 0, 0xabcd].pack("CCCCS>")
  },
  {
    name: "Padding rune (relative).",
    source: "|0100 $4 abcd",
    expected: [0, 0, 0, 0, 0xabcd].pack("CCCCS>")
  },
  # Label runes
  {
    name: "Label rune (parent).",
    source: "@parent",
    expected: [].pack("")
  },
  {
    name: "Label rune (child).",
    source: "@parent $child",
    expected: [].pack("")
  },
  # Immediate runes
  {
    name: "JMI",
    source: "|2106 @parent |100 !parent",
    expected: [OPCODES_BY_MNEMONIC["JMI"], 0x2003].pack("CS>")
  },
  {
    name: "JCI",
    source: "|2106 @parent |100 ?parent",
    expected: [OPCODES_BY_MNEMONIC["JCI"], 0x2003].pack("CS>")
  },
  # Addressing runes
  {
    name: "Literal relative rune.",
    source: "|100 ,parent |110 @parent",
    expected: [OPCODES_BY_MNEMONIC["LIT"], 0x0d].pack("CC")
  },
  {
    name: "Raw relative rune.",
    source: "|100 _parent |110 @parent",
    expected: [0x0e].pack("C")
  },
  {
    name: "Literal zero-page rune.",
    source: " |04 @parent |100 .parent",
    expected: [OPCODES_BY_MNEMONIC["LIT"], 0x04].pack("CC")
  },
  {
    name: "Raw zero-page rune.",
    source: " |04 @parent |100 -parent",
    expected: [0x04].pack("C")
  },
  {
    name: "Literal absolute rune.",
    source: " |1234 @parent |100 ;parent",
    expected: [OPCODES_BY_MNEMONIC["LIT2"], 0x1234].pack("CS>")
  },
  {
    name: "Raw absolute rune.",
    source: " |1234 @parent |100 =parent",
    expected: [0x1234].pack("S>")
  },
  # NOTE: pre-processor runes are tested in pre-processor tests
]

BRACKETS_TEST_CASES = [
  {
    name: "Square brackets.",
    source: "POP2 [ POP2 POP2 ] POP2",
    expected: [
      OPCODES_BY_MNEMONIC["POP2"],
      OPCODES_BY_MNEMONIC["POP2"],
      OPCODES_BY_MNEMONIC["POP2"],
      OPCODES_BY_MNEMONIC["POP2"],
    ].pack("C*")
  },
  {
    name: "Unadorned curly (JSI).",
    source: "POP2 { POP2 POP2 } POP2",
    expected: [
      OPCODES_BY_MNEMONIC["POP2"],
      OPCODES_BY_MNEMONIC["JSI"],
      0x0002,
      OPCODES_BY_MNEMONIC["POP2"],
      OPCODES_BY_MNEMONIC["POP2"],
      OPCODES_BY_MNEMONIC["POP2"],
    ].pack("CCS>C*")
  },
  {
    name: "Curly with `!`.",
    source: "POP2 !{ POP2 POP2 } POP2",
    expected: [
      OPCODES_BY_MNEMONIC["POP2"],
      OPCODES_BY_MNEMONIC["JMI"],
      0x0002,
      OPCODES_BY_MNEMONIC["POP2"],
      OPCODES_BY_MNEMONIC["POP2"],
      OPCODES_BY_MNEMONIC["POP2"],
    ].pack("CCS>C*")
  },
  {
    name: "Curly with `?`.",
    source: "POP2 ?{ POP2 POP2 } POP2",
    expected: [
      OPCODES_BY_MNEMONIC["POP2"],
      OPCODES_BY_MNEMONIC["JCI"],
      0x0002,
      OPCODES_BY_MNEMONIC["POP2"],
      OPCODES_BY_MNEMONIC["POP2"],
      OPCODES_BY_MNEMONIC["POP2"],
    ].pack("CCS>C*")
  },
  {
    name: "Curly with `;`.",
    source: "POP2 ;{ POP2 POP2 } POP2",
    expected: [
      OPCODES_BY_MNEMONIC["POP2"],  # |0100
      OPCODES_BY_MNEMONIC["LIT2"],  # |0101
      0x0106,                       # |0102 absolute address...
      OPCODES_BY_MNEMONIC["POP2"],  # |0104
      OPCODES_BY_MNEMONIC["POP2"],  # |0105
      OPCODES_BY_MNEMONIC["POP2"],  # |0106 ...of this instruction
    ].pack("CCS>C*")
  },
]

MACRO_TEST_CASES = [
  {
    name: "Macro with curlies.",
    source: "%macro { POP2k } macro",
    expected: [
      OPCODES_BY_MNEMONIC["POP2k"],
    ].pack("C"),
  },
  {
    name: "Macro with curlies, with a lambda.",
    source: "%macro { { POP2k } } macro",
    expected: [
      OPCODES_BY_MNEMONIC["JSI"],
      0x0001,
      OPCODES_BY_MNEMONIC["POP2k"],
    ].pack("CS>C"),
  },
]

# TODO: test error cases too
# |100 ,testing |300 @testing #1234   →   `Relative reference too far`


def run_tests(suite, tests)
  puts ":: #{suite}"

  results = tests.map do |test|
    exception = nil
    result = false

    begin
      output = just_build(test[:source])
      result = test[:expected].bytes == output.bytes
    rescue Exception => e
      exception = e
    end

    unless result
      puts "FAILED: #{test[:name]}"
      puts "      |   Source: #{test[:source].inspect}"
      puts "      | Expected: #{test[:expected].bytes}"
      if exception.nil?
        puts "      |      Got: #{output.bytes}"
      else
        msg = [
          e.message(),
          e.backtrace().join("\n"),
        ].join("\n").split("\n").map{|l| "      |   #{l}" }.join("\n")
        puts "      |Exception: \n#{msg}"
      end
    end

    if test[:debug] && !exception
      lexer = Lexer.from_source(test[:source])
      lexer.parse!
      lexer.preprocess!
      pp lexer.tokens
      parser = Parser.new(lexer.tokens)
      parser.parse!
      pp parser.output
    end

    {
      result: result,
      test: test,
    }
  end

  grouped = results.group_by { |result| result[:result] }
  grouped[true] ||= []
  grouped[false] ||= []

  puts "   Success: #{grouped[true].length}/#{results.length}"
end

run_tests("opcodes", OPCODE_TEST_CASES)
run_tests("simple", SIMPLE_OUTPUT_TEST_CASES)
run_tests("runes", RUNES_TEST_CASES)
run_tests("brackets", BRACKETS_TEST_CASES)
run_tests("macros", MACRO_TEST_CASES)
