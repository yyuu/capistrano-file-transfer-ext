set :application, "capistrano-file-transfer-ext"
set :repository,  "."
set :deploy_to do
  File.join("/home", user, application)
end
set :deploy_via, :copy
set :scm, :none
set :use_sudo, false
set :user, "vagrant"
set :password, "vagrant"
set :ssh_options, {:user_known_hosts_file => "/dev/null"}

role :web, "192.168.33.10"
role :app, "192.168.33.10"
role :db,  "192.168.33.10", :primary => true

$LOAD_PATH.push(File.expand_path("../../lib", File.dirname(__FILE__)))
require "capistrano/configuration/actions/file_transfer_ext"
require "stringio"

task(:test_all) {
  find_and_execute_task("test_default")
  find_and_execute_task("test_transfer_if_modified")
  find_and_execute_task("test_install")
  find_and_execute_task("test_install_if_modified")
}

def _invoke_command(cmdline, options={})
  via = options.delete(:via)
  if via == :run_locally
    run_locally(cmdline)
  else
    invoke_command(cmdline, options.merge(:via => via))
  end
end

def assert_timestamp_equals(x, y, options={})
  begin
    _invoke_command("test \! #{x.dump} -nt #{y.dump} -a \! #{x.dump} -ot #{y.dump}", options)
  rescue
    logger.debug("assert_timestamp_equals(#{x}, #{y}) failed.")
    _invoke_command("ls -l #{x.dump} #{y.dump}", options)
    raise
  end
end

def assert_timestamp_not_equals(x, y, options={})
  begin
    _invoke_command("test #{x.dump} -nt #{y.dump} -o #{x.dump} -ot #{y.dump}", options)
  rescue
    logger.debug("assert_timestamp_not_equals(#{x}, #{y}) failed.")
    _invoke_command("ls -l #{x.dump} #{y.dump}", options)
    raise
  end
end

def assert_file_equals(x, y, options={})
  begin
    _invoke_command("cmp #{x.dump} #{y.dump}", options)
  rescue
    logger.debug("assert_file_equals(#{x}, #{y}) failed.")
    _invoke_command("ls -l #{x.dump} #{y.dump}", options)
    raise
  end
end

def assert_file_mode_equals(x, y, options={})
  begin
    _invoke_command("test $(ls -l #{x.dump} | cut -d ' ' -f 1) = $(ls -l #{y.dump} | cut -d ' ' -f 1)", options)
  rescue
    logger.debug("assert_file_mode_equals(#{x}, #{y}) failed.")
    _invoke_command("ls -l #{x.dump} #{y.dump}", options)
    raise
  end
end

def assert_file_mode(mode, file, options={})
  mode = mode.to_i(8) if mode.is_a?(String)
  smode = "%c%c%c%c%c%c%c%c%c%c" % [
    ?-,
    mode & 0400 == 0 ? ?- : ?r, mode & 0200 == 0 ? ?- : ?w, mode & 0100 == 0 ? ?- : ?x,
    mode & 0040 == 0 ? ?- : ?r, mode & 0020 == 0 ? ?- : ?w, mode & 0010 == 0 ? ?- : ?x,
    mode & 0004 == 0 ? ?- : ?r, mode & 0002 == 0 ? ?- : ?w, mode & 0001 == 0 ? ?- : ?x,
  ]
  begin
    _invoke_command("test #{smode.dump} = $(ls -l #{file.dump} | cut -d ' ' -f 1)", options)
  rescue
    logger.debug("assert_file_mode(#{mode.to_s(8)}, #{file}) failed.")
    _invoke_command("ls -l #{file.dump}", options)
    raise
  end
end

def assert_file_owner(uid, file, options={})
  uid = uid.to_i
  # `stat -c` => GNU, `stat -f` => BSD
  begin
    _invoke_command("test #{uid} -eq $( stat -c '%u' #{file.dump} || stat -f '%u' #{file.dump} )", options)
  rescue
    logger.debug("assert_file_owner(#{uid}, #{file}) failed.")
    _invoke_command("ls -l #{file.dump}", options)
    raise
  end
end

def assert_file_group(gid, file, options={})
  gid = gid.to_i
  # `stat -c` => GNU, `stat -f` => BSD
  begin
    _invoke_command("test #{gid} -eq $( stat -c '%g' #{file.dump} || stat -f '%g' #{file.dump} )", options)
  rescue
    logger.debug("assert_file_group(#{gid}, #{file}) failed.")
    _invoke_command("ls -l #{file.dump}", options)
    raise
  end
