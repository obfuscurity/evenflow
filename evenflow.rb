require 'rubygems'
require 'bundler'
require 'bundler/setup'

require 'em-sflow'
require 'snmp'
require 'socket'
require 'thread'
require 'uri'


EM.run do

  # connect to remote carbon socket
  begin
    carbon_url = URI.parse(ENV['CARBON_URL'])
  rescue
    raise "missing CARBON_URL, e.g. carbon://localhost:2003"
  end
  begin
    carbon = TCPSocket.new(carbon_url.host, carbon_url.port)
  rescue
    raise "unable to connect to CARBON_URL at #{carbon_url}"
  end

  # see if we have a custom metrics prefix
  carbon_prefix = ENV['CARBON_PREFIX'] || nil
  evenflow_prefix = ENV['EVENFLOW_PREFIX'] || 'evenflow'
  force_domain = ENV['FORCE_DOMAIN'] || nil

  # SNMP community for looking up ifDescr values
  snmp_community = ENV['SNMP_COMMUNITY'] || false
  IF_MIB_IFDESCR = '1.3.6.1.2.1.2.2.1.2.'

  # prep our DNS in-memory cache and resolver
  dns_cache = {}
  resolver = Resolv::DNS.new

  # prep our interface description cache
  interfaces = {}

  # listen for sflow datagrams
  collector = EventMachine::SFlow::Collector.new(:host => '0.0.0.0')

  # start our internal metrics timer
  total_metrics = 0
  stats_interval = ENV['STATS_INTERVAL'] || 60
  EM::add_periodic_timer stats_interval do
    carbon.puts "#{evenflow_prefix}.metrics #{total_metrics} #{Time.now.to_i}"
    total_metrics = 0
  end

  wanted_metrics = {
    :if_in_ucast_pkts => true,
    :if_in_mcast_pkts => true,
    :if_in_bcast_pkts => true,
    :if_in_discards => true,
    :if_in_errors => true,
    :if_in_octets => true,
    :if_in_unknown_protocols => true,
    :if_out_ucast_pkts => true,
    :if_out_mcast_pkts => true,
    :if_out_bcast_pkts => true,
    :if_out_discards => true,
    :if_out_errors => true,
    :if_out_octets => true,
    :if_index => false,
    :if_type => false,
    :if_direction => false,
    :if_admin_status => false,
    :if_oper_status => false,
    :if_promiscuous => false,
  }

  collector.on_sflow do |pkt|
    op = proc do
      unless dns_cache[pkt.agent.to_s]
        begin
          hostname = resolver.getname(pkt.agent.to_s).to_s
        rescue Resolv::ResolvError
          next
        end
        hostname.gsub!(/([^.]*)\..*/, "\\1.#{force_domain}") if force_domain
        dns_cache[pkt.agent.to_s] = hostname
      end

      if snmp_community && !interfaces[pkt.agent.to_s]
        mutex = Mutex.new
        mutex.synchronize do
          interfaces[pkt.agent.to_s] = {}
          snmp_hostname = dns_cache[pkt.agent.to_s]

          SNMP::Manager.open(:host => snmp_hostname, :community => snmp_community) do |mgr|
            begin
              mgr.walk(IF_MIB_IFDESCR) do |row|
                row.each do |record|
                  port = record.name.last.to_s
                  name = record.value.to_s.downcase.gsub('/', '_')
                  interfaces[pkt.agent.to_s][port] = name
                end
              end
            rescue
              # nil out interfaces[pkt.agent.to_s] so we try again
              interfaces[pkt.agent.to_s] = nil
            end
          end
        end
      end

      dns_cache[pkt.agent.to_s]
    end
    cb = proc do |agent|
      hostname = agent.to_s.gsub!('.', '_')

      pkt.samples.each do |sample|
        sample.records.each do |record|
          if record.is_a? EM::SFlow::GenericInterfaceCounters
            record.public_methods.each do |metric|
              if wanted_metrics[metric.to_sym]
                total_metrics += 1
                if dns_cache.include? pkt.agent.to_s
                  interface_name = interfaces[pkt.agent.to_s][record.if_index.to_s] || record.if_index.to_s

                  if snmp_community && !interfaces[pkt.agent.to_s][record.if_index.to_s]
                    puts "unable to find interface name for #{pkt.agent.to_s} / #{record.if_index.to_s}"
                    next
                  end

                  carbon.puts "#{carbon_prefix}.#{dns_cache[pkt.agent.to_s]}.interfaces.#{interface_name}.#{metric} #{record.method(metric).call} #{Time.now.to_i}"
                  puts "#{carbon_prefix}.#{dns_cache[pkt.agent.to_s]}.interfaces.#{interface_name}.#{metric} #{record.method(metric).call} #{Time.now.to_i}" if ENV['VERBOSE'].to_i.eql?(1)
                end
              end
            end
          end
        end
      end
    end
    EM.defer op, cb
  end
end
