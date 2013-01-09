# Evenflow

Evenflow is a simple service for submitting sFlow datagrams to Graphite. It accepts sFlow datagrams from multiple network devices and proxies the data to a Carbon listener.

Currently only _Generic Interface Counters_ are supported. All other message types are discarded.

## Usage

```
$ CARBON_PREFIX=network CARBON_URL=carbon://localhost:2003 ruby evenflow.rb
```

## License 

Evenflow is distributed under the MIT license.