end

namespace(:test_default) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_default", "test_default:setup"
  after "test_default", "test_default:teardown"

  task(:setup) {
    run_locally("mkdir -p tmp")
    run("mkdir -p tmp")
  }

  task(:teardown) {
    run_locally("rm -rf tmp")
    sudo("rm -rf tmp")
  }

  task(:test_safe_upload) {
    body = "foo"
    from = "tmp/foo"
    to = "tmp/rfoo"
    run_locally("rm -f #{from.dump}; echo #{body.dump} > #{from.dump}")
    run("rm -f #{to.dump}")
    safe_upload(from, to)
    run("test -f #{to.dump}")
    run("test #{body.dump} = $(cat #{to.dump})")
  }

  task(:test_safe_put) {
    body = "bar"
    to = "tmp/rbar"
    run("rm -f #{to.dump}")
    safe_put(body, to)
    run("test -f #{to.dump}")
    run("test #{body.dump} = $(cat #{to.dump})")
  }

  task(:test_safe_upload_directory) {
    files = %w(x y z)
    body = "baz"
    from = "tmp/baz"
    from_files = files.map { |x| File.join(from, x) }
    to = "tmp/rbaz"
    to_files = files.map { |x| File.join(to, x) }
    run_locally("rm -rf #{from.dump}; mkdir -p #{from.dump}")
    run_locally(from_files.map { |file| "echo #{body.dump} > #{file.dump}" }.join(" && "))
    run("rm -rf #{to.dump}")
    safe_upload(from, to)
    run(to_files.map { |file| "test -f #{file.dump}" }.join(" && "))
  }
}

namespace(:test_transfer_if_modified) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_transfer_if_modified", "test_transfer_if_modified:setup"
  after "test_transfer_if_modified", "test_transfer_if_modified:teardown"

  task(:setup) {
    run_locally("mkdir -p tmp")
    run("mkdir -p tmp")
  }

  task(:teardown) {
    run_locally("rm -rf tmp")
    sudo("rm -rf tmp")
  }

  def _test_transfer_if_modified_up(from, to, options={})
    run("rm -f #{to.dump}")
    transfer_if_modified(:up, from, to, options)
    if from.respond_to?(:read)
      pos = from.pos
      body = from.dup.read
      from.pos = pos
    else
      body = File.read(from)
    end
    tempbody = capture("mktemp tmp/body.XXXXXXXXXX").strip
    run("rm -f #{tempbody.dump}")
    put(body, tempbody)
    assert_file_equals(tempbody, to)

## should not transfer without changes
    2.times do
      sleep(1)
      tempto = capture("mktemp tmp/to.XXXXXXXXXX").strip
      run("rm -f #{tempto.dump}; cp -p #{to.dump} #{tempto.dump}")
      transfer_if_modified(:up, from, to, options) # re-transfer
      assert_file_equals(tempto, to)
      assert_timestamp_equals(tempto, to)
    end

## should transfer if `from' is changed
    tempfrom = run_locally("mktemp tmp/from.XXXXXXXXXX").strip
    tempto = capture("mktemp tmp/to.XXXXXXXXXX").strip
    File.write(tempfrom, body * 4)
    run("rm -f #{tempto.dump}; cp -p #{to.dump} #{tempto.dump}")
    transfer_if_modified(:up, tempfrom, to, options)
    run("test #{tempto.dump} -ot #{to.dump}") # check if `to' is overwritten
  end

  def _test_transfer_if_modified_down(from, to, options={})
    to = to.gsub(/\$CAPISTRANO:HOST\$/, "192.168.33.10")
    run_locally("rm -f #{to.dump}")
    transfer_if_modified(:down, from, to, options)
    tempbody = capture("mktemp tmp/body.XXXXXXXXXX").strip
    run_locally("rm -f #{tempbody.dump}")
    download(from, tempbody)
    assert_file_equals(tempbody, to, :via => :run_locally)

## should not transfer without changes
    2.times do
      sleep(1)
      tempto = capture("mktemp tmp/to.XXXXXXXXXX").strip
      run_locally("rm -f #{tempto.dump}; cp -p #{to.dump} #{tempto.dump}")
      transfer_if_modified(:down, from, to, options) # re-transfer
      assert_file_equals(tempto, to, :via => :run_locally)
      assert_timestamp_equals(tempto, to, :via => :run_locally)
    end

