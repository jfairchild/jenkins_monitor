#!/usr/bin/env ruby
$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__) + '/../lib'))
require_relative '../lib/jenkins_api_client'
require_relative '../lib/jenkins_api_client/node'
require 'colorize'

class JenkinsMonitor
  CLIENT_FILE= '~/.jenkins_api_client/login.yml'
  QUEUE_WAIT_MAX_SECONDS = 1200 # 20 minutes
  SLAVE_WAIT_MAX = 1200 # 20 minutes

  def self.go
    monitor = JenkinsMonitor.new
    monitor.check_queued_jobs
    delete_slaves = monitor.check_slave_status
    delete_slaves.each { |slave| print_now "#{slave} should be deleted..." }

    raise "There are #{delete_slaves.count} slaves to delete." if delete_slaves.count > 1
    raise "There's one slave to delete." if delete_slaves.count == 1
  end

  def initialize
    client_opts = Hash[YAML.load_file(File.expand_path(CLIENT_FILE)).map { |(k, v)| [k.to_sym, v] }]
    self.client = JenkinsApi::Client.new(client_opts)
  end

  attr_accessor :client

  def print_now(msg)
    STDERR.puts "[#{Time.now}] #{msg.red}"
  end

  def check_queued_jobs
    client.queue.list.each { |job| p(client.queue.get_age(job)) }

  end

  def check_slave_status
    offline_nodes = client.node.list.select do |node|
      client.node.is_offline?(node)
    end

    print_now "#{offline_nodes.count} offline nodes"
    offline_nodes.select do |node|
      print_now "Offline cause: #{client.node.get_node_offlineCause(node)}"
      config_xml = Nokogiri::XML(client.node.get_config(node)) { |config| config.noblanks }
      launch_time = config_xml.search('.//launchTime').children[0].text
      uptime = Time.now.utc - Time.parse(launch_time)
      uptime > SLAVE_WAIT_MAX
    end
  end
end

if __FILE__ == $0
  JenkinsMonitor.go
end
