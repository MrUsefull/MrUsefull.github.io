+++
title = 'Multiwan 2: Segementation and Gateway Groups'
date = 2024-03-22
tags = ["network", "failover", "opnsense", "home network", "HA", "multiwan"]
toc = true
featured_image="/images/2024-03-22-multiwan-2/gateway_groups_complete.png"
series = ["multiwan"]
summary = "A more advanced and useful multiwan failover setup. Block some VLANs from accessing the failover connection, limiting failover use to actual users or other high priority traffic."
+++

This post is a follow-up to the simplified [multiwan](/posts/2024-03-04-multiwan-failover/) setup.

## The Problem

The setup described in the previous [multiwan](/posts/2024-03-04-multiwan-failover/) allows automatic failover for all traffic leaving the firewall. This is problematic, since the LTE connection is both expensive and relatively slow. My LTE connection currently charges for usage over 1GB. The only traffic I want to have actually use the failover is user traffic. I absolutely do not want low priority but relatively heavy traffic to flow through the LTE Modem.

At some point I'll hopefully replace the backup connection to be something with unlimited data, but at the moment this is super cheap. Well, it's cheap until you actually have to use it.

## The Plan

There are several ways to achieve the desired results where some VLANs can failover, but some cannot talk to the LTE failover connection. This is just how I've done it.

We will be creating multiple gateway groups, and firewall rules to match. One gateway group will point towards the primary and failover gateway, the other will use only the primary gateway. Firewall rules will be updated to allow some VLANs access to the failover gateway group, and other VLANs access only to the primary. I use gateway groups even for the primary only connection in case I ever get a third ISP that is not expensive to use.

We are assuming the OPNsense router is in the state we left it in after the [previous post](/posts/2024-03-04-multiwan-failover/)

## Steps

0. Take a backup. Never forget to take a backup before making any changes!
1. Go to System -> Gateways -> Group. Create two gateway groups. One group for primary only, the other group containing primary and failover gateways. If you intend to use IPv6 and IPv4, you will need 4 groups, one for IPv4 and one for IPv6.

    Primary only

    [![primary only](/images/2024-03-22-multiwan-2/gateway-groups-primary-only.png)](/images/2024-03-22-multiwan-2/gateway-groups-primary-only.png)

    Primary and Failover

    [![primary and failover](/images/2024-03-22-multiwan-2/gateway-groups-primary-and-failover.png)](/images/2024-03-22-multiwan-2/gateway-groups-primary-and-failover.png)

    All Groups

    [![all groups](/images/2024-03-22-multiwan-2/gateway_groups_complete.png)](/images/2024-03-22-multiwan-2/gateway_groups_complete.png)

2. Create firewall rules for users VLAN

    Using gateway groups requires more firewall rules than without. You must point your egress traffic to the appropriate group by default. You must also have rules allowing any local traffic such as DNS, or accessing local services, to the appropriate places.

    [![user's firewall settings](/images/2024-03-22-multiwan-2/firewall-users.png)](/images/2024-03-22-multiwan-2/firewall-users.png)

    Pictured are the firewall rules for a user's vlan. There are a few important rules here.

    - At the bottom are two allow rules, one for IPv4 and one for IPv6 pointing at the appropriate gateway group for failover. This ensures traffic will go to the primary connection when up, and the LTE connection otherwise.

    - Just above the gateway rules are allow rules for managing the LTE modem. I've previously created an alias for the modem's WebUI. The rule here allows access to the modem's WebUI IP from the LTE interface.

    - At the very top of the screenshot are rules from a group I've created. These rules allow access to all local networks I've defined in the group from LAN and users VNET. The DNS firewall rules could be handled the same way, I'm sure someday I'll get around to it.

3. Create firewall rules for services VLAN

    [![LAN firewall](/images/2024-03-22-multiwan-2/firewall-lan.png)](/images/2024-03-22-multiwan-2/firewall-lan.png)

    You can see the LAN VNET has the same group rules as the user VNET above. The differences are the DNS rules, and importantly the bottom two rules use the primary only gateway groups for egress traffic.
