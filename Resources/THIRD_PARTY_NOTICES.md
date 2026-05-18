# Third-Party Notices

XDVPN bundles the following third-party software in release builds.

## OpenConnect

- Project: https://www.infradead.org/openconnect/
- License: LGPL-2.1-only
- Source: https://gitlab.com/openconnect/openconnect
- Usage: VPN client core, dynamically linked
- Version policy: pinned major/minor, patch updates allowed after build-time validation

OpenConnect is used under LGPL-2.1. Source code is available from the upstream repository.

## ocproxy

- Project: https://github.com/cernekee/ocproxy
- License: BSD-3-Clause
- Usage: userspace SOCKS5 proxy for proxy-only mode (openconnect --script-tun)

## libevent

- Project: https://libevent.org/
- License: BSD-3-Clause
- Source: https://github.com/libevent/libevent
- Usage: runtime dependency of ocproxy

The release build also bundles non-system dynamic libraries required by these components. Their upstream license terms remain with those projects.
