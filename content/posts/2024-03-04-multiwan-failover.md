+++
title = 'Multiwan Failover With OPNsense and an LTE modem'
date = 2024-03-04
featured_image="/images/2024-03-04-multiwan-failover/diagram.png"
tags = ["network", "failover", "opnsense", "home network", "HA", "multiwan"]
toc = true
draft = false
+++

## The Problem

Working remotely means my internet connection must be highly reliable. Losing internet during working hours means potentially losing income. Worse, I could be forced into an office. With an open floorplan. A fate truely worse than looking for a new job.

Murphy's law also implies any connection downtime will happen when the connection is needed most. This post is all about mitigating the risk of an ISP outage with a secondary connection over a separate medium. In my case it's my main ISP's connection and a 4G LTE modem backup.

This post describes the bare minimum configuration. A more advanced setup may be in a followup post.

Relevant OPNsense [documentation](https://docs.opnsense.org/manual/how-tos/multiwan.html).

## Requirements

[![diagram](/images/2024-03-04-multiwan-failover/diagram.png)](/images/2024-03-04-multiwan-failover/diagram.png)

- Traffic should flow through the main ISP connection exclusively unless there is an outage.
- If the main ISP has an outage, traffic should go through the backup connection.
- When service from the main ISP is restored, traffic should go through the main ISP connection.

## Hardware

This project needs a couple pieces of hardware to get going.

1. A router running OPNsense with at least 3 ethernet ports, or 2 ethernet ports and a USB port, or 2 ethernet and a free PCIe slot. All depending on your LTE modem and router combo.

2. An LTE modem. I went with [Protectli](https://protectli.com/lte/), but really any LTE modem should work just fine here.

## Setup The Modem

> WARNING: Do not disable DHCP on the modem. Your router will not get an IP address when the modem has DHCP disabled in modem mode.

1. Attach the antenna, insert the sim card, and power on the modem.

2. Connect an ethernet cable from your computer to the modem.

3. My modem was accessable at `192.168.123.254` with the default login of `admin`/`admin12345`. Your modem probably comes with a card containing login info. A factory restore will set the login to `admin/admin`

4. Change the login info. At minimum change the password.

5. Set the modem to modem mode `Setup -> Network -> Device Mode`.

    [![modem config](/images/2024-03-04-multiwan-failover/modem-config.png)](/images/2024-03-04-multiwan-failover/modem-config.png)

You can disconnect the modem from your computer now.

## Setup The Router

0. Backup your configuration. Seriously, why would you make changes without having a backup first?

1. Plug the ethernet cable from the modem into the router port you want to use for your backup WAN.

2. Set a monitor IP  and priority on your existing WAN interface. `System -> Gateways -> Configuration`. Edit the connection.

    [![existing WAN monitor ip](/images/2024-03-04-multiwan-failover/existing-wan-monitor-ip.png)](/images/2024-03-04-multiwan-failover/existing-wan-monitor-ip.png)

    A lower priority number means the gateway is more important. Your preferred gateway should have the lowest priority number here. Valid values are between 1 and 255. The default for my system was 254. A blank monitor IP defaults to using the next hop. Some next hops respond to ping, some do not.
    I set my existing ISP connection to a priority of 128 (default was 254) and to use the next hop.

    > WARNING: Be careful what you use for the monitor IP. Once you use a monitor IP, that IP will only be reachable through the interface that has the monitor IP. This can lead to poor behavior when the Gateway goes down.

3. I had to add the interface for the new LTE WAN. This step can be skipped if the interface exists. Go to `Interfaces` -> `Assignments` -> `Assign a new device`. Add the port you want to use for the Gateway. Don't forget to enable the interface.

4. Set DNS for each Gateway, and enable default gateway switching. `System -> Settings -> General`. These are the settings I chose.

    [![DNS](/images/2024-03-04-multiwan-failover/dns.png)](/images/2024-03-04-multiwan-failover/dns.png)

## Test Failover

One test method is to open a terminal, and start pinging something. Once ping is running, physically unplug the primary ISP connection.

Here's the output from my initial test:

```bash
$ ping youtube.com
PING youtube.com (142.251.46.206) 56(84) bytes of data.
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=1 ttl=58 time=4.08 ms
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=2 ttl=58 time=5.08 ms
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=3 ttl=58 time=5.25 ms
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=4 ttl=58 time=7.15 ms
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=5 ttl=58 time=6.44 ms
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=6 ttl=58 time=5.18 ms
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=7 ttl=58 time=7.53 ms
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=8 ttl=58 time=5.79 ms
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=9 ttl=58 time=5.23 ms
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=10 ttl=58 time=5.25 ms
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=11 ttl=58 time=5.46 ms
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=12 ttl=58 time=6.88 ms
< some output omitted>
From _gateway (10.0.3.1) icmp_seq=30 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=31 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=32 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=33 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=34 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=35 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=36 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=37 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=38 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=39 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=40 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=41 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=42 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=43 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=44 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=45 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=46 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=47 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=48 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=49 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=50 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=51 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=52 Destination Host Unreachable
From _gateway (10.0.3.1) icmp_seq=53 Destination Host Unreachable
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=54 ttl=109 time=192 ms
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=55 ttl=109 time=340 ms
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=56 ttl=109 time=182 ms
64 bytes from nuq04s45-in-f14.1e100.net (142.251.46.206): icmp_seq=57 ttl=109 time=249 ms
```

The LTE connection is much slower than my primary ISP. It is just a backup afterall. This is the minimum setup for failover, more advanced to come in another post.

## Configuring web gui access to LTE Modem

You may want access to the modem's web gui after all of the config is in place. To do so you need to setup a route to the modem's management IP.

In OPNsense `System -> Routes -> Configuration` add a /32 route to the management IP address. Mine is `192.168.123.254/32`

[![routes](/images/2024-03-04-multiwan-failover/routes.png)](/images/2024-03-04-multiwan-failover/routes.png)