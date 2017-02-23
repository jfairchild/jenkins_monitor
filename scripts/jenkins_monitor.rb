#!/usr/bin/env ruby

require 'jenkins_api_client'
require 'colorize'

class JenkinsMonitor
  CLIENT_FILE = '~/.jenkins_api_client/login.yml'
  QUEUE_WAIT_MAX_SECONDS = 600 # 10 minutes
  IGNORED_JOBS = %w(example).freeze
  IGNORED_NODES = %w(example).freeze
  ALLOWED_BLOCKING_REASONS = [/\ABuild #\d[\d,]+ is already in progress/,
    /\AUpstream project [A-Za-z0-9_\-]+ is already building.\z/,
    /\ABlocking job [A-Za-z0-9_\-]+ is running.\z/].freeze

  def self.go
    monitor = JenkinsMonitor.new
    monitor.delete_offline_slaves
    monitor.check_queued_jobs
  end

  def self.check_for_running_slave(node_name)
    monitor = JenkinsMonitor.new
    node_names = monitor.client.node.list(node_name)

    raise "No available running nodes with name like: #{node_name}" unless monitor.has_available_executors(node_names)
  end

  def initialize
    client_opts = Hash[YAML.load_file(File.expand_path(CLIENT_FILE)).map { |(k, v)| [k.to_sym, v] }]
    self.client = JenkinsApi::Client.new(client_opts)
  end

  attr_accessor :client

  def print_now(msg)
    STDERR.puts "[#{Time.now}] #{msg.red}"
  end

  def print_info(msg)
    STDERR.puts "[#{Time.now}] #{msg.green}"
  end

  def need_more_nodes?(blocking_reason)
    more_nodes_required = false
    match = /\AWaiting for next available executor on ([a-z_]+)/.match(blocking_reason)
    unless match.nil? || match[1].nil?
      more_nodes_required = true unless client.api_get_request("/label/#{match[1]}")['nodes'].nil?
      launch_node(match[1]) if ENV['LAUNCH_NODES']
    end
    more_nodes_required
  end

  def launch_node(node_label)
    print_info "launching node for label: #{node_label}"
    nodes = client.api_get_request("/label/#{node_label}")['nodes']
    unless nodes.nil? || nodes.empty?
      node = nodes[0]['nodeName'].split(' ')[0]
      client.api_post_request('/cloud/ec2-us-east-1/provision', { template: node }) {|res|
        print_info "CODE [#{res}] MESSAGE: [#{res.message}]"
        print_info(res.body) if res.body_permitted?
      }
    end
  end

  def check_queued_jobs
    queued_jobs = client.queue.list
    print_info 'No queued jobs.' if queued_jobs.empty?
    queued_jobs.each do |job|
      next if IGNORED_JOBS.any? { |ignored| job =~ /\A#{ignored}*/ }
      enqueued_time = client.queue.get_age(job) || 0
      print_info "#{job} Queued for #{(enqueued_time/60).round(1)} minutes"
      print_info "#{job} is blocked? #{client.queue.is_blocked?(job)} is buildable? #{client.queue.is_buildable?(job)}"
      print_now 'Possible problem building. Check slaves.' if client.queue.is_buildable?(job)
      blocking_reason = client.queue.get_reason(job)
      print_info "#{job}: #{blocking_reason}"

      next if ALLOWED_BLOCKING_REASONS.any? { |reason| blocking_reason =~ reason }

      next if need_more_nodes?(blocking_reason)

      raise "Investigate #{job}. Enqueued for #{(enqueued_time/60).round(2)} minutes" if client.queue.is_buildable?(job) && enqueued_time > QUEUE_WAIT_MAX_SECONDS
    end
  end

  def has_available_executors(node_names)
    node_names.each do |node|
      begin
        return true if client.node.get_node_numExecutors(node) > 0
      rescue TypeError
        next
      end
    end
    false
  end

  def is_offline_after_waiting?(node)
    wait = 2
    (1..7).each do
      print_info "#{node} is #{client.node.is_offline?(node) ? 'offline' : 'online'}"
      sleep(wait+=wait)
      return client.node.is_offline?(node) unless client.node.is_offline?(node)
    end
    print_now "#{node} is #{client.node.is_offline?(node) ? 'offline' : 'online'}"
    print_now "#{node} offline cause: #{client.node.get_node_offlineCause(node)}"
    client.node.is_offline?(node)
  end

  def delete_offline_slaves
    offline_nodes = client.node.list.select do |node|
      client.node.is_offline?(node) && !IGNORED_NODES.include?(node)
    end

    offline_nodes.empty? ? print_info('No offline nodes.') : print_now("#{offline_nodes.count} offline node(s)")

    offline_nodes.select do |node|
      print_now "[#{node}] Offline cause: [#{client.node.get_node_offlineCause(node)}]"
      print_now "[#{node}] get_node_monitorData #{client.node.get_node_monitorData(node)}"
      print_now "[#{node}] get_node_oneOffExecutors #{client.node.get_node_oneOffExecutors(node)}"
      print_now "[#{node}] get_node_numExecutors #{client.node.get_node_numExecutors(node)}"

      client.node.delete(node) if is_offline_after_waiting?(node) && client.node.get_node_offlineCause(node).nil?
    end
  end
end

if __FILE__ == $0
  puts ARGV[0]
  JenkinsMonitor.go if ARGV[0].nil?
  JenkinsMonitor.check_for_running_slave(ARGV[0]) unless ARGV[0].nil?
end
