# Third-Party Licenses

## Samba / libsmbclient

HAPxFer uses libsmbclient from the Samba project for SMB1 (NT1) protocol
support required to communicate with the Sony HAP-Z1ES.

- Project: https://www.samba.org/
- License: GNU General Public License v3.0 or later (GPL-3.0-or-later)
- Copyright: The Samba Team and contributors

The full text of the GPL v3 license is included in the LICENSE file at the
root of this repository.

libsmbclient is dynamically linked. Users must have Samba installed
(e.g., via Homebrew: `brew install samba`) to build and run HAPxFer.
