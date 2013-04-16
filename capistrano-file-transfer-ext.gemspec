# -*- encoding: utf-8 -*-
require File.expand_path('../lib/capistrano/configuration/actions/file_transfer_ext/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Yamashita Yuu"]
  gem.email         = ["yamashita@geishatokyo.com"]
  gem.description   = %q{A sort of utilities which helps you transferring files with Capistrano.}
  gem.summary       = %q{A sort of utilities which helps you transferring files with Capistrano.}
  gem.homepage      = "https://github.com/yyuu/capistrano-file-transfer-ext"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "capistrano-file-transfer-ext"
  gem.require_paths = ["lib"]
  gem.version       = Capistrano::Configuration::Actions::FileTransferExt::VERSION

  gem.add_dependency("capistrano", "< 3")
end
