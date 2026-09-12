# frozen_string_literal: true

require "rack"
require "rack/test"
require "header_guard"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |c| c.verify_partial_doubles = true }

  # No top-level `describe`; everything goes through RSpec.describe.
  config.disable_monkey_patching!

  # Random order surfaces accidental coupling between examples. The seed is
  # printed on every run and can be replayed with --seed.
  config.order = :random
  Kernel.srand config.seed

  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
end
