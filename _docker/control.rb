#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'
require 'tempfile'
require 'gpgme'
require 'yaml'
require 'digest'

class Options
  def self.parse(args)
    options = {:build => false, :restart => false, :awestruct => {:gen => false, :preview => false}}

    opts_parse = OptionParser.new do |opts|
      opts.banner = 'Usage: control.rb [options]'
      opts.separator 'Specific options:'

      opts.on('-r', '--restart', 'Restart the containers') do |r|
        options[:restart] = r
      end

      opts.on('-b', '--build', 'Build the containers') do |b|
        options[:build] = b
      end

      opts.on('-g', '--generate', 'Run awestruct (clean gen)') do |r|
        options[:awestruct][:gen] = true
      end

      opts.on('-p', '--preview', 'Run awestruct (clean preview)') do |r|
        options[:awestruct][:preview] = true
      end

      # No argument, shows at tail.  This will print an options summary.
      opts.on_tail('-h', '--help', 'Show this message') do
        puts opts
        exit
      end
    end

    opts_parse.parse! args
    options
  end
end

def modify_env
  begin
    crypto = GPGME::Crypto.new
    fname = File.open '../_config/secrets.yaml.gpg'

    secrets = YAML.load(crypto.decrypt(fname).to_s)
    secrets.each do |k, v|
      ENV[k] = v
    end
    puts 'Vault decrypted'
  rescue GPGME::Error => e
    puts "Unable to decrypt vault (#{e})"
  end
end

def execute_docker_compose(cmd, args = [])
  if cmd == :up
    Kernel.system 'docker-compose', 'up', '-d'
  else
    Kernel.system *['docker-compose', cmd.to_s, *args]
  end
end

def execute_docker(cmd, args = [])
  Kernel.system *['sudo', cmd.to_s, *args]
end

options = Options.parse ARGV

puts Options.parse %w(-h) unless options[:build] || options[:restart] || options[:awestruct][:gen] || options[:awestruct][:preview]

modify_env

if options[:build]
  FileUtils.cp '../Gemfile', 'ruby' unless Digest::MD5.file('../Gemfile') == Digest::MD5.file('ruby/Gemfile')
  FileUtils.cp '../Gemfile.lock', 'ruby' unless Digest::MD5.file('../Gemfile.lock') == Digest::MD5.file('ruby/Gemfile.lock')
  puts 'Building base docker image...'
  execute_docker(:build, ['-t developer.redhat.com/base', './base'])
  puts 'Building base Java docker image...'
  execute_docker(:build, ['-t developer.redhat.com/java', './java'])
  execute_docker_compose :build
end

if options[:restart]
  execute_docker_compose :kill
  execute_docker_compose :up
  execute_docker_compose :ps
end

if options[:awestruct][:gen]
  execute_docker_compose :run, %w(awestruct rake clean gen)
end

if options[:awestruct][:preview]
  execute_docker_compose :run, %w(awestruct rake clean preview)
end