## should transfer if `from' is changed
    tempfrom = capture("mktemp tmp/from.XXXXXXXXXX").strip
    tempto = run_locally("mktemp tmp/to.XXXXXXXXXX").strip
    run("for i in 0 1 2 3; do cat #{from.dump} >> #{tempfrom.dump}; done")
    run_locally("rm -f #{tempto.dump}; cp -p #{to.dump} #{tempto.dump}")
    transfer_if_modified(:down, tempfrom, to, options)
    run_locally("test #{tempto.dump} -ot #{to.dump}") # check if `to' is overwritten
  end

  task(:test_transfer_if_modified_up) {
    run_locally("rm -f tmp/foo; echo foo > tmp/foo")
    _test_transfer_if_modified_up("tmp/foo", "tmp/rfoo")
  }

  task(:test_transfer_if_modified_up_with_stringio) {
    _test_transfer_if_modified_up(StringIO.new("bar"), "tmp/rbar", :digest => :sha1)
  }

  task(:test_transfer_if_modified_down) {
    run("rm -f tmp/foo; echo foo > tmp/foo")
    _test_transfer_if_modified_down("tmp/foo", "tmp/lfoo", :digest => :sha1)
  }

  task(:test_transfer_if_modified_down_with_capistrano_host) {
    run("rm -f tmp/bar; echo bar > tmp/bar")
    _test_transfer_if_modified_down("tmp/bar", "tmp/lbar_$CAPISTRANO:HOST$")
  }
}

def _test_install(frombody, tobody, options={})
  from = capture("mktemp tmp/from.XXXXXXXXXX").strip
  run("rm -f #{from.dump}")
  put(frombody, from)

  sleep(1)
  to = capture("mktemp tmp/to.XXXXXXXXXX").strip
  run("rm -f #{to.dump}")
  if tobody
    put(tobody, to)
    orig_mode = options.delete(:orig_mode)
    run("chmod #{orig_mode.to_s(8)} #{to.dump}") if orig_mode
    orig_owner = options.delete(:orig_owner)
    sudo("chown #{orig_owner} #{to.dump}") if orig_owner
    orig_group = options.delete(:orig_group)
    sudo("chgrp #{orig_group} #{to.dump}") if orig_group
  end

  tempfrom = capture("mktemp tmp/from2.XXXXXXXXXX").strip
  run("rm -f #{tempfrom.dump}; #{sudo} cp -p #{from.dump} #{tempfrom.dump}")

  tempto = capture("mktemp tmp/to2.XXXXXXXXXX").strip
  if tobody
    run("rm -f #{tempto.dump}; #{sudo} cp -p #{to.dump} #{tempto.dump}")
  else
    run("rm -f #{tempto.dump}")
  end

  method = ( options.delete(:install) || :always )
  send(method == :if_modified ? :install_if_modified : :install, from, to, options)
  yield(from, to, tempfrom, tempto)
end

namespace(:test_install) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_install", "test_install:setup"
  after "test_install", "test_install:teardown"

  task(:setup) {
    run_locally("mkdir -p tmp")
    run("mkdir -p tmp")
  }

  task(:teardown) {
    run_locally("rm -rf tmp")
    sudo("rm -rf tmp")
  }

  task(:test_if_not_modified) {
    _test_install("foo", "foo") do |from, to, tempfrom, tempto|
      assert_file_equals(tempto, to)
      assert_timestamp_equals(tempfrom, to)
      assert_timestamp_not_equals(tempto, to)
      assert_file_mode_equals(tempto, to)
    end
  }

  task(:test_if_modified) {
    _test_install("foo", "bar", :digest => :sha1) do |from, to, tempfrom, tempto|
      assert_file_equals(tempfrom, to)
      assert_timestamp_equals(tempfrom, to)
      assert_timestamp_not_equals(tempto, to)
      assert_file_mode_equals(tempto, to)
    end
  }

  task(:test_if_missing) {
    _test_install("baz", nil) do |from, to, tempfrom, tempto|
      assert_file_equals(tempfrom, to)
      assert_timestamp_equals(tempfrom, to)
    end
  }

  task(:test_with_mode) {
    _test_install("foo", "bar", :mode => 0755) do |from, to, tempfrom, tempto|
      assert_file_mode(0755, to)
    end
  }

  task(:test_via_sudo) {
    _test_install("bar", "baz", :orig_owner => 0, :via => :sudo) do |from, to, tempfrom, tempto|
      assert_file_owner(0, to)
    end
  }

  task(:test_with_mode_via_sudo) {
    _test_install("bar", "baz", :mode => 0644, :orig_owner => 0, :via => :sudo) do |from, to, tempfrom, tempto|
      assert_file_mode(0644, to)
      assert_file_owner(0, to)
    end
  }

  task(:test_preserve_original_mode) {
    _test_install("foo", "bar", :orig_mode => 0600) do |from, to, tempfrom, tempto|
      assert_file_mode(0600, to)
    end
  }

  task(:test_ignore_original_mode) {
    _test_install("foo", "bar", :orig_mode => 0400, :mode => 0700) do |from, to, tempfrom, tempto|
      assert_file_mode(0700, to)
    end
  }

  task(:test_preserve_original_owner_group_mode) {
    _test_install("foo", "bar", :orig_owner => 0, :orig_group => 0, :orig_mode => 0640, :via => :sudo) do |from, to, tempfrom, tempto|
      assert_file_mode(0640, to)
      assert_file_owner(0, to)
      assert_file_group(0, to)
    end
  }

  task(:test_ignore_original_owner_group_mode) {
    _test_install("bar", "baz", :owner => 0, :group => 0, :mode => 0640, :via => :sudo) do |from, to, tempfrom, tempto|
      assert_file_mode(0640, to)
      assert_file_owner(0, to)
      assert_file_group(0, to)
    end
  }
}

