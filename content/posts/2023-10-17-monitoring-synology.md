+++
title = 'Monitoring Synology NAS with Prometheus & SNMP'
date = 2023-10-17
featured_image="/images/2023-10-17-monitoring-synology/grafana-dashboard.png"
draft = false
toc = true
tags = ["metrics", "k3s", "prometheus", "grafana", "synology", "snmp"]
+++

My Synology NAS is a very important part of my [home network](https://colby.gg/posts/2023-09-29-network-overview/), and until recently it was practically unmonitored. Synology doesn't make it easy to monitor their NAS devices out of the box. It's possible to get Prometheus' node exporter running, but that doesn't export all of the metrics of interest and is generally a pain to deal with. I also prefer to minimize the number of things running on my NAS. It's under enough load as is.

So what to do? Synology exposes metrics over SNMP. Prometheus has a handy [snmp exporter](https://github.com/prometheus/snmp_exporter/). It's a bit of a pain to get setup, but it does get metrics into my preferred monitoring solution.

## Requirements & Goals

1. Get Synology metrics into Prometheus.
2. Setup Dashboards in Grafana.
3. Setup alerting for the NAS.
4. Fully automated - no manual actions.
5. Secure - everything should be encrypted, and no plaintext password storage.

## NAS Configuration

First the NAS must be configured to enable SNMP. In the WebUI `Control Panel` -> `Terminal & SNMP` -> `SNMP`, enable SNMP and configure SNMPv3. SNMPv1 and SNMPv2 are not secure and should not be used.

[![synology config](/images/2023-10-17-monitoring-synology/synology-config.png)](/images/2023-10-17-monitoring-synology/synology-config.png)

SHA is better than MD5, and AES is better than DES.

## Generate snmp_exporter config

The snmp_exporter config must be generated, default configuration will not work.

1. Clone [snmp exporter](https://github.com/prometheus/snmp_exporter/).
2. Checkout the version you intend to deploy. Unreleased versions may not work. You can see the releases on GitHub and then can checkout the Tag. The latest release at the time of writing is `v0.24.1`.

    ```bash
    git checkout tags/v0.24.1
    ```

3. Follow the instructions in the README in `generator/README.md` of the repository.
4. Download the synology mibs. There is a link on the page where the NAS SNMP was enabled. Place the mibs in `generator/mibs`.
5. Edit generator.yml. Most of the defaults are not relevant and can be deleted. For the initial version, I've taken the default synology config in the generator.yml and removed almost everything else. This is my initial redacted version, important alterations are at the very top:

    ```yaml
    ---
    auths:
      synology: # <-- this section is added: This name is important later
        version: 3
        username: THE_CONFIGURED_USERNAME 
        security_level: authPriv
        password: THE_CONFIGURED_PASSWORD
        auth_protocol: SHA
        priv_protocol: AES
        priv_password: THE_CONFIGURED_PRIV_PASSWORD
    
    modules:
      # Default IF-MIB interfaces table with ifIndex.
      if_mib:
        walk: [sysUpTime, interfaces, ifXTable]
        lookups:
          - source_indexes: [ifIndex]
            lookup: ifAlias
          - source_indexes: [ifIndex]
            # Uis OID to avoid conflict with PaloAlto PAN-COMMON-MIB.
            lookup: 1.3.6.1.2.1.2.2.1.2 # ifDescr
          - source_indexes: [ifIndex]
            # Use OID to avoid conflict with Netscaler NS-ROOT-MIB.
            lookup: 1.3.6.1.2.1.31.1.1.1.1 # ifName
        overrides:
          ifAlias:
            ignore: true # Lookup metric
          ifDescr:
            ignore: true # Lookup metric
          ifName:
            ignore: true # Lookup metric
          ifType:
            type: EnumAsInfo
      # Default IP-MIB with ipv4InterfaceTable for example.
      ip_mib:
        walk: [ipv4InterfaceTable]
    
      synology:
        walk:
          - laNames
          - laLoadInt
          - ssCpuUser
          - ssCpuSystem
          - ssCpuIdle
          - memory
          - hrStorage
          - 1.3.6.1.4.1.6574.1       # synoSystem
          - 1.3.6.1.4.1.6574.2       # synoDisk
          - 1.3.6.1.4.1.6574.3       # synoRaid
          - 1.3.6.1.4.1.6574.4       # synoUPS
          - 1.3.6.1.4.1.6574.5       # synologyDiskSMART
          - 1.3.6.1.4.1.6574.6       # synologyService
          - 1.3.6.1.4.1.6574.101     # storageIO
          - 1.3.6.1.4.1.6574.102     # spaceIO
          - 1.3.6.1.4.1.6574.104     # synologyiSCSILUN
        lookups:
          - source_indexes: [spaceIOIndex]
            lookup: spaceIODevice
            drop_source_indexes: true
          - source_indexes: [storageIOIndex]
            lookup: storageIODevice
            drop_source_indexes: true
          - source_indexes: [serviceInfoIndex]
            lookup: serviceName
            drop_source_indexes: true
          - source_indexes: [diskIndex]
            lookup: diskID
            drop_source_indexes: true
          - source_indexes: [raidIndex]
            lookup: raidName
            drop_source_indexes: true
          - source_indexes: [laIndex]
            lookup: laNames
            drop_source_indexes: true
          - source_indexes: [hrStorageIndex]
            lookup: hrStorageDescr
            drop_source_indexes: true
        overrides:
          diskModel:
            type: DisplayString
          diskSMARTAttrName:
            type: DisplayString
          diskSMARTAttrStatus:
            type: DisplayString
          diskSMARTInfoDevName:
            type: DisplayString
          diskType:
            type: DisplayString
          modelName:
            type: DisplayString
          raidFreeSize:
            type: gauge
          raidName:
            type: DisplayString
          raidTotalSize:
            type: gauge
          serialNumber:
            type: DisplayString
          serviceName:
            type: DisplayString
          version:
            type: DisplayString
    ```

6. Generate the snmp.yml file

    ```bash
    make generate
    ```

7. Verify the snmp.yml file is correct. Download the appropriate snmp exporter binary from the [releases](https://github.com/prometheus/snmp_exporter/releases). Copy the snmp.yml file into the directory with the binary. Run the following commands to verify.

    From terminal 1:

    ```bash terminal 1
    ./snmp_exporter
    ```

    From terminal 2:

    ```bash terminal 2
    curl 'http://localhost:9116/snmp?target=<SYNOLOGY_NAS_IP_HERE>&auth=synology&module=if_mib'
    curl 'http://localhost:9116/snmp?target=<SYNOLOGY_NAS_IP_HERE>&auth=synology&module=synology'
    ```

    Both curl commands should spit out a long list of metrics.

## Install snmp_exporter and snmp.yml

Choose the host you want to have polling your NAS for metrics and install the snmp_exporter and the generated snmp.yml file. There are instructions for this in the snmp_exporter git repo.

I've written [another post](https://colby.gg/posts/2023-10-18-deploying-snmp-exporter/) on how I deploy snmp_exporter with Ansible.

## Update Prometheus config to scrape snmp

My Prometheus is configured via helm, [details here](https://colby.gg/posts/2023-09-30-metrics/). Update the extraScapeConfigs in values.yml with configs for snmp.

```yaml
extraScrapeConfigs: |
   # Other jobs removed for brevity
   - job_name: 'snmp'
     static_configs:
       - targets:
         - NAS_IP_OR_HOSTNAME_HERE # <-- important to modify
     metrics_path: /snmp
     params:
       auth: [synology]
       module: [if_mib, synology]
     relabel_configs:
       - source_labels: [__address__]
         target_label: __param_target
       - source_labels: [__param_target]
         target_label: instance
       - target_label: __address__
         replacement: IP_OF_HOST_WITH_SNMP_EXPORTER_HERE:9116  # <--- important to modify

   # Global exporter-level metrics
   - job_name: 'snmp_exporter'
     static_configs:
       - targets: ['HOSTNAME_OF_HOST_WITH_SNMP_EXPORTER_HERE:9116'] # <--- important to modify
```

For verification I also enabled ingress to Prometheus temporarily. This was very helpful for debugging a few silly typos. On the Prometheus WebUI go to `status` -> `targets` and find the SNMP.

[![prometheus snmp](/images/2023-10-17-monitoring-synology/prometheus-targets.png)](/images/2023-10-17-monitoring-synology/prometheus-targets.png)

Don't forget to disable the ingress when done.

## Create Dashboards and Alerts in Grafana

This [dashboard](https://grafana.com/grafana/dashboards/13516-synology-snmp-dashboard/) is an excellent place to start. Congratulations, you have monitoring for your NAS!

[![prometheus snmp](/images/2023-10-17-monitoring-synology/grafana-dashboard.png)](/images/2023-10-17-monitoring-synology/grafana-dashboard.png)

As you can see, there were immediate action items when I first brought up the dashboard. My NAS had been running rather warm, and the fans were set to quiet mode. Thanks to the monitoring, that was an easy fix before it became an issue.

An improved dashboard that requires some modification is [here](https://grafana.com/grafana/dashboards/13516-synology-snmp-dashboard/). Several changes are required:

1. Alter the job query param in every graph to match the job used (snmp in this article).
2. Alter the interface variable in the dashboard. The default query does not work for me:

[![interface query](/images/2023-10-17-monitoring-synology/improved-dash-interface.png)](/images/2023-10-17-monitoring-synology/improved-dash-interface.png)

Final results:

[![interface query](/images/2023-10-17-monitoring-synology/final-results.png)](/images/2023-10-17-monitoring-synology/final-results.png)

## Conclusion

Prometheus is now configured to pull SNMP metrics from the NAS, dashboards and alerts are now configured. I'm leaving the alerting config as an exercise for the reader.
