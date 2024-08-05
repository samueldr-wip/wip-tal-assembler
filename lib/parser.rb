require_relative "lexer"
require_relative "error"

OPCODES_BY_BYTE = {
  0x00 => "BRK",
  0x01 => "INC",
  0x02 => "POP",
  0x03 => "NIP",
  0x04 => "SWP",
  0x05 => "ROT",
  0x06 => "DUP",
  0x07 => "OVR",
  0x08 => "EQU",
  0x09 => "NEQ",
  0x0a => "GTH",
  0x0b => "LTH",
  0x0c => "JMP",
  0x0d => "JCN",
  0x0e => "JSR",
  0x0f => "STH",

  0x10 => "LDZ",
  0x11 => "STZ",
  0x12 => "LDR",
  0x13 => "STR",
  0x14 => "LDA",
  0x15 => "STA",
  0x16 => "DEI",
  0x17 => "DEO",
  0x18 => "ADD",
  0x19 => "SUB",
  0x1a => "MUL",
  0x1b => "DIV",
  0x1c => "AND",
  0x1d => "ORA",
  0x1e => "EOR",
  0x1f => "SFT",

  0x20 => "JCI",
  0x40 => "JMI",
  0x60 => "JSI",

  0x80 => "LIT",
  0xa0 => "LIT2",
  0xc0 => "LITr",
  0xe0 => "LIT2r",
}

(0x01..0x1f).each do |num|
  OPCODES_BY_BYTE[ num | 0x20 ] = OPCODES_BY_BYTE[num] + "2"
  OPCODES_BY_BYTE[ num | 0x40 ] = OPCODES_BY_BYTE[num] + "r"
  OPCODES_BY_BYTE[ num | 0x60 ] = OPCODES_BY_BYTE[num] + "2r"
  OPCODES_BY_BYTE[ num | 0x80 ] = OPCODES_BY_BYTE[num] + "k"
  OPCODES_BY_BYTE[ num | 0xa0 ] = OPCODES_BY_BYTE[num] + "2k"
  OPCODES_BY_BYTE[ num | 0xc0 ] = OPCODES_BY_BYTE[num] + "kr"
  OPCODES_BY_BYTE[ num | 0xe0 ] = OPCODES_BY_BYTE[num] + "2kr"
end

OPCODES_BY_MNEMONIC = OPCODES_BY_BYTE.map do |k, v|
  [v, k]
end.sort.to_h

[2, 3].each do |i|
  ["2", "k", "r"].permutation(i) do |list|
    suffix = list.join("")
    OPCODES_BY_BYTE.each do |value, mnemonic|
      OPCODES_BY_MNEMONIC[mnemonic + suffix] = [
        value,
        if list.include?("2") then 0x20 else 0 end,
        if list.include?("r") then 0x40 else 0 end,
        if list.include?("k") then 0x80 else 0 end,
      ].reduce(&:+)
    end
  end
end

class Parser
  attr_reader :tokens
  attr_reader :output
  attr_reader :labels

  def initialize(tokens)
    @tokens = tokens.select { |token| !token.transparent? }
    @output = []
    @position = 0x0100
    @labels = {}
  end

  def parse!()
    # First coalesce the tokens into their final shape... with palceholders...
    tokens.each do |token|
      case token
      when Lexer::PaddingRelative
        @position += token.value
      when Lexer::PaddingAbsolute
        @position = token.value
      when Lexer::Label
        # The labels were checked for uniqueness when lexing...
        labels[token.label] = @position
      when Lexer::Literal
        if token.value[:length] == 1
          add_op("LIT")
        else
          add_op("LIT2")
        end
        add_output(Output.new(token.value[:value], length: token.value[:length], position: @position, token: token))
      when Lexer::ByteOrShort
        add_output(Output.new(token.value[:value], length: token.value[:length], position: @position, token: token))
      when Lexer::RawAscii
        add_output(Output.new(token.value, length: token.value.length, position: @position, token: token))
      when Lexer::Opcode
        add_op(token.str)
      when Lexer::LabelRef
        if token.instruction
          add_op(token.instruction)
        end
        add_output(Placeholder.new(token.label, token.ref_type, position: @position, token: token))
      when Lexer::Macro
        # no-op
      else
        raise "Unexpected token #{token.class.name.inspect}"
      end
    end

    # Then pry out the placeholder for actual values
    output.each do |value|
      next unless value.is_a?(Placeholder)
      value.set_ref(@labels[value.label])
    end

    output
  end

  def add_op(name)
    add_output(Output.new(OPCODES_BY_MNEMONIC[name], position: @position, token: {opcode: name}))
  end

  def add_output(value)
    output << value
    @position += value.length
  end

  def emit!(io)
    output.each do |value|
      if value.length > 0
        newpos = value.position - 0x100
        if newpos < io.tell
          raise AssemblerException.new("Unexpected rewind for writing from #{io.tell} to #{newpos}")
        end
        io.seek(newpos)
        io.write(value.emit)
      end
    end
  end

  class Output
    # Value as either a number (8 or 16 bit) or a string of bytes.
    attr_reader :value
    # Length in bytes of the value
    attr_reader :length
    # Position (in RAM)
    attr_reader :position
    # Token causing this output
    attr_reader :token

    def initialize(value, length: 1, position:, token:)
      @value = value
      @length = length
      @position = position
      @token = token
    end

    def emit()
      if value.nil?
        raise "Value unexpectedly nil for #{token.inspect}..."
      elsif value.is_a? String
        value
      else
        pattern = 
          case length
          when 1
            "C"
          when 2
            "S>"
          else
            raise "Unexpected length #{length} for value #{value.inspect}"
          end
        [value].pack(pattern)
      end
    end
  end

  class Placeholder < Output
    attr_reader :label
    attr_reader :type

    def initialize(label, type, position:, token:)
      @length =
        if [:relative_8, :zeropage].include?(type)
          1
        else
          2
        end
      super(nil, length: @length, position: position, token:)
      @label = label
      @type = type
    end

    def set_ref(address)
      if address.nil?
        raise AssemblerException.new("Reference not found for label #{self.token.label.inspect}")
      end
      @value =
        if [:relative_8, :relative_16].include?(type)
          address - position - 2
        else
          address
        end
      if type == :relative_8 && value > 0xff
        token.error "Relative reference too far: #{label.inspect}"
      end
    end
  end
end
