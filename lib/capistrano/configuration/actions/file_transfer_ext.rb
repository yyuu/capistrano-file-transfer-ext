require "capistrano/configuration/actions/file_transfer_ext/version"
require "capistrano/configuration"
require "capistrano/transfer"

module Capistrano
  class Configuration
    module Actions
      module FileTransferExt
        def safe_upload(from, to, options={}, &block)
          mode = options.delete(:mode)
          via = options.delete(:via)
          begin
            tempname = File.join("/tmp", File.basename(to) + ".XXXXXXXXXX")
            tempfile = capture("mktemp #{tempname.dump}").strip
            run("rm -f #{tempfile.dump}", options)
            transfer(:up, from, tempfile, options, &block)
            execute = []
            execute << "( diff -u #{to.dump} #{tempfile.dump} || mv -f #{tempfile.dump} #{to.dump} )"
            if mode
              mode = mode.is_a?(Numeric) ? mode.to_s(8) : mode.to_s
              execute << "chmod #{mode} #{to}"
            end
            invoke_command(execute.join(" && "), options.merge(:via => via))
          ensure
            run("rm -f #{tempfile.dump}", options) rescue nil
          end
        end
      end
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::Configuration::Actions::FileTransferExt)
end

# vim:set ft=ruby sw=2 ts=2 :
