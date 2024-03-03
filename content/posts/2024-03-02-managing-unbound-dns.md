+++
title = 'Managing Unbound DNS overrides with Boundation'
date = 2024-03-02
summary = "CRUD OPNsense Unbound DNS with CLI or External DNS"
featured_image="/images/2024-03-02-managing-unbound-dns/pipeline.png"
toc = true
+++

## [Boundation](https://github.com/MrUsefull/boundation) GitHub repository

At some point in the past six months or so I've started using a mini pc with OPNsense installed as my router. I've replaced AdGuard Home with [Unbound DNS](https://docs.opnsense.org/manual/unbound.html) running on the router. It provides all the blocklist functionality I want, plus Unbound integrates quite well with the DHCP server.

Generally I like Unbound, but managing DNS changes automatically has proven more challenging than with AdGuard Home. With AdGuard home I used [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) and the [External DNS - Adguard Home Provider (Webhook)](https://github.com/muhlba91/external-dns-provider-adguard) to automatically manage DNS entries for my Kubernetes deployment. No such option seems to exist for Unbound.

So I built Boundation. That's the best name I could come up with. Let's not talk about that.

## Requirements

- DNS entries must be created for environments as they're spun up. For example, if I open a PR for one of my web projects, a test environment is created with a new ingress. My internal DNS must be updated with the appropriate records.
- DNS entries must be removed when environments are destroyed. When I merge the example PR, the test environment is automatically torn down. The DNS record must also be cleaned up.
- Bonus: Ability to manage DNS for services outside of Kubernetes.

## Initial Solution

I created an External DNS Webhook for Unbound using the OPNsense [API](https://docs.opnsense.org/development/api/core/unbound.html). When I deployed it with External DNS, I found that duplicate DNS entries were constantly being created. I had either misconfigured External DNS, or done something wrong. Either way, I realized External DNS was overkill. The only time I need a DNS entry to change is when I Create, Update, or Delete a deployment.

## Simplified Solution

I took the work I'd done for the webhook and created a simple CLI. Some simple usage examples:

Create or Update overrides:

```bash
unbound upsert --host=example.domain.here --target=1.2.3.4 --host=other.host.com --target=5.6.7.8
```

Read existing overrides

```bash
unbound read
```

Delete overrides

```bash
unbound delete --host=example.domain.here
```

Run interactive configuration menu

```bash
unbound configure
```

Source code for both solutions can be found in the [boundation](https://github.com/MrUsefull/boundation) repo.

## Example snippets for GitLab CI

I use GitLab for my internal projects, so here's an example `.gitlab-ci.yml` snippet for pull request deployments, creating the DNS entry then deleting the entry when the environment is stopped.

```yaml
pr-deploy:
  rules:
    - if: $CI_MERGE_REQUEST_ID
  stage: deploy
  needs:
    - jobs
    - needed
    - for
    - deploy
    - here
  variables:
    ENV_HOSTNAME: ${CI_MERGE_REQUEST_ID}-example.domain.here
  image:
    name: alpine/k8s:1.25.13
    entrypoint: [""]
  script:
    - deployment_command_here.sh
  environment:
    name: ${CI_MERGE_REQUEST_ID}
    url: https://${ENV_HOSTNAME}
    on_stop: pr-stop

pr-dns-create:
  needs:
    - pr-deploy
  rules:
    - if: $CI_MERGE_REQUEST_ID
  stage: dns
  variables:
    ENV_HOSTNAME: ${CI_MERGE_REQUEST_ID}-example.domain.here
    TARGET_IP: 1.2.3.4 # put the ip address you want here
  script:
    - go install github.com/MrUsefull/boundation/cmd/unbound@latest
    - mv ${UNBOUND_CFG} ${UNBOUND_CFG}.yaml # current cfg package needs a .yaml extension. May change.
    - unbound upsert --host=${ENV_HOSTNAME} --target=${TARGET_IP} --config=${UNBOUND_CFG}.yaml

pr-stop:
  stage: deploy
  image:
    name: alpine/k8s:1.25.13
    entrypoint: [""]
  environment:
    name: ${CI_MERGE_REQUEST_ID}
    action: stop
  rules:
    - if: $CI_MERGE_REQUEST_ID
  when: manual
  script:
    - stop_command_here.sh

pr-dns-delete:
  needs:
    - pr-stop
  stage: dns
  environment:
    name: ${CI_MERGE_REQUEST_ID}
    action: stop
  rules:
    - if: $CI_MERGE_REQUEST_ID
  variables:
    ENV_HOSTNAME: ${CI_MERGE_REQUEST_ID}-example.domain.here
  script:
    - go install github.com/MrUsefull/boundation/cmd/unbound@latest
    - mv ${UNBOUND_CFG} ${UNBOUND_CFG}.yaml # current cfg package needs a .yaml extension. May change.
    - unbound delete --host=${ENV_HOSTNAME} --config=${UNBOUND_CFG}.yaml


```

Example cli config. You can get the API key in the OPNsense UI under `System` -> `Access` -> `Users` -> `${USER}` -> click the `+` button in the `API Keys` section.

```yaml
opnsense:
    baseurl: https://router.example.domain.here
    creds: <API_KEY_NAME>:<API_KEY_SECRET>
filter:
    filter: []
    exclude: []
loglevel: INFO

```

Obviously the script sections above can be pulled into more reusable scripts, this is just an example afterall. The snippet above is 90% of a fully automated environment deployment and DNS management with GitLab CI.

[![example pipeline](/images/2024-03-02-managing-unbound-dns/pipeline.png)](/images/2024-03-02-managing-unbound-dns/pipeline.png)