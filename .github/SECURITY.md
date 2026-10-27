# Security policy

## Supported versions

Security fixes are made for the latest release. Older versions are not supported
separately.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability. Use
[private reporting](https://github.com/cunderw/tower/security/advisories/new) so the report
and follow-up remain private.

Use private reporting for issues involving the API keys Tower stores, the keychain, the
requests Tower sends to a server or a service, or an action that runs on a server without
the user asking for it. Include the affected version, reproduction steps, impact, and any
evidence that can be shared safely. Do not include API keys, server addresses or other
private data unless they are essential to the report.

Ordinary bugs and feature requests should continue to use the public issue templates.

Tower does not currently offer a bug bounty or promise a response deadline.

## Known limitations

Tower stores every API key, username and password in the iOS keychain on the device. It
sends each one only to the server or service it belongs to, in one of three ways:

- The Unraid server, Sonarr, Radarr, Lidarr, Prowlarr, Bazarr and Overseerr: the API key
  in a request header.
- Tautulli: the API key in the URL, as the `apikey` query parameter, because Tautulli
  ignores the header form. A key in a URL can land in the access logs of Tautulli and of
  any proxy in front of it.
- NZBGet: the username and password, with HTTP Basic authentication.

Tower accepts an `http://` address as well as an `https://` one, because many Unraid
servers and self-hosted services serve plain HTTP. `Tower/Info.plist` sets only
`NSAllowsLocalNetworking` under App Transport Security. Per Apple's documentation, that
allows plain HTTP to IP addresses (IPv4 and IPv6, with no limit to private ranges),
`.local` names and unqualified host names. App Transport Security still refuses plain HTTP
to a fully qualified DNS name. Over an `http://` address the key, or the NZBGet password,
travels unencrypted, and anyone who can read traffic on that network can read it. Use an
`https://` address where the server offers one.

Posters and covers load directly from third-party image hosts. Sonarr, Radarr and Lidarr
send the image addresses, on hosts such as TMDb and TheTVDB. For Overseerr, Tower builds
the address on `image.tmdb.org` from the path Overseerr sends. Those requests carry no
key, but the hosts see the device's IP address and which titles it shows.

If you find that Tower exposes more than this, please report it through private
reporting.
