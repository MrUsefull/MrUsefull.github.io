+++
title = 'Securing simple web services behind caddy with SSO'
date = 2024-12-07
toc = true
tags = ["sso", "caddy", "oauth2-proxy", "oauth"]
summary = "Adding SSO with OIDC to simple webapps proxied by Caddy"
+++

## The Problem

I have a simple WebService running behind Caddy on some `server1.my.example.fqdn`, and my SSO provider running at `auth.my.example.fqdn`. The simple WebService should be protected by a login. I could configure the service to use HTTP Basic Auth, but then I'd have to manage users. I would prefer to use my existing SSO via [OIDC](https://auth0.com/docs/authenticate/protocols/openid-connect-protocol). For this use case, any authenticated user should have full and complete access to the service.

Unfortunately, Caddy also does not support OIDC out of the box. I had a surprisingly difficult time getting SSO working the way I wanted here, so I'm quickly recording what I've done.

## Solution

Configure [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) and forward auth with Caddy. There are other solutions, but this generally seems to work.

All configurations below assume the SSO provider is already configured.

## Docker Compose

***Note: The original version used bitnami's oauth2-proxy [never](https://community.broadcom.com/tanzu/blogs/beltran-rueda-borrego/2025/08/18/how-to-prepare-for-the-bitnami-changes-coming-soon) use anything bitnami***

```yml
services:
    caddy:
        image: caddy:latest
        restart: unless-stopped
        networks:
            - caddy
        container_name: caddy
        cap_add:
            - NET_ADMIN
            - CAP_NET_BIND_SERVICE
            - CAP_NET_RAW
        ports:
            - "80:80" # For redirect
            - "443:443"
            - "443:443/udp"
        volumes:
            - confdir/Caddyfile:/etc/caddy/Caddyfile
            - datadir:/data
            - confdir:/config
        environment:
            ACME_AGREE: "true"

    oauth2-proxy:
        container_name: oauth2-proxy
        image: quay.io/oauth2-proxy/oauth2-proxy:v7.12.0
        restart: unless-stopped
        command: "oauth2-proxy --email-domain=*"
        # WARNING: Many env variables seem to be completely ignored
        environment:
          - OAUTH2_PROXY_PROVIDER=oidc
          - OAUTH2_PROXY_CLIENT_ID=CLIENT_ID_GOES_HERE
          - OAUTH2_PROXY_CLIENT_SECRET=CLIENT_SECRET_GOES_HERE
          - OAUTH2_PROXY_REDIRECT_URL=https://server1.myexample.fqdn/oauth2/callback
          - OAUTH2_PROXY_OIDC_ISSUER_URL=https://auth.my.example.fqdn/application/o/server1/
          - OAUTH2_PROXY_COOKIE_SECRET=73EgCj7ktL51UWJH5B0c7lZ9cKPeNmgX5qeBUcsWG7s=
          - OAUTH2_PROXY_COOKIE_SECURE=true
          - OAUTH2_PROXY_COOKIE_DOMAINS=server1.my.example.fqdn
          - OAUTH2_PROXY_WHITELIST_DOMAINS=server1.my.example.fqdn
          - OAUTH2_PROXY_UPSTREAMS=static://200
          - OAUTH2_PROXY_HTTP_ADDRESS=0.0.0.0:4180
          - OAUTH2_PROXY_SKIP_PROVIDER_BUTTON=true
          - OAUTH2_PROXY_CODE_CHALLENGE_METHOD=S256
        networks:
          - caddy

    server1:
        container_name: server1
        image: example/image/here:latest
        networks:
          - caddy

    networks:
        caddy:
```

### Important notes

`OAUTH2_PROXY_UPSTREAMS=static://200` was a somewhat difficult to dig out setting to respond with http 200 and let Caddy proceed with the reverse proxying after the forward auth. I found that some services worked fine with setting `OAUTH2_PROXY_UPSTREAMS=server1:8080`, but some did not.

`--email-domain="` is specified in the command. It seems the oauth2-proxy image for both bitnami and the project build image (not used here) ignore some documented configurations when using environment variables. In theory, `OAUTH2_PROXY_EMAIL_DOMAINS=*` should work but does not.

`- OAUTH2_PROXY_CODE_CHALLENGE_METHOD=S256` will vary based on the SSO provider.

## Caddyfile

```Caddyfile
server1.my.example.fqdn {
	# Requests to /oauth2/* are proxied to oauth2-proxy without authentication.
	# You can't use `reverse_proxy /oauth2/* oauth2-proxy.internal:4180` here because the reverse_proxy directive has lower precedence than the handle directive.
	handle /oauth2/* {
		reverse_proxy oauth2-proxy:4180 {
			# oauth2-proxy requires the X-Real-IP and X-Forwarded-{Proto,Host,Uri} headers.
			# The reverse_proxy directive automatically sets X-Forwarded-{For,Proto,Host} headers.
			header_up X-Real-IP {remote_host}
			header_up X-Forwarded-Uri {uri}
		}
	}
	# Requests to other paths are first processed by oauth2-proxy for authentication.
	handle {
		forward_auth oauth2-proxy:4180 {
			# uri /oauth2/auth # Checking if order
			uri /oauth2/
			# oauth2-proxy requires the X-Real-IP and X-Forwarded-{Proto,Host,Uri} headers.
			# The forward_auth directive automatically sets the X-Forwarded-{For,Proto,Host,Method,Uri} headers.
			header_up X-Real-IP {remote_host}
			# If needed, you can copy headers from the oauth2-proxy response to the request sent to the upstream.
			# Make sure to configure the --set-xauthrequest flag to enable this feature.
			#copy_headers X-Auth-Request-User X-Auth-Request-Email
			# If oauth2-proxy returns a 401 status, redirect the client to the sign-in page.
			@error status 401
			handle_response @error {
				redir * /oauth2/sign_in?rd={scheme}://{host}{uri}
			}
		}
	}
	reverse_proxy server1:8080
}
```
