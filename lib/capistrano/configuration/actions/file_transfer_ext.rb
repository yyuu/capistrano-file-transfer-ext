require "capistrano/configuration/actions/file_transfer_ext/version"
require "capistrano/configuration"
require "capistrano/transfer"
require "stringio"

module Capistrano
  class Configuration
    module Actions
      module FileTransferExt
        DIGEST_FILTER_CMD = %{awk '{for(n=1;n<=NF;n++){if(match($n,"^[0-9a-z]{16,}$")){print($n);break}}}'}

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

        # transfer file (or IO like object) from local to remote.
        # do not care if the transfer has been completed or not.
        def _transfer(direction, from, to, options={}, &block)
          transfer(direction, from, to, options, &block)
        end

        # transfer file (or IO like object) from local to remote, only if the file checksum is differ.
        # do not care if the transfer has been completed or not.
        def _transfer_if_modified(direction, from, to, options={}, &block)
          digest_method = options.fetch(:digest_method, "md5")
          digest_cmd = options.fetch(:digest_cmd, "#{digest_method.downcase}sum")
          require "digest/#{digest_method.downcase}"
          target = direction == :up ? from : to
          remote_target = direction == :up ? to : from
          if target.respond_to?(:read)
            pos = target.pos
            digest = Digest.const_get(digest_method.upcase).hexdigest(target.read)
            target.pos = pos
          else
            begin
              digest = Digest::const_get(digest_method.upcase).hexdigest(File.read(target))
            rescue SystemCallError
              digest = nil
            end
          end
          if dry_run
            logger.debug("transfering: #{[direction, from, to] * ', '}")
          else
            execute_on_servers(options) do |servers|
              targets = servers.map { |server| sessions[server] }.reject { |session|
                remote_digest = session.exec!("test -f #{remote_target.dump} && #{digest_cmd} #{remote_target.dump} | #{DIGEST_FILTER_CMD}")
                result = !( digest.nil? or remote_digest.nil? ) && digest == remote_digest.strip
                logger.info("#{session.xserver.host}: skip transfering since no changes: #{[direction, from, to] * ', '}") if result
                result
              }
              Capistrano::Transfer.process(direction, from, to, targets, options.merge(:logger => logger), &block) unless targets.empty?
            end
          end
        end

        # place a file on remote.
        def _place(from, to, options={}, &block)
          mode = options.delete(:mode)
          execute = []
          execute << "mv -f #{from.dump} #{to.dump}"
          if mode
            mode = mode.is_a?(Numeric) ? mode.to_s(8) : mode.to_s
            execute << "chmod #{mode} #{to.dump}"
          end
          invoke_command(execute.join(" && "), options)
        end

        # place a file on remote, only if the destination is differ from source.
        def _place_if_modified(from, to, options={}, &block)
          mode = options.delete(:mode)
          digest_method = options.fetch(:digest_method, "md5")
          digest_cmd = options.fetch(:digest_cmd, "#{digest_method.downcase}sum")
          execute = []
          execute << %{from=$(#{digest_cmd} #{from.dump} | #{DIGEST_FILTER_CMD})}
          execute << %{to=$(#{digest_cmd} #{to.dump} | #{DIGEST_FILTER_CMD})}
          execute << %{( test "x${from}" = "x${to}" || ( echo #{from.dump} '->' #{to.dump}; mv -f #{from.dump} #{to.dump} ) )}
          if mode
            mode = mode.is_a?(Numeric) ? mode.to_s(8) : mode.to_s
            execute << "chmod #{mode} #{to.dump}"
          end
          invoke_command(execute.join(" && "), options)
        end
      end
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::Configuration::Actions::FileTransferExt)
end

# vim:set ft=ruby sw=2 ts=2 :
