# Capistrano::Configuration::Actions::FileTransferExt

A sort of utilities which helps you transferring files with Capistrano.

## Installation

Add this line to your application's Gemfile:

    gem 'capistrano-file-transfer-ext'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install capistrano-file-transfer-ext

## Usage

Add `require` line in your `Capfile` or `config/deploy.rb` or so.

    require "capistrano/configuration/actions/file_transfer_ext"

Now you can use them in your tasks.

* `safe_upload` - Transfers a file from the local host to multiple remote hosts. ([more...](#safe_upload))
* `safe_put` - Store the contents of multiple servers. ([more...](#safe_put))
* `transfer_if_modified` - Transfer files from/to remote servers only if they are different. ([more...](#transfer_if_modified))
* `install` - Install files on remote servers. ([more...](#install))
* `install_if_modified` - Install files on remote servers only if they are different. ([more...](#install_if_modified))

## Reference

### `safe_upload`

**Definition**

    safe_upload(from, to, options={}, &block)

**Module**

    Capistrano::Configuration::Actions::FileTransferExt

The `safe_upload` acts like almost as same as `upload`, but with some little enhancements.

1. overwrite remote file only if transmission has been successfully completed.
2. (if you request) overwrite remote file only if the checksums are different.

#### Arguments

**from**

Thie may be either a String, or an IO object (e.g. an open file handle, or a StringIO instance).

**to**

This must be a string indicating the path on the remote server that should be uploaded to.

**options**

All of the options of `upload` are sensible. In addition, there are some extra options.

* `:install` It must be either `:always` (the default), or `:if_modified`. If `:if_modified` is given, install the file only if the checksums are different.
* `:digest` This is a symbol indicating which algorithm should be used to calculate the checksum of files. `:md5` is default.
* `:digest_cmd` The command to calculate checksum of files. `md5sum` is default.
* `:via` `:run` by default.


### `safe_put`

**Definition**

    safe_put(data, to, options={})

**Module**

    Capistrano::Configuration::Actions::FileTransferExt

The `safe_put` action is `safe_upload`'s little brother.

#### Arguments

**data**

This is a string containing the contents of the file you want to upload.

**to**

This is a string naming the file on the remote server(s) that should be created (or overwritten) with the given data.

**options**

All of the options of `safe_upload` are sensible.


### `transfer_if_modified`

**Definition**

    transfer_if_modified(direction, from, to, options={}, &block)

**Module**

    Capistrano::Configuration::Actions::FileTransferExt

The `transfer_if_modified` action is `transfer`'s senior brother.
Transfer files from/to remote servers only if they are different.

#### Arguments

**direction**

The direction of transfer. `:up` or `:down` is sensible.

**from**

Source file.

**to**

Destination file.

**options**

All of the options of `transfer` are sensible. In addition, there are some extra options.

* `:digest` This is a symbol indicating which algorithm should be used to calculate the checksum of files. `:md5` is default.
* `:digest_cmd` The command to calculate checksum of files. `md5sum` is default.


### `install`

**Definition**

    install(from, to, options={}, &block)

**Module**

    Capistrano::Configuration::Actions::FileTransferExt

Install files on remote servers. This method acts just like `mv`.

#### Arguments

**from**

Source file on remote server.

**to**

Destination file on remote server.

**options**

* `:mode` The mode of destination file. If not given, preserve original mode of `to`.
* `:via` `:run` by default.


### `install_if_modified`

**Definition**

    install_if_modified(from, to, options={}, &block)

**Module**

    Capistrano::Configuration::Actions::FileTransferExt

The `install_if_modified` action is `install`'s senior brother.
Install files on remote servers only if they are different.

#### Arguments

**from**

Source file on remote server.

**to**

Destination file on remote server.

**options**

* `:mode` The mode of destination file. If not given, preserve original mode of `to`.
* `:via` `:run` by default.
* `:digest` This is a symbol indicating which algorithm should be used to calculate the checksum of files. `:md5` is default.
* `:digest_cmd` The command to calculate checksum of files. `md5sum` is default.


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Author

- YAMASHITA Yuu (https://github.com/yyuu)
- Geisha Tokyo Entertainment Inc. (http://www.geishatokyo.com/)

## License

MIT
