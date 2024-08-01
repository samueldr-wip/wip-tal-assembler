class AssemblerException < StandardError
  def initialize(msg)
    @msg = msg
  end

  def message()
    @msg
  end
end
