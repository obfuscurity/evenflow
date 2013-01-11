# Evenflow

Evenflow is a simple service for submitting sFlow datagrams to Graphite. It accepts sFlow datagrams from multiple network devices and proxies the data to a Carbon listener.

Currently only _Generic Interface Counters_ are supported. All other message types are discarded.

## Usage

Starting up evenflow is very straightforward. It recognizes a few ENV options such as `CARBON_PREFIX`, `CARBON_URL`, `STATS_INTERVAL` and `VERBOSE`. Setting `STATS_INTERVAL=10` will cause evenflow to report internal statistics (`evenflow.metrics`) every 10 seconds (defaults to 60s). When `VERBOSE=1` it will print out each line to stderr that it also sends to the Carbon socket.

```
$ CARBON_PREFIX=network CARBON_URL=carbon://localhost:2003 ruby evenflow.rb
```

## License 

Evenflow is distributed under the MIT license.

