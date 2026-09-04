# frozen_string_literal: true

require "json"

module ACP
end

module ACP::SchemaGenerator
  ROOT = File.expand_path("..", __dir__)
  SCHEMA_DIR = File.join(ROOT, "schema")
  OUT_SCHEMA = File.join(ROOT, "lib", "acp", "schema.rb")
  OUT_META = File.join(ROOT, "lib", "acp", "meta.rb")

  SKIP_DEFS = /\A(Agent|Client)(Message|Request|Response|Notification)\z/

  DEF_RENAMES = {
    "AvailableCommandsUpdate" => "AvailableCommandsUpdateBase",
    "ConfigOptionUpdate" => "ConfigOptionUpdateBase",
    "CurrentModeUpdate" => "CurrentModeUpdateBase",
    "SessionInfoUpdate" => "SessionInfoUpdateBase",
    "UsageUpdate" => "UsageUpdateBase",
    "StringMultiSelectItems" => "StringMultiSelectItemsBase"
  }.freeze

  VARIANT_NAMES = {
    "ContentBlock" => %w[
      TextContentBlock ImageContentBlock AudioContentBlock ResourceContentBlock EmbeddedResourceContentBlock
    ],
    "ToolCallContent" => %w[ContentToolCallContent FileEditToolCallContent TerminalToolCallContent],
    "PlanUpdateContent" => %w[PlanUpdateItems PlanUpdateFile PlanUpdateMarkdown],
    "NesSuggestion" => %w[
      NesEditSuggestionVariant NesJumpSuggestionVariant NesRenameSuggestionVariant NesSearchAndReplaceSuggestionVariant
    ],
    "SessionUpdate" => %w[
      UserMessageChunk AgentMessageChunk AgentThoughtChunk ToolCallStart ToolCallProgress AgentPlanUpdate
      AgentPlanContentUpdate AgentPlanRemovedUpdate AvailableCommandsUpdate CurrentModeUpdate ConfigOptionUpdate
      SessionInfoUpdate UsageUpdate SessionUpdateCompactionUpdate SessionUpdateCompactionSummaryChunk
    ],
    "McpServer" => %w[HttpMcpServer SseMcpServer AcpMcpServer],
    "AuthMethod" => %w[TerminalAuthMethod],
    "SessionConfigOption" => %w[SessionConfigOptionSelect SessionConfigOptionBoolean],
    "RequestPermissionOutcome" => %w[DeniedOutcome AllowedOutcome],
    "CreateElicitationResponse" => %w[
      AcceptElicitationResponse DeclineElicitationResponse CancelElicitationResponse OtherElicitationResponse
    ],
    "ElicitationPropertySchema" => %w[
      ElicitationStringPropertySchema ElicitationNumberPropertySchema ElicitationIntegerPropertySchema
      ElicitationBooleanPropertySchema ElicitationMultiSelectPropertySchema ElicitationOtherPropertySchema
    ],
    "MultiSelectItems" => %w[StringMultiSelectItems OtherMultiSelectItems],
    "SetSessionConfigOptionRequest" => %w[SetSessionConfigOptionBooleanRequest SetSessionConfigOptionSelectRequest],
    "ElicitationFormMode" => %w[ElicitationFormSessionMode ElicitationFormRequestMode],
    "ElicitationUrlMode" => %w[ElicitationUrlSessionMode ElicitationUrlRequestMode],
    "CreateElicitationRequest" => {
      "0.0" => "CreateFormSessionElicitationRequest",
      "0.1" => "CreateFormRequestElicitationRequest",
      "1.0" => "CreateUrlSessionElicitationRequest",
      "1.1" => "CreateUrlRequestElicitationRequest",
      "2.0" => "CreateOtherSessionElicitationRequest",
      "2.1" => "CreateOtherRequestElicitationRequest"
    }
  }.freeze

  RESERVED_FIELD_NAMES = {
    "method" => "method_name",
    "class" => "klass",
    "hash" => "hash_value",
    "send" => "send_value",
    "object_id" => "object_identifier"
  }.freeze

  SPECIAL_SCALARS = {
    "ProtocolVersion" => "Types::PROTOCOL_VERSION"
  }.freeze

  Field = Struct.new(:name, :key, :type_expr, :required, :default, :const, :default_on_error, keyword_init: true)
  Shape = Struct.new(
    :name, :fields, :own_fields, :parent, :ref_only, :source, :tag_key, :tag_value, :path,
    keyword_init: true
  )

  class Generator
    def initialize(schema_dir: SCHEMA_DIR)
      @schema = JSON.parse(File.read(File.join(schema_dir, "schema.json")))
      @meta = JSON.parse(File.read(File.join(schema_dir, "meta.json")))
      @version = File.read(File.join(schema_dir, "VERSION")).strip
      @defs = @schema.fetch("$defs")
      @plain_classes = []
      @variant_classes = []
      @constants = []
      @shape_cache = {}
      @emitted_names = {}
    end

    def render_schema
      @defs.each do |name, definition|
        next if name.match?(SKIP_DEFS)

        emit_def(name, definition)
      end

      lines = []
      lines << "# frozen_string_literal: true"
      lines << ""
      lines << 'require_relative "schema_base"'
      lines << ""
      lines << "module ACP"
      lines << "  module Schema"
      lines << "    SCHEMA_REF = #{@version.inspect}"
      lines << ""
      (@plain_classes + @variant_classes).each do |klass|
        lines.concat(render_class(klass))
        lines << ""
      end
      @constants.each { |line| lines << "    #{line}" }
      lines << "  end"
      lines << "end"
      "#{lines.join("\n")}\n"
    end

    def render_meta
      lines = []
      lines << "# frozen_string_literal: true"
      lines << ""
      lines << "module ACP"
      lines << "  PROTOCOL_VERSION = #{@meta.fetch('version')}"
      lines << "  SCHEMA_REF = #{@version.inspect}"
      lines << ""
      lines.concat(render_method_map("AGENT_METHODS", @meta.fetch("agentMethods")))
      lines << ""
      lines.concat(render_method_map("CLIENT_METHODS", @meta.fetch("clientMethods")))
      lines << ""
      lines.concat(render_method_map("PROTOCOL_METHODS", @meta.fetch("protocolMethods")))
      lines << "end"
      "#{lines.join("\n")}\n"
    end

    private

    def render_method_map(const_name, map)
      lines = ["  #{const_name} = {"]
      entries = map.map { |key, value| "    #{key.inspect} => #{value.inspect}" }
      lines << entries.join(",\n")
      lines << "  }.freeze"
      lines
    end

    def render_class(klass)
      parent = klass[:parent] || "Base"
      header = "    class #{klass[:name]} < #{parent}"
      return ["#{header}; end"] if klass[:fields].empty?

      lines = [header]
      klass[:fields].each { |f| lines << "      #{field_line(f)}" }
      lines << "    end"
      lines
    end

    def field_line(field)
      parts = [":#{field.name}", field.type_expr]
      parts << "key: #{field.key.inspect}" if camel(field.name) != field.key
      parts << "required: true" if field.required && field.const.nil?
      parts << "default: #{field.default.inspect}" unless field.default.nil?
      parts << "const: #{field.const.inspect}" unless field.const.nil?
      parts << "default_on_error: true" if field.default_on_error
      "field #{parts.join(', ')}"
    end

    def emit_def(name, definition)
      if object_with_variants?(definition)
        shapes = shapes_for_def(name)
        shapes.each { |shape| emit_shape(shape) }
        @constants << union_constant(ruby_name(name), shapes)
      elsif variants?(definition)
        emit_union_def(name, definition)
      elsif object_class?(definition)
        add_class(@plain_classes, name: ruby_name(name), fields: fields_for(definition))
      else
        @constants << "#{ruby_name(name)} = #{scalar_alias(name, definition)}"
      end
    end

    def emit_union_def(name, definition)
      variants = definition["oneOf"] || definition["anyOf"]
      kinds = variants.map { |v| variant_kind(v) }

      if kinds.all? { |k| %i[enum_member enum_open].include?(k) }
        values = variants.select { |v| v.key?("const") }.map { |v| v["const"] }
        open = kinds.include?(:enum_open)
        @constants << "#{ruby_name(name)} = Types::Enum.new(#{values.inspect}#{open ? ', open: true' : ''})"
      elsif kinds.all? { |k| %i[scalar enum_open].include?(k) }
        exprs = variants.map { |v| type_expr(v) }.uniq
        exprs.reject! { |e| e == ":any" } if exprs.size > 1
        if exprs.size == 1 && !exprs.first.start_with?("Types::List")
          @constants << "#{ruby_name(name)} = #{scalar_constant(exprs.first)}"
        elsif exprs.all? { |e| e.start_with?("Types::List") }
          @constants << "#{ruby_name(name)} = Types::Union.new(untagged: [#{exprs.join(', ')}])"
        else
          @constants << "#{ruby_name(name)} = Types::ANY"
        end
      else
        shapes = shapes_for_def(name)
        shapes.each { |shape| emit_shape(shape) }
        @constants << union_constant(ruby_name(name), shapes)
      end
    end

    def emit_shape(shape)
      return if shape.ref_only

      fields = shape.parent ? shape.own_fields : shape.fields
      add_class(@variant_classes, name: shape.name, fields: fields, parent: shape.parent)
    end

    def add_class(list, name:, fields:, parent: nil)
      raise "Duplicate generated name: #{name}" if @emitted_names.key?(name)

      @emitted_names[name] = true
      list << { name: name, fields: fields, parent: parent }
    end

    def union_constant(const_name, shapes)
      tag_key = shapes.map(&:tag_key).compact.first
      tagged = {}
      untagged = []
      shapes.each do |shape|
        type_name = shape.ref_only || shape.name
        if shape.tag_value
          (tagged[shape.tag_value] ||= []) << type_name
        else
          untagged << type_name
        end
      end
      args = []
      args << "tag: #{tag_key.inspect}" if tag_key && !tagged.empty?
      unless tagged.empty?
        entries = tagged.map { |value, names| "#{value.inspect} => #{names.inspect}" }
        args << "tagged: { #{entries.join(', ')} }"
      end
      args << "untagged: #{untagged.inspect}" unless untagged.empty?
      "#{const_name} = Types::Union.new(#{args.join(', ')})"
    end

    def scalar_alias(name, definition)
      return SPECIAL_SCALARS[name] if SPECIAL_SCALARS.key?(name)

      scalar_constant(type_expr(definition))
    end

    def scalar_constant(expr)
      case expr
      when ":string" then "Types::STRING"
      when ":integer" then "Types::INTEGER"
      when ":number" then "Types::NUMBER"
      when ":boolean" then "Types::BOOLEAN"
      when ":object" then "Types::OBJECT"
      when ":any" then "Types::ANY"
      else expr
      end
    end

    def variants?(definition)
      definition.key?("oneOf") || definition.key?("anyOf")
    end

    def object_with_variants?(definition)
      variants?(definition) && definition.key?("properties")
    end

    def object_class?(definition)
      return false unless definition["type"] == "object"

      definition.key?("properties") || !definition.key?("additionalProperties")
    end

    def variant_kind(variant)
      return :enum_member if variant["type"] == "string" && variant.key?("const")
      return :enum_open if variant["type"] == "string" && !variant.key?("properties") && !variant.key?("allOf")
      return :object if variant.key?("properties") || variant.key?("allOf") || variant.key?("anyOf") || variant.key?("oneOf")
      return :object if variant.key?("$ref")

      :scalar
    end

    def shapes_for_def(name)
      @shape_cache[name] ||= begin
        definition = @defs.fetch(name)
        if variants?(definition)
          expand_variants(name, definition)
        else
          fields = object_class?(definition) ? fields_for(definition) : []
          [Shape.new(name: ruby_name(name), fields: fields, own_fields: fields, ref_only: ruby_name(name), source: name, path: [])]
        end
      end
    end

    def expand_variants(def_name, definition)
      base_fields = fields_for(definition)
      variants = definition["oneOf"] || definition["anyOf"]
      variants.each_with_index.flat_map do |variant, index|
        next [] unless variant_kind(variant) == :object

        expand_node(variant, def_name, [index]).map do |shape|
          finalize_shape(def_name, shape, base_fields, variant)
        end
      end
    end

    def finalize_shape(def_name, shape, base_fields, variant)
      if base_fields.empty?
        return shape if shape.ref_only

        shape.name = variant_name(def_name, shape.path, shape.tag_value, variant["title"])
        return shape
      end

      Shape.new(
        name: variant_name(def_name, shape.path, shape.tag_value, variant["title"]),
        fields: merge_fields(base_fields, shape.fields),
        own_fields: merge_fields(base_fields, shape.fields),
        tag_key: shape.tag_key,
        tag_value: shape.tag_value,
        path: shape.path
      )
    end

    def expand_node(node, def_name, path)
      own_fields = fields_for(node)
      tag = own_fields.find { |f| !f.const.nil? }
      ref_names = Array(node["allOf"]).map { |entry| ref_name(entry) }
      ref_names << ref_name(node) if node.key?("$ref")
      nested = node["anyOf"] || node["oneOf"] || []

      components = ref_names.map do |ref|
        alternatives = shapes_for_def(ref)
        alternatives.each_with_index.map do |shape, index|
          [shape, alternatives.size > 1 ? path + [index] : path]
        end
      end
      unless nested.empty?
        components << nested.each_with_index.flat_map do |child, index|
          expand_node(child, def_name, path + [index]).map { |shape| [shape, shape.path] }
        end
      end

      if components.empty?
        return [Shape.new(fields: own_fields, own_fields: own_fields, tag_key: tag&.key, tag_value: tag&.const, path: path)]
      end

      product(components).map do |combo|
        shapes = combo.map(&:first)
        combo_path = combo.size == 1 ? combo.first.last : path + combo.map { |(_, p)| p.last }
        merged = merge_fields(own_fields, shapes.flat_map(&:fields))
        single = shapes.size == 1 ? shapes.first : nil
        if own_fields.empty? && single
          Shape.new(
            fields: merged, own_fields: merged, ref_only: single.ref_only || single.name,
            tag_key: single.tag_key, tag_value: single.tag_value, path: combo_path
          )
        elsif single&.ref_only && plain_def?(single) && own_fields.all? { |f| !f.const.nil? }
          Shape.new(
            fields: merged, own_fields: own_fields, parent: single.ref_only,
            tag_key: tag&.key, tag_value: tag&.const, path: combo_path
          )
        else
          Shape.new(fields: merged, own_fields: merged, tag_key: tag&.key, tag_value: tag&.const, path: combo_path)
        end
      end
    end

    def plain_def?(shape)
      shape.source && object_class?(@defs[shape.source])
    end

    def product(components)
      components.reduce([[]]) do |acc, alternatives|
        acc.flat_map { |prefix| alternatives.map { |alt| prefix + [alt] } }
      end
    end

    def merge_fields(first, second)
      (first + second).each_with_object({}) { |f, h| h[f.key] = f }.values
    end

    def variant_name(def_name, path, tag_value, title)
      table = VARIANT_NAMES[def_name]
      key = path.join(".")
      name = case table
             when Array then path.size == 1 ? table[path.first] : nil
             when Hash then table[key]
             end
      return name if name

      suffix = tag_value || title
      suffix ? "#{ruby_name(def_name)}#{camel_class(suffix)}" : "#{ruby_name(def_name)}Variant#{key.tr('.', '_')}"
    end

    def fields_for(node)
      properties = node["properties"] || {}
      required = Array(node["required"])
      properties.filter_map do |prop, spec|
        next if prop == "_meta"

        spec = {} unless spec.is_a?(Hash)
        name = field_name(prop)
        Field.new(
          name: name,
          key: prop,
          type_expr: spec.key?("const") ? ":string" : type_expr(spec),
          required: required.include?(prop),
          default: spec["default"],
          const: spec["const"],
          default_on_error: spec["x-deserialize-default-on-error"] == true
        )
      end
    end

    def field_name(prop)
      snake = snake_case(prop)
      RESERVED_FIELD_NAMES.fetch(snake, snake)
    end

    def type_expr(spec)
      return ruby_name(ref_name(spec)).inspect if spec.key?("$ref")

      all_of = spec["allOf"]
      return type_expr(all_of.first) if all_of.is_a?(Array) && all_of.size == 1

      union = spec["anyOf"] || spec["oneOf"]
      if union.is_a?(Array)
        non_null = union.reject { |entry| entry["type"] == "null" }
        return type_expr(non_null.first) if non_null.size == 1

        return ":any"
      end

      types = Array(spec["type"]) - ["null"]
      case types
      when ["string"]
        spec["enum"] ? "Types::Enum.new(#{spec['enum'].inspect})" : ":string"
      when ["integer"] then ":integer"
      when ["number"] then ":number"
      when ["boolean"] then ":boolean"
      when ["array"]
        skip = spec["x-deserialize-skip-invalid-items"] == true ? ", skip_invalid: true" : ""
        "Types::List.new(#{type_expr(spec['items'] || {})}#{skip})"
      when ["object"]
        additional = spec["additionalProperties"]
        additional.is_a?(Hash) ? "Types::Map.new(#{type_expr(additional)})" : ":object"
      else
        ":any"
      end
    end

    def ref_name(spec)
      spec.fetch("$ref").split("/").last
    end

    def ruby_name(def_name)
      DEF_RENAMES.fetch(def_name, def_name)
    end

    def snake_case(text)
      text.gsub(/([a-z0-9])([A-Z])/, '\1_\2').gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').downcase
    end

    def camel(snake)
      parts = snake.to_s.split("_")
      parts[0] + parts[1..].map(&:capitalize).join
    end

    def camel_class(text)
      text.to_s.split(/[^A-Za-z0-9]+/).map { |part| part[0].upcase + part[1..] }.join
    end
  end

  def self.run(schema_dir: SCHEMA_DIR, schema_out: OUT_SCHEMA, meta_out: OUT_META)
    generator = Generator.new(schema_dir: schema_dir)
    File.write(schema_out, generator.render_schema)
    File.write(meta_out, generator.render_meta)
  end
end

ACP::SchemaGenerator.run if $PROGRAM_NAME == __FILE__
