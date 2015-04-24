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

      opts.on('-d', '--dns', 'Override boot2docker DNS config to force use of Red Hat DNS servers') do |d|
        Kernel.system('boot2docker', 'up')
        Kernel.system('boot2docker', 'ssh', "echo $'EXTRA_ARGS=\"--dns=10.5.30.160 --dns=10.11.5.19 --dns=8.8.8.8\"' | sudo tee -a /var/lib/boot2docker/profile && sudo /etc/init.d/docker restart")
        exit 0
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
  Kernel.system *['docker', cmd.to_s, *args]
end

def options_selected? options
  (options[:build] || options[:restart] || options[:awestruct][:gen] || options[:awestruct][:preview])
end

def block_wait_drupal_started
  docker_drupal = Docker::Container.get('docker_drupal_1')
  until docker_drupal.info['NetworkSettings']['Ports']
    sleep(5)
    docker_drupal = Docker::Container.get('docker_drupal_1')
  end

  # Check to see if Drupal is accepting connections before continuing
  puts 'Waiting to proceed until Drupal is up'
  drupal_port80_info = docker_drupal.info['NetworkSettings']['Ports']['80/tcp'].first
  drupal_ip = drupal_port80_info['HostIp']
  drupal_port = drupal_port80_info['HostPort']
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
end

def startup_services
  execute_docker_compose :up, %w(-d elasticsearch mysql drupalmysql drupal searchisko searchiskoconfigure)

  configure_service = Docker::Container.get('docker_searchiskoconfigure_1')

  puts 'Waiting to proceed until Drupal is up and searchiskoconfigure has completed'
  # searchiskoconfigure takes a while, we need to wait to proceed
  while configure_service.info['State']['Running']
    sleep 5
    configure_service = Docker::Container.get('docker_searchiskoconfigure_1')
  end

  puts 'searchiskoconfigure done, waiting for drupal'

  # Check to see if Drupal is accepting connections before continuing
  block_wait_drupal_started

  #execute_docker_compose :run, ['--no-deps', 'awestruct', 'rake clean preview[docker]']
  execute_docker_compose :run, ['--no-deps', '--rm','--service-ports', 'awestruct', 'rake bundle_update clean gen[docker]']
end

options = Options.parse ARGV

puts Options.parse %w(-h) unless options_selected? options

modify_env

Docker.url = options[:docker] if options[:docker]

if options[:build]
  docker_dir = 'awestruct'

  parent_gemfile = File.new '../Gemfile'
  parent_lock = File.new '../Gemfile.lock'
  docker_gemfile = File.new File.join(docker_dir, 'Gemfile')
  docker_lock = File.new File.join(docker_dir, 'Gemfile.lock')

  FileUtils.cp parent_gemfile, docker_dir unless Digest::MD5.file(parent_gemfile) == Digest::MD5.file(docker_gemfile)
  FileUtils.cp parent_lock, docker_dir unless Digest::MD5.file(parent_lock) == Digest::MD5.file(docker_lock)

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
  execute_docker_compose :run, ['--no-deps', 'awestruct', 'rake clean gen[docker]']
end

if options[:awestruct][:preview]
  execute_docker_compose :run, ['--no-deps', 'awestruct', 'rake clean preview[docker]']
end
