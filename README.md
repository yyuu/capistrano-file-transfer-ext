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

`file_transfer_ext` provides following additional file transfer actions. You can use them in your tasks.

  * `safe_put` - Store the contents of multiple servers, with comparing the difference of the contents.
  * `safe_upload` - Transfers a file from the local host to multiple remote hosts, with comparing the difference of the contents.

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
