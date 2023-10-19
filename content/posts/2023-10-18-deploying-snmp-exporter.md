+++
title = 'Deploying snmp_exporter via Ansible'
date = 2023-10-18
draft = false
+++

A [previous](https://colby.gg/posts/2023-10-17-monitoring-synology/) post described how to monitor a Synology NAS with SNMP and Prometheus. This post goes over the Ansible role created to deploy the snmp_exporter. I'm rather dissatisfied with the way I'm doing testing with molecule at the moment, so I'm not releasing the full role in a repo at this time. However the important files are layed out.

It would probably be nicer to build an image with the SNMP exporter and deploy a container, but this Ansible deployment was quick and easy to bang out.

## The main.yml tasks

This file details all of the tasks needed to deploy the snmp_exporter. Variable explanations to follow.

```yaml
---
- name: "Download prometheus node exporter binary"
  ansible.builtin.get_url:
    url: "{{ snmp_exporter_base_url }}/v{{ snmp_exporter_version }}/snmp_exporter-{{ snmp_exporter_version }}.linux-amd64.tar.gz"
    dest: "/home/ansible/snmp_exporter-{{ snmp_exporter_version }}.linux-amd64.tar.gz"
    mode: "0666"

- name: "Extract the exporter"
  ansible.builtin.unarchive:
    remote_src: true
    src: "/home/ansible/snmp_exporter-{{ snmp_exporter_version }}.linux-amd64.tar.gz"
    dest: "/home/ansible/"
    mode: "0750"

- name: "Copy node_exporter binary"
  become: "{{ snmp_need_sudo }}"
  ansible.builtin.copy:
    remote_src: true
    src: "/home/ansible/snmp_exporter-{{ snmp_exporter_version }}.linux-amd64/snmp_exporter"
    dest: /usr/local/bin/snmp_exporter
    mode: "0750"
    owner: "node_exporter"
    group: "node_exporter"

- name: "Create snmp_exporter dir"
  become: "{{ snmp_need_sudo }}"
  ansible.builtin.file:
    path: "/etc/snmp_exporter"
    state: directory
    owner: node_exporter
    group: node_exporter
    mode: "0700"

- name: "Install templates"
  become: "{{ snmp_need_sudo }}"
  ansible.builtin.template:
    src: "{{ item.src }}"
    dest: "{{ item.dst }}"
    owner: node_exporter
    group: node_exporter
    mode: "0600"
  loop:
    - { src: "templates/snmp.yml.j2", dst: "/etc/snmp_exporter/snmp.yml" }

- name: "Install service file"
  become: "{{ snmp_need_sudo }}"
  ansible.builtin.copy:
    src: "files/snmp_exporter.service"
    dest: /etc/systemd/system/snmp_exporter.service
    owner: "node_exporter"
    group: "node_exporter"
    mode: "0644"
  when: snmp_need_sudo

- name: "Start snmp exporter service"
  become: "{{ snmp_need_sudo }}"
  ansible.builtin.systemd_service:
    enabled: true
    name: "{{ item }}"
    state: "started"
  loop:
    - "snmp_exporter.service"
  when: snmp_need_sudo
```

## Default Variables

```yaml
---
# SNMP configs
snmp_need_sudo: true # Used for molecule testing. Can't use sudo in the containers I use to test.
snmp_exporter_base_url: https://github.com/prometheus/snmp_exporter/releases/download
snmp_exporter_version: "0.24.1"
snmp_username: snmp_user_goes_here
snmp_password: SET_ME_ENV
snmp_priv_password: SET_ME_ENV
```

## snmp.yml template

This is the head of snmp.yml.j2 file stored at templates/snmp.yml.j2. Most of the file has been left off because it's quite long. This file was generated in the [previous](https://colby.gg/posts/2023-10-17-monitoring-synology/) post.

```yaml
# WARNING: This file was auto-generated using snmp_exporter generator, manual changes will be lost.
auths:
  synology:
    community: public
    security_level: authPriv
    username: {{ snmp_username }}
    password: {{ snmp_password }}
    auth_protocol: SHA
    priv_protocol: AES
    priv_password: {{ snmp_priv_password }}
    version: 3
modules:
    # The rest of the file is omitted for brevity
```

## Deployment

This is one way this role could be deployed:

```bash
    ansible-playbook playbook_using_the_role.yml --extra-vars \"{\
      \"snmp_password\": \"${SNMP_PASSWORD}\",\
      \"snmp_priv_password\": \"${SNMP_PRIV_PASSWORD}\",\
    }\""
```