namespace(:test_install_if_modified) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_install_if_modified", "test_install_if_modified:setup"
  after "test_install_if_modified", "test_install_if_modified:teardown"

  task(:setup) {
    run_locally("mkdir -p tmp")
    run("mkdir -p tmp")
  }

  task(:teardown) {
    run_locally("rm -rf tmp")
    sudo("rm -rf tmp")
  }

  task(:test_if_not_modified) {
    _test_install("foo", "foo", :install => :if_modified) do |from, to, tempfrom, tempto|
      assert_file_equals(tempto, to)
      assert_timestamp_equals(tempto, to)
      assert_timestamp_not_equals(tempfrom, to)
      assert_file_mode_equals(tempto, to)
    end
  }

  task(:test_if_modified) {
    _test_install("foo", "bar", :install => :if_modified, :digest => :sha1) do |from, to, tempfrom, tempto|
      assert_file_equals(tempfrom, to)
      assert_timestamp_equals(tempfrom, to)
      assert_timestamp_not_equals(tempto, to)
      assert_file_mode_equals(tempto, to)
    end
  }

  task(:test_if_missing) {
    _test_install("baz", nil, :install => :if_modified) do |from, to, tempfrom, tempto|
      assert_file_equals(tempfrom, to)
      assert_timestamp_equals(tempfrom, to)
    end
  }

  task(:test_with_mode) {
    _test_install("foo", "bar", :install => :if_modified, :mode => 0755) do |from, to, tempfrom, tempto|
      assert_file_mode(0755, to)
    end
  }

  task(:test_via_sudo) {
    _test_install("bar", "baz", :install => :if_modified, :orig_owner => 0, :via => :sudo) do |from, to, tempfrom, tempto|
      assert_file_owner(0, to)
    end
  }

  task(:test_with_mode_via_sudo) {
    _test_install("bar", "baz", :install => :if_modified, :orig_owner => 0, :mode => 0644, :via => :sudo) do |from, to, tempfrom, tempto|
      assert_file_mode(0644, to)
      assert_file_owner(0, to)
    end
  }

  task(:test_preserve_original_mode) {
    _test_install("foo", "bar", :install => :if_modified, :orig_mode => 0600) do |from, to, tempfrom, tempto|
      assert_file_mode(0600, to)
    end
  }

  task(:test_ignore_original_mode) {
    _test_install("foo", "bar", :install => :if_modified, :orig_mode => 0400, :mode => 0700) do |from, to, tempfrom, tempto|
      assert_file_mode(0700, to)
    end
  }

  task(:test_preserve_original_owner_group_mode) {
    _test_install("foo", "bar", :install => :if_modified, :orig_owner => 0, :orig_group => 0, :orig_mode => 0640, :via => :sudo) do |from, to, tempfrom, tempto|
      assert_file_mode(0640, to)
      assert_file_owner(0, to)
      assert_file_group(0, to)
    end
  }

  task(:test_ignore_original_owner_group_mode) {
    _test_install("bar", "baz", :install => :if_modified, :owner => 0, :group => 0, :mode => 0640, :via => :sudo) do |from, to, tempfrom, tempto|
      assert_file_mode(0640, to)
      assert_file_owner(0, to)
      assert_file_group(0, to)
    end
  }
}

# vim:set ft=ruby sw=2 ts=2 :
