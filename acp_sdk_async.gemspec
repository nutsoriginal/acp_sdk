# frozen_string_literal: true

require_relative "lib/acp/version"

Gem::Specification.new do |spec|
  spec.name = "acp_sdk_async"
  spec.version = ACP::VERSION
  spec.authors = ["nutsoriginal"]
  spec.summary = "Ruby SDK for the Agent Client Protocol (ACP)"
  spec.description = "Typed schema models, JSON-RPC connection, agent and client wrappers, " \
                     "and stdio process management for the Agent Client Protocol."
  spec.homepage = "https://github.com/nutsoriginal/acp_sdk"
  spec.license = "Unlicense"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "https://agentclientprotocol.com"

  spec.files = Dir["lib/**/*.rb", "schema/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "async", "~> 2.32"
  spec.add_dependency "logger", ">= 1.6"
end
