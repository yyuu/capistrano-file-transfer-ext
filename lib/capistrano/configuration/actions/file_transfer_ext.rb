require "capistrano/configuration/actions/file_transfer_ext/version"
require "capistrano/configuration"
require "capistrano/transfer"
require "find"
require "pathname"
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
          options = options.dup
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
          safe_options = options.dup
          digest_method = safe_options.fetch(:digest, :md5).to_s
          digest_cmd = safe_options.fetch(:digest_cmd, "#{digest_method.downcase}sum")
          target        = direction == :up ? from : to
          remote_target = direction == :up ? to : from
          require "digest/#{digest_method.downcase}"
          target_is_io = target.respond_to?(:read)
          if not(target_is_io) and FileTest.directory?(target)
            Find.find(target) do |_target|
              relative_path = Pathname.new(_target).relative_path_from(Pathname.new(target))
              _remote_target = File.join(remote_target, relative_path)
              from = direction == :up ? _target : _remote_target
              to   = direction == :up ? _remote_target : _target
              transfer_if_modified(direction, from, to, options, &block) unless FileTest.directory?(_target)
            end
          else
            if target_is_io
              pos = target.pos
              digest = Digest.const_get(digest_method.upcase).hexdigest(target.read)
              target.pos = pos
            else
              begin
                digest = Digest.const_get(digest_method.upcase).hexdigest(File.read(target))
              rescue SystemCallError
                digest = nil
              end
            end
            logger.debug("#{digest_method.upcase}(#{target}) = #{digest}")
            if dry_run
              logger.debug("transfering: #{[direction, from, to] * ', '}")
            else
              execute_on_servers(safe_options) do |servers|
                targets = servers.map { |server| sessions[server] }.reject { |session|
                  remote_digest = session.exec!("test -f #{remote_target.dump} && #{digest_cmd} #{remote_target.dump} | #{DIGEST_FILTER_CMD}")
                  logger.debug("#{session.xserver.host}: #{digest_method.upcase}(#{remote_target}) = #{remote_digest}")
                  result = !( digest.nil? or remote_digest.nil? ) && digest.strip == remote_digest.strip
                  logger.info("#{session.xserver.host}: skip transfering since no changes: #{[direction, from, to] * ', '}") if result
                  result
                }
                Capistrano::Transfer.process(direction, from, to, targets, safe_options.merge(:logger => logger), &block) unless targets.empty?
              end
            end
          end
        end

        # install a file on remote.
        #
        # The +options+ hash may include any of the following keys:
        #
        # * :mode - permission of the file.
        # * :via - :run by default.
        #
        def install(from, to, options={}, &block)
          options = options.dup
          via = options.delete(:via)
          if via == :sudo or options.delete(:sudo) # check :sudo for backward compatibility
            # ignore {:via => :sudo} since `sudo()` cannot handle multiple commands properly.
            _try_sudo = sudo
          else
            _try_sudo = ""
            options[:via] = via if via
          end
          # * If :mode is :preserve or :mode is not given, preserve original mode.
          # * Otherwise, just respect given :mode.
          mode_given = options.key?(:mode)
          mode = options.delete(:mode)
          if mode_given ? mode == :preserve : true
            if fetch(:install_preserve_mode, true)
              begin
                # respect mode of original file
                # `stat -c` for GNU, `stat -f` for BSD
                s = capture("test -f #{to.dump} && ( stat -c '%a' #{to.dump} || stat -f '%p' #{to.dump} )", options)
                mode = s.to_i(8) & 0777 if /^[0-7]+$/ =~ s
                logger.debug("preserve original file mode #{mode.to_s(8)}.")
              rescue
                mode = nil
              end
            else
              mode = nil
            end
          end
          owner_given = options.key?(:owner)
          owner = options.delete(:owner)
          if owner_given ? owner == :preserve : true
            if fetch(:install_preserve_owner, true) and via == :sudo
              begin
                owner = capture("test -f #{to.dump} && ( stat -c '%u' #{to.dump} || stat -f '%u' #{to.dump} )", options).strip
                logger.debug("preserve original file owner #{owner.dump}.")
              rescue
                owner = nil
              end
            else
              owner = nil
            end
          end
          group_given = options.key?(:group)
          group = options.delete(:group)
          if group_given ? group == :preserve : true
            if fetch(:install_preserve_group, true) and via == :sudo
              begin
                group = capture("test -f #{to.dump} && ( stat -c '%g' #{to.dump} || stat -f '%g' #{to.dump} )", options).strip
                logger.debug("preserve original file grop #{group.dump}.")
              rescue
                group = nil
              end
            else
              group = nil
            end
          end
          execute = []
          if block_given?
            execute << yield(from, to)
          else
            execute << "( test -d #{File.dirname(to).dump} || #{_try_sudo} mkdir -p #{File.dirname(to).dump} )"
            execute << "#{_try_sudo} mv -f #{from.dump} #{to.dump}"
          end
          if mode
            mode = mode.is_a?(Numeric) ? mode.to_s(8) : mode.to_s
            execute << "#{_try_sudo} chmod #{mode.dump} #{to.dump}"
          end
          execute << "#{_try_sudo} chown #{owner.to_s.dump} #{to.dump}" if owner
          execute << "#{_try_sudo} chgrp #{group.to_s.dump} #{to.dump}" if group
          invoke_command(execute.join(" && "), options)
        end
        alias place install

        # install a file on remote, only if the destination is differ from source.
        #
        # The +options+ hash may include any of the following keys:
        #
        # * :mode - permission of the file.
        # * :via - :run by default.
        # * :digest - digest algorithm. the default is "md5".
        # * :digest_cmd - the digest command. the default is "#{digest}sum".
        #
        def install_if_modified(from, to, options={}, &block)
          options = options.dup
          if options[:via] == :sudo or options.delete(:sudo)
            _try_sudo = sudo
            options[:via] = :sudo
          else
            _try_sudo = ""
          end
          digest_method = options.fetch(:digest, :md5).to_s
          digest_cmd = options.fetch(:digest_cmd, "#{digest_method.downcase}sum")
          install(from, to, options) do |from, to|
            execute = []
            execute << %{( test -d #{File.dirname(to).dump} || #{_try_sudo} mkdir -p #{File.dirname(to).dump} )}
            # calculate hexdigest of `from'
            execute << %{from=$(#{digest_cmd} #{from.dump} 2>/dev/null | #{DIGEST_FILTER_CMD} || true)}
            execute << %{echo %s} % ["#{digest_method.upcase}(#{from}) = ${from}".dump]
            # calculate hexdigest of `to'
            execute << %{to=$(#{digest_cmd} #{to.dump} 2>/dev/null | #{DIGEST_FILTER_CMD} || true)}
            execute << %{echo %s} % ["#{digest_method.upcase}(#{to}) = ${to}".dump]
            # check the hexdigests
            execute << (<<-EOS).gsub(/\s+/, " ").strip
              if [ -n "${from}" -a "${to}" ] && [ "${from}" = "${to}" ]; then
                echo "skip installing since no changes.";
              else
                #{_try_sudo} mv -f #{from.dump} #{to.dump};
              fi
            EOS
            execute.join(" && ")
          end
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
