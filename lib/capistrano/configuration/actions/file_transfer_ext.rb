require "capistrano/configuration/actions/file_transfer_ext/version"
require "capistrano/configuration"
require "capistrano/transfer"
require "stringio"

module Capistrano
  class Configuration
    module Actions
      module FileTransferExt
        def safe_put(data, path, options={})
          opts = options.dup
          safe_upload(StringIO.new(data), path, opts)
        end

        def safe_upload(from, to, options={}, &block)
          mode = options.delete(:mode)
          via = ( options.delete(:via) || :run )
          compare_method = ( options.delete(:compare_method) || :cmp )
          begin
            tempname = File.join("/tmp", File.basename(to) + ".XXXXXXXXXX")
            tempfile = capture("mktemp #{tempname.dump}").strip
            run("rm -f #{tempfile.dump}", options)
            transfer(:up, from, tempfile, options, &block)
            execute = []
            execute << "mkdir -p #{File.dirname(to).dump}"
            case compare_method
            when :diff
              execute << "( diff -u #{to.dump} #{tempfile.dump} || mv -f #{tempfile.dump} #{to.dump} )"
            else
              execute << "( cmp #{to.dump} #{tempfile.dump} || mv -f #{tempfile.dump} #{to.dump} )"
            end
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
