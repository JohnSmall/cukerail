# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cukerail/version'
require "cukerail/testrail"
# require "cucumber_extensions/formatters/json/builder"

Gem::Specification.new do |spec|
  spec.name          = "cukerail"
  spec.version       = Cukerail::VERSION
  spec.authors       = ["John Small"]
  spec.email         = ["john.small@bbc.com"]
  spec.summary       = %q{Integrates Cucumber and Testrail from Gurock Software}
  spec.description   = %q{Allows you to sync your Testrail testcases from feature files and send test results into Testrail testruns}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "cucumber", "~> 2.3.2"
  spec.add_runtime_dependency 'retriable', '~> 2.1'

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake","~>10.4"
  spec.add_development_dependency "rspec","~>3.2"
  spec.add_development_dependency "pry","~>0.10"
  spec.add_development_dependency "byebug"
  spec.add_development_dependency "awesome_print"
end
