# frozen_string_literal: true

require "json"

module ACP
  module Schema
    class ValidationError < StandardError
      attr_reader :path

      def initialize(message, path = [])
        @path = path
        super(path.empty? ? message : "#{path.join('.')}: #{message}")
      end
    end

    def self.to_camel(snake)
      parts = snake.to_s.split("_")
      parts[0] + parts[1..].map(&:capitalize).join
    end

    def self.to_snake(camel)
      camel.to_s.gsub(/([A-Z])/) { "_#{::Regexp.last_match(1).downcase}" }.sub(/\A_/, "")
    end

    def self.serialize(value)
      case value
      when Base then value.to_h
      when Array then value.map { |v| serialize(v) }
      when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = serialize(v) }
      else value
      end
    end

    module Types
      def self.resolve(spec)
        case spec
        when Symbol then Scalar.for(spec)
        when String then Ref.new(spec)
        when Array then List.new(resolve(spec.first))
        else
          raise ArgumentError, "Unsupported type spec: #{spec.inspect}" unless spec.respond_to?(:coerce)

          spec
        end
      end

      class Scalar
        KINDS = %i[string integer number boolean object any].freeze

        def self.for(kind)
          @instances ||= KINDS.to_h { |k| [k, new(k)] }
          @instances.fetch(kind) { raise ArgumentError, "Unknown scalar type: #{kind.inspect}" }
        end

        attr_reader :kind

        def initialize(kind)
          @kind = kind
        end

        def coerce(value, path = [])
          case @kind
          when :any then value
          when :string
            return value if value.is_a?(String)

            fail!(value, path)
          when :integer
            return value if value.is_a?(Integer)
            return value.to_i if value.is_a?(Float) && value.finite? && value == value.floor

            fail!(value, path)
          when :number
            return value if value.is_a?(Numeric)

            fail!(value, path)
          when :boolean
            return value if [true, false].include?(value)

            fail!(value, path)
          when :object
            return value if value.is_a?(Hash)

            fail!(value, path)
          end
        end

        private

        def fail!(value, path)
          raise ValidationError.new("expected #{@kind}, got #{value.class}", path)
        end
      end

      STRING = Scalar.for(:string)
      INTEGER = Scalar.for(:integer)
      NUMBER = Scalar.for(:number)
      BOOLEAN = Scalar.for(:boolean)
      OBJECT = Scalar.for(:object)
      ANY = Scalar.for(:any)

      class ProtocolVersion
        def coerce(value, _path = [])
          return value if value.is_a?(Integer)

          Integer(value)
        rescue ArgumentError, TypeError
          1
        end
      end

      PROTOCOL_VERSION = ProtocolVersion.new

      class Ref
        attr_reader :name

        def initialize(name)
          @name = name
          @target = nil
        end

        def target
          @target ||= Schema.const_get(@name)
        end

        def coerce(value, path = [])
          target.coerce(value, path)
        end
      end

      class List
        attr_reader :item

        def initialize(item, skip_invalid: false)
          @item = Types.resolve(item)
          @skip_invalid = skip_invalid
        end

        def coerce(value, path = [])
          raise ValidationError.new("expected array, got #{value.class}", path) unless value.is_a?(Array)

          result = []
          value.each_with_index do |element, index|
            result << @item.coerce(element, path + [index])
          rescue ValidationError
            raise unless @skip_invalid
          end
          result
        end
      end

      class Map
        def initialize(value_type)
          @value_type = Types.resolve(value_type)
        end

        def coerce(value, path = [])
          raise ValidationError.new("expected object, got #{value.class}", path) unless value.is_a?(Hash)

          value.each_with_object({}) do |(key, element), result|
            result[key.to_s] = @value_type.coerce(element, path + [key.to_s])
          end
        end
      end

      class Enum
        attr_reader :values

        def initialize(values, open: false)
          @values = values.freeze
          @open = open
        end

        def coerce(value, path = [])
          raise ValidationError.new("expected string, got #{value.class}", path) unless value.is_a?(String)
          return value if @open || @values.include?(value)

          raise ValidationError.new("unexpected value #{value.inspect}, allowed: #{@values.join(', ')}", path)
        end
      end

      class Union
        attr_reader :tag, :tagged, :untagged

        def initialize(tag: nil, tagged: {}, untagged: [])
          @tag = tag
          @tagged = tagged.transform_values { |list| Array(list).map { |t| Types.resolve(t) } }
          @untagged = Array(untagged).map { |t| Types.resolve(t) }
        end

        def variants
          (@tagged.values.flatten + @untagged).map { |t| t.is_a?(Ref) ? t.target : t }
        end

        def coerce(value, path = [])
          if value.is_a?(Base)
            return value if variant_classes.any? { |variant| value.is_a?(variant) }

            return coerce(value.to_h, path)
          end

          if @tag && value.is_a?(Hash)
            tag_value = read_tag(value)
            candidates = @tagged[tag_value] if tag_value
            return try_variants(candidates, value, path) { |error| raise error } if candidates && !candidates.empty?
          end

          try_variants(@untagged, value, path) do
            raise ValidationError.new(union_error_message(value), path)
          end
        end

        private

        def variant_classes
          @variant_classes ||= variants.select { |variant| variant.is_a?(Class) }
        end

        def read_tag(hash)
          snake = Schema.to_snake(@tag)
          [@tag, @tag.to_sym, snake, snake.to_sym].each do |key|
            return hash[key] if hash.key?(key)
          end
          nil
        end

        def try_variants(candidates, value, path)
          last_error = nil
          candidates.each do |candidate|
            return candidate.coerce(value, path)
          rescue ValidationError => e
            last_error = e
          end
          yield(last_error || ValidationError.new(union_error_message(value), path))
        end

        def union_error_message(value)
          if @tag && value.is_a?(Hash)
            "no variant matches #{@tag}=#{read_tag(value).inspect}"
          else
            "no variant matches value of type #{value.class}"
          end
        end
      end
    end

    class Base
      FieldDef = Struct.new(
        :name, :key, :type, :required, :default, :const, :default_on_error,
        keyword_init: true
      )

      # Catch-all Other* variants must reject values reserved by known
      # variants, otherwise unions would accept malformed payloads
      # (e.g. action=accept in Other).
      RESERVED_TAGS = {
        "CreateOtherSessionElicitationRequest" => ["mode", %w[form url].freeze],
        "CreateOtherRequestElicitationRequest" => ["mode", %w[form url].freeze],
        "OtherElicitationResponse" => ["action", %w[accept cancel decline].freeze],
        "ElicitationOtherPropertySchema" => ["type", %w[array boolean integer number string].freeze],
        "OtherMultiSelectItems" => ["type", %w[string].freeze]
      }.freeze

      class << self
        def fields
          @fields ||= superclass.respond_to?(:fields) ? superclass.fields.dup : []
        end

        def field_names
          fields.map(&:name)
        end

        def field(name, type = :any, key: nil, required: false, default: nil, const: nil, default_on_error: false)
          name = name.to_sym
          fields.reject! { |f| f.name == name }
          fields << FieldDef.new(
            name: name,
            key: key || Schema.to_camel(name),
            type: Types.resolve(type),
            required: required,
            default: default,
            const: const,
            default_on_error: default_on_error
          )
          attr_reader name

          define_method(:"#{name}=") do |value|
            instance_variable_set(:"@#{name}", value)
            @set_fields << name
          end
        end

        def coerce(value, path = [])
          return value if value.is_a?(self)
          raise ValidationError.new("expected object, got #{value.class}", path) unless value.is_a?(Hash)

          instance = allocate
          instance.send(:load_from_hash, value, path)
          instance.send(:check_reserved_tags!, path)
          instance
        end

        def from_hash(hash)
          return nil if hash.nil?

          coerce(hash)
        end

        alias parse coerce
      end

      attr_accessor :field_meta

      def initialize(**kwargs)
        @set_fields = []
        @field_meta = kwargs.delete(:field_meta) || kwargs.delete(:_meta)
        unknown = kwargs.keys - self.class.field_names
        raise ArgumentError, "Unknown fields for #{self.class.name}: #{unknown.join(', ')}" unless unknown.empty?

        self.class.fields.each do |f|
          if kwargs.key?(f.name)
            value = kwargs[f.name]
            if value.nil?
              if f.const
                assign(f, f.const, set: true)
              elsif f.required && !f.default_on_error
                raise ValidationError.new("missing required field #{f.key}", [f.key])
              else
                assign(f, default_for(f), set: false)
              end
            else
              begin
                coerced = f.type.coerce(value, [f.key])
              rescue ValidationError
                raise unless f.default_on_error

                assign(f, default_for(f), set: false)
                next
              end
              raise ValidationError.new("expected #{f.const.inspect}, got #{coerced.inspect}", [f.key]) if f.const && coerced != f.const

              assign(f, coerced, set: true)
            end
          elsif f.const
            assign(f, f.const, set: true)
          elsif f.required
            raise ValidationError.new("missing required field #{f.key}", [f.key])
          else
            assign(f, default_for(f), set: false)
          end
        end
        check_reserved_tags!
      end

      def set?(name)
        @set_fields.include?(name.to_sym)
      end

      def [](name)
        public_send(name)
      end

      def to_h
        result = {}
        ordered_fields.each do |f|
          next unless f.const || @set_fields.include?(f.name)

          value = instance_variable_get(:"@#{f.name}")
          next if value.nil?

          result[f.key] = Schema.serialize(value)
        end
        result["_meta"] = Schema.serialize(@field_meta) if @field_meta
        result
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      def ==(other)
        other.class == self.class && other.to_h == to_h
      end

      alias eql? ==

      def hash
        [self.class, to_h].hash
      end

      def inspect
        "#<#{self.class.name} #{to_h.inspect}>"
      end

      private

      def ordered_fields
        fields = self.class.fields
        fields.select(&:const) + fields.reject(&:const)
      end

      def assign(field, value, set:)
        instance_variable_set(:"@#{field.name}", value)
        @set_fields << field.name if set
      end

      def default_for(field)
        default = field.default
        return nil if default.nil?

        default = deep_dup(default)
        begin
          field.type.coerce(default, [field.key])
        rescue ValidationError
          default
        end
      end

      def deep_dup(value)
        case value
        when Hash then value.transform_values { |v| deep_dup(v) }
        when Array then value.map { |v| deep_dup(v) }
        when String then value.dup
        else value
        end
      end

      def load_from_hash(hash, path)
        @set_fields = []
        self.class.fields.each do |f|
          present, raw = lookup(hash, f)
          if present && !raw.nil?
            load_present(f, raw, path)
          elsif f.const
            assign(f, f.const, set: true)
          elsif f.required && !(present && f.default_on_error)
            raise ValidationError.new("missing required field #{f.key}", path)
          else
            assign(f, default_for(f), set: false)
          end
        end
        meta = hash.key?("_meta") ? hash["_meta"] : hash[:_meta]
        @field_meta = meta.is_a?(Hash) ? meta : nil
      end

      def load_present(field, raw, path)
        value = field.type.coerce(raw, path + [field.key])
        raise ValidationError.new("expected #{field.const.inspect}, got #{value.inspect}", path + [field.key]) if field.const && value != field.const

        assign(field, value, set: true)
      rescue ValidationError
        raise unless field.default_on_error

        assign(field, default_for(field), set: false)
      end

      def lookup(hash, field)
        [field.key, field.key.to_sym, field.name.to_s, field.name].each do |candidate|
          return [true, hash[candidate]] if hash.key?(candidate)
        end
        [false, nil]
      end

      def check_reserved_tags!(path = [])
        rule = RESERVED_TAGS[self.class.name.split("::").last]
        return unless rule

        wire_field, reserved = rule
        field = self.class.fields.find { |f| f.key == wire_field || f.name.to_s == wire_field }
        return unless field

        value = instance_variable_get(:"@#{field.name}")
        return if value.nil?

        return unless reserved.include?(value)

        raise ValidationError.new(
          "#{wire_field} value is reserved by a known variant",
          path + [field.key]
        )
      end
    end
  end
end
