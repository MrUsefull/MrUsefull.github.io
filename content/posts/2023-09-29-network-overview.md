+++
title = 'Documenting my current home network'
date = 2023-09-29
featured_image="/images/2023-09-29-network-overview/HomeLab.png"
draft = false
toc = true
tags = ["home network", "network", "diagram"]
+++

My home network setup currently allows me to host multiple useful services in a K3S cluster, as well as access my security footage or any other service remotely over Wireguard. All host level resources are deployed with [Ansible](https://www.ansible.com/community) for automation. No manual changes allowed.

That is to say, no manual changes other than OS install. That part still needs to be automated in order to make all hosts truly replaceable.

Application level automation is largely through helm for services deployed in K3S, and docker-compose managed through Ansible for those special cases.

All services running have valid TLS certificates provisioned automatically.

The domain used for my home network has been replaced by `network_domain_name.here` for paranoia reasons.

## Diagram

[![Architecture diagram](/images/2023-09-29-network-overview/HomeLab.png)](/images/2023-09-29-network-overview/HomeLab.png)

## Hosts

### Net-Tools

Net-Tools is one of the most important hosts on the network. This box is responsible for:

- DNS network AdBlocking with [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome#getting-started)
- VPN access with [Wireguard](https://github.com/linuxserver/docker-wireguard)
- [Caddy](https://caddyserver.com/) for TLS termination reverse-proxy to AdGuard Home's admin interface
- Cronjob to update Cloudflare with my current external IP

The host is provisioned via Ansible. The services are running in docker-compose, also provisioned by Ansible. Caddy provisions certificates via [dns challenge](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge) with CloudFlare's API and Let's Encrypt.

The cron script updates `vpn.network_domain_name.here` with the external IP of my router, which forwards port 51820 to Wireguard.

AdGuard home has a nice API that allows me to dynamically provision DNS rewrites (local DNS) for services as they come up and down. Combined with Wireguard, I can visit `https://serviceName.network_domain_name.here`

### Synology NAS

The NAS is probably the second favorite host on the network. The NAS has [certbot](https://eff-certbot.readthedocs.io/en/stable/) provisioning new TLS certificates periodically. This was a little bit of a pain to figure out, hopefully I'll have a writeup on this before I completely forget it all.

The NAS has 12tb in RAID 10 with a R/W NVMe cache to speed everything up. NAS Storage includes:

- All photos, movies, tv shows, and other media
- Encrypted database and configuration backups
- Home security footage

The NAS sends motion detection alerts for some cameras, and is accessible when connected to Wireguard.

### Security Cameras

There are several security cameras throughout the house. Most are Amcrest at the moment, and a Reolink doorbell. Only the doorbell has external network access; all others can only talk to the NAS.

### K3S cluster

I have a small kubernetes cluster running on some old desktop hardware and some cheap MiniPcs. I chose the MiniPcs for multiple hosts because they were so much cheaper than Raspberry Pis at the time. Host level install is done via Ansible, databases are backed by NVMe mount(s) and automatic backups are taken once a week.

Some key services include:

GitLab
: Gitlab allows me to keep all source code for all of my projects at `gitlab.network_domain_name.here`, and also allows an easy way to run build automation and Ansible jobs.

Jellyfin
: Jellyfin for all of my media indexing needs. `jellyfin.network_domain_name.here` makes a great backend for Kodi and the smart TV. It's also accessible from anywhere over Wireguard.

Grafana
: Displays metrics for all services. Alerts go to Discord.

Misc
: Several other applications I've written for myself, and other misc services.

### BuildyBoy

This box is for bare metal builds and trying things that I think might break a host. Unfortunately my Ansible tests need a bare metal host at the moment in order to spin up and destroy containers within containers. I'm sure I'll fix this someday.

## Future plans

I'm not really sure what I'm going to tinker around with next. Some potential ideas are:

- More home automation with Home Assistant.
- Maybe I'll actually finish one of the applications I've written that are currently in a "good enough" state.
- Improve metrics and monitoring.
- Try that NextCloud thing.
