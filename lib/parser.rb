require_relative "opcodes"
require_relative "lexer"
require_relative "error"

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
        raise AssemblerException.new("Reference not found for label reference #{self.token.label.inspect} @ #{self.token.position}")
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
