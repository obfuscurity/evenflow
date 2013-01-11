
require 'em-sflow'
require 'socket'
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

  # prep our DNS in-memory cache and resolver
  dns_cache = {}
  resolver = Resolv::DNS.new

  # listen for sflow datagrams
  collector = EventMachine::SFlow::Collector.new(:host => '0.0.0.0')

  # start our internal metrics timer
  total_metrics = 0
  EM::add_periodic_timer 5.0 do
    puts "number of metrics: #{total_metrics}"
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
    op = proc { resolver.getname(pkt.agent.to_s) unless dns_cache[pkt.agent.to_s] }
    cb = proc do |agent|
      dns_cache[pkt.agent.to_s] ||= agent.to_s.gsub('.', '_')
      pkt.samples.each do |sample|
        sample.records.each do |record|
          if record.is_a? EM::SFlow::GenericInterfaceCounters
            record.public_methods.each do |metric|
              if wanted_metrics[metric]
                total_metrics++
                carbon.puts "#{carbon_prefix}.#{dns_cache[pkt.agent.to_s]}.interfaces.#{record.if_index}.#{metric} #{record.method(metric).call} #{Time.now.to_i}"
                puts "#{carbon_prefix}.#{dns_cache[pkt.agent.to_s]}.interfaces.#{record.if_index}.#{metric} #{record.method(metric).call} #{Time.now.to_i}" if ENV['VERBOSE'].to_i.eql?(1)
              end
            end
          end
        end
      end
    end
    EM.defer op, cb
  end
end
