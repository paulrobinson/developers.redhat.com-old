#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'
require 'tempfile'
require 'gpgme'
require 'yaml'
require 'digest'
require 'docker'
require 'socket'
require 'timeout'

class Options
  def self.parse(args)
    options = {:build => false, :restart => false, :awestruct => {:gen => false, :preview => false}}

    opts_parse = OptionParser.new do |opts|
      opts.banner = 'Usage: control.rb [options]'
      opts.separator 'Specific options:'

      opts.on('-d', '--docker', 'Docker client connection info (i.e. tcp://example.com:1000)') do |d|
        options[:docker] = d
      end

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
  Kernel.system *['docker-compose', cmd.to_s, *args]
end

def execute_docker(cmd, args = [])
  Kernel.system *['sudo', cmd.to_s, *args]
end

def options_selected? options
  (options[:build] || options[:restart] || options[:awestruct][:gen] || options[:awestruct][:preview])
end

def startup_services
  execute_docker_compose :up, %w(-d elasticsearch mysql drupalmysql drupal searchisko searchiskoconfigure)

  configure_service = Docker::Container.get('docker_searchiskoconfigure_1')

  while configure_service.info['State']['Running']
    sleep 5
    configure_service = Docker::Container.get('docker_searchiskoconfigure_1')
  end

  # Check to see if Drupal is accepting connections before continuing
  puts 'Waiting to proceed until Drupal is up'
  drupal_ip = Docker::Container.get('docker_drupal_1').info["NetworkSettings"]["Ports"]["80/tcp"].first["HostIp"]
  drupal_port = Docker::Container.get('docker_drupal_1').info["NetworkSettings"]["Ports"]["80/tcp"].first["HostPort"]
  up = false
  until up
    begin
      Timeout::timeout(1) do
        begin
          s = TCPSocket.new(drupal_ip, drupal_port)
          s.close
          up = true
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
          # Doesn't matter, just means it's still down
          sleep 5
        end
      end
    rescue Timeout::Error
      # We don't really care about this
    end
  end

  execute_docker_compose :up, %q(-d --no-recreate awestruct)
end

options = Options.parse ARGV

puts Options.parse %w(-h) unless options_selected? options

modify_env

Docker.url = options[:docker] if options[:docker]

if options[:build]
  docker_dir = 'ruby'

  parent_gemfile = File.new '../Gemfile'
  parent_lock = File.new '../Gemfile.lock'
  docker_gemfile = File.new File.join(docker_dir, 'Gemfile')
  docker_lock = File.new File.join(docker_dir, 'Gemfile.lock')

  FileUtils.cp parent_gemfile, 'ruby' unless Digest::MD5.file(parent_gemfile) == Digest::MD5.file(docker_gemfile)
  FileUtils.cp parent_lock, 'ruby' unless Digest::MD5.file(parent_lock) == Digest::MD5.file(docker_lock)

  puts 'Building base docker image...'
  execute_docker(:build, ['-t developer.redhat.com/base', './base'])
  puts 'Building base Java docker image...'
  execute_docker(:build, ['-t developer.redhat.com/java', './java'])
  execute_docker_compose :build
end

if options[:restart]
  execute_docker_compose :kill
  startup_services
  execute_docker_compose :ps
end

if options[:awestruct][:gen]
  execute_docker_compose :run, %w(--no-deps awestruct rake clean gen)
end

if options[:awestruct][:preview]
  execute_docker_compose :run, %w(--no-deps awestruct rake clean preview)
end
