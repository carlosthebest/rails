require 'erb'
require 'active_support/core_ext/kernel/singleton_class'

class ERB
  module Util
    HTML_ESCAPE = { '&' => '&amp;',  '>' => '&gt;',   '<' => '&lt;', '"' => '&quot;' }
    JSON_ESCAPE = { '&' => '\u0026', '>' => '\u003E', '<' => '\u003C' }
    HTML_ESCAPE_ONCE_REGEXP = /[\"><]|&(?!([a-zA-Z]+|(#\d+));)/
    JSON_ESCAPE_REGEXP = /[&"><]/

    # A utility method for escaping HTML tag characters.
    # This method is also aliased as <tt>h</tt>.
    #
    # In your ERB templates, use this method to escape any unsafe content. For example:
    #   <%=h @person.name %>
    #
    # ==== Example:
    #   puts html_escape("is a > 0 & a < 10?")
    #   # => is a &gt; 0 &amp; a &lt; 10?
    def html_escape(s)
      s = s.to_s
      if s.html_safe?
        s
      else
        s.encode(s.encoding, :xml => :attr)[1...-1].html_safe
      end
    end

    # Aliasing twice issues a warning "discarding old...". Remove first to avoid it.
    remove_method(:h)
    alias h html_escape

    module_function :h

    singleton_class.send(:remove_method, :html_escape)
    module_function :html_escape

    # A utility method for escaping HTML without affecting existing escaped entities.
    #
    # ==== Examples
    #   html_escape_once("1 < 2 &amp; 3")
    #   # => "1 &lt; 2 &amp; 3"
    #
    #   html_escape_once("&lt;&lt; Accept & Checkout")
    #   # => "&lt;&lt; Accept &amp; Checkout"
    def html_escape_once(s)
      result = s.to_s.gsub(HTML_ESCAPE_ONCE_REGEXP) { |special| HTML_ESCAPE[special] }
      s.html_safe? ? result.html_safe : result
    end

    module_function :html_escape_once

    # A utility method for escaping HTML entities in JSON strings
    # using \uXXXX JavaScript escape sequences for string literals:
    #
    #   json_escape("is a > 0 & a < 10?")
    #   # => is a \u003E 0 \u0026 a \u003C 10?
    #
    # Note that after this operation is performed the output is not
    # valid JSON. In particular double quotes are removed:
    #
    #   json_escape('{"name":"john","created_at":"2010-04-28T01:39:31Z","id":1}')
    #   # => {name:john,created_at:2010-04-28T01:39:31Z,id:1}
    #
    # This method is also aliased as +j+, and available as a helper
    # in Rails templates:
    #
    #   <%=j @person.to_json %>
    #
    def json_escape(s)
      result = s.to_s.gsub(JSON_ESCAPE_REGEXP) { |special| JSON_ESCAPE[special] }
      s.html_safe? ? result.html_safe : result
    end

    alias j json_escape
    module_function :j
    module_function :json_escape
  end
end

class Object
  def html_safe?
    false
  end
end

class Numeric
  def html_safe?
    true
  end
end

module ActiveSupport #:nodoc:
  class SafeBuffer < String
    UNSAFE_STRING_METHODS = ["capitalize", "chomp", "chop", "delete", "downcase", "gsub", "lstrip", "next", "reverse", "rstrip", "slice", "squeeze", "strip", "sub", "succ", "swapcase", "tr", "tr_s", "upcase", "prepend"].freeze

    alias_method :original_concat, :concat
    private :original_concat

    class SafeConcatError < StandardError
      def initialize
        super "Could not concatenate to the buffer because it is not html safe."
      end
    end

    def[](*args)
      new_safe_buffer = super
      new_safe_buffer.instance_eval { @dirty = false }
      new_safe_buffer
    end

    def safe_concat(value)
      raise SafeConcatError if dirty?
      original_concat(value)
    end

    def initialize(*)
      @dirty = false
      super
    end

    def initialize_copy(other)
      super
      @dirty = other.dirty?
    end

    def concat(value)
      if dirty? || value.html_safe?
        super(value)
      else
        super(ERB::Util.h(value))
      end
    end
    alias << concat

    def +(other)
      dup.concat(other)
    end

    def html_safe?
      !dirty?
    end

    def to_s
      self
    end

    def to_param
      to_str
    end

    def encode_with(coder)
      coder.represent_scalar nil, to_str
    end

    UNSAFE_STRING_METHODS.each do |unsafe_method|
      if 'String'.respond_to?(unsafe_method)
        class_eval <<-EOT, __FILE__, __LINE__ + 1
          def #{unsafe_method}(*args, &block)       # def capitalize(*args, &block)
            to_str.#{unsafe_method}(*args, &block)  #   to_str.capitalize(*args, &block)
          end                                       # end

          def #{unsafe_method}!(*args)              # def capitalize!(*args)
            @dirty = true                           #   @dirty = true
            super                                   #   super
          end                                       # end
        EOT
      end
    end

    protected

    def dirty?
      @dirty
    end
  end
end

class String
  def html_safe
    ActiveSupport::SafeBuffer.new(self)
  end
end
