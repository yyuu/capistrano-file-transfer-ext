require "capistrano/configuration/actions/file_transfer_ext/version"
require "capistrano/configuration"
require "capistrano/transfer"
require "stringio"

module Capistrano
  class Configuration
    module Actions
      module FileTransferExt
# FIXME: better way to filter out hexdigests from output of md5sum (both GNU and BSD).
#        currently, we regards 16+ consecutive [0-9a-f] as string of hexdigest.
#        since mawk does not recognize /.{n}/ style quantifier, the regex is very scary.
        DIGEST_FILTER_CMD = "awk '%s'" % %q{
{
  for(n=1;n<=NF;n++){
    if(match($n,
"^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]+$"
       )){
      print($n);break
    }
  }
}
        }.gsub(/\s+/, "").strip

        def safe_put(data, path, options={})
          opts = options.dup
          safe_upload(StringIO.new(data), path, opts)
        end

        # upload file from local to remote.
        # this method uses temporary file to avoid incomplete transmission of files.
        #
        # The +options+ hash may include any of the following keys:
        #
        # * :transfer - use transfer_if_modified if :if_modified is set
        # * :install - use install_if_modified if :if_modified is set
        # * :run_method - the default is :run.
        def safe_upload(from, to, options={}, &block)
          transfer_method = options.delete(:transfer) == :if_modified ? :transfer_if_modified : :transfer
          if options.has_key?(:install)
            install_method = options.delete(:install) == :if_modified ? :install_if_modified : :install
          else
            # for backward compatibility before v0.0.4.
            install_method = options.delete(:place)   == :if_modified ? :install_if_modified : :install
          end
          run_method = ( options.delete(:run_method) || :run )
          begin
            tempname = File.join("/tmp", File.basename(to) + ".XXXXXXXXXX")
            tempfile = capture("mktemp #{tempname.dump}").strip
            run("rm -f #{tempfile.dump}", options)
            send(transfer_method, :up, from, tempfile, options, &block)
            send(install_method, tempfile, to, options.merge(:via => run_method), &block)
          ensure
            run("rm -f #{tempfile.dump}", options) rescue nil
          end
        end

        # transfer file (or IO like object) from local to remote, only if the file checksum is differ.
        # do not care if the transfer has been completed or not.
        #
        # The +options+ hash may include any of the following keys:
        #
        # * :digest - digest algorithm. the default is "md5".
        # * :digest_cmd - the digest command. the default is "#{digest}sum".
        #
        def transfer_if_modified(direction, from, to, options={}, &block)
          digest_method = options.fetch(:digest, "md5")
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
          logger.debug("#{digest_method.upcase}(#{target}) = #{digest}")
          if dry_run
            logger.debug("transfering: #{[direction, from, to] * ', '}")
          else
            execute_on_servers(options) do |servers|
              targets = servers.map { |server| sessions[server] }.reject { |session|
                remote_digest = session.exec!("test -f #{remote_target.dump} && #{digest_cmd} #{remote_target.dump} | #{DIGEST_FILTER_CMD}")
                logger.debug("#{session.xserver.host}: #{digest_method.upcase}(#{remote_target}) = #{remote_digest}")
                result = !( digest.nil? or remote_digest.nil? ) && digest.strip == remote_digest.strip
                logger.info("#{session.xserver.host}: skip transfering since no changes: #{[direction, from, to] * ', '}") if result
                result
              }
              Capistrano::Transfer.process(direction, from, to, targets, options.merge(:logger => logger), &block) unless targets.empty?
            end
          end
        end

        # install a file on remote.
        #
        # The +options+ hash may include any of the following keys:
        #
        # * :mode - permission of the file.
        # * :sudo - use sudo if set true. the default is false.
        #
        def install(from, to, options={}, &block)
          mode = options.delete(:mode)
          try_sudo = options.delete(:sudo) ? sudo : ""
          execute = []
          execute << "( test -d #{File.dirname(to).dump} || #{try_sudo} mkdir -p #{File.dirname(to).dump} )"
          execute << "#{try_sudo} mv -f #{from.dump} #{to.dump}"
          if mode
            mode = mode.is_a?(Numeric) ? mode.to_s(8) : mode.to_s
            execute << "#{try_sudo} chmod #{mode} #{to.dump}"
          end
          invoke_command(execute.join(" && "), options)
        end
        alias place install

        # install a file on remote, only if the destination is differ from source.
        #
        # The +options+ hash may include any of the following keys:
        #
        # * :mode - permission of the file.
        # * :sudo - use sudo if set true. the default is false.
        # * :digest - digest algorithm. the default is "md5".
        # * :digest_cmd - the digest command. the default is "#{digest}sum".
        #
        def install_if_modified(from, to, options={}, &block)
          mode = options.delete(:mode)
          try_sudo = options.delete(:sudo) ? sudo : ""
          digest_method = options.fetch(:digest, "md5")
          digest_cmd = options.fetch(:digest_cmd, "#{digest_method.downcase}sum")
          execute = []
          execute << %{( test -d #{File.dirname(to).dump} || #{try_sudo} mkdir -p #{File.dirname(to).dump} )}
          # calculate hexdigest of `from'
          execute << %{from=$(#{digest_cmd} #{from.dump} 2>/dev/null | #{DIGEST_FILTER_CMD} || true)}
          execute << %{echo %s} % ["#{digest_method.upcase}(#{from}) = ${from}".dump]
          # calculate hexdigest of `to'
          execute << %{to=$(#{digest_cmd} #{to.dump} 2>/dev/null | #{DIGEST_FILTER_CMD} || true)}
          execute << %{echo %s} % ["#{digest_method.upcase}(#{to}) = ${to}".dump]
          # check the hexdigests
          execute << (<<-EOS).gsub(/\s+/, " ").strip
            if [ -n "${from}" -a "${to}" ] && [ "${from}" = "${to}" ]; then
              echo "skip placing since no changes.";
            else
              #{try_sudo} mv -f #{from.dump} #{to.dump};
            fi
          EOS

          if mode
            mode = mode.is_a?(Numeric) ? mode.to_s(8) : mode.to_s
            execute << "#{try_sudo} chmod #{mode} #{to.dump}"
          end
          invoke_command(execute.join(" && "), options)
        end
        alias place_if_modified install_if_modified
      end
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::Configuration::Actions::FileTransferExt)
end

# vim:set ft=ruby sw=2 ts=2 :
