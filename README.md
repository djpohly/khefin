# khefin

A system for using a FIDO2 authenticator with [hmac-secret extension](https://fidoalliance.org/specs/fido-v2.0-id-20180227/fido-client-to-authenticator-protocol-v2.0-id-20180227.html#sctn-hmac-secret-extension) support to generate passphrase-protected secrets.

[![Continuous integration status](https://github.com/mjec/khefin/workflows/Continuous%20integration/badge.svg)](https://github.com/mjec/khefin/actions?query=workflow%3A%22Continuous+integration%22)

## Installation

For Arch Linux, install the [`khefin` AUR package](https://aur.archlinux.org/packages/khefin/).

Install dependencies `libfido2`, `libcbor` and `libsodium`, then `make all && sudo make install`.

For more, see `INSTALL.md`.

At the moment I believe this tool is linux-only; issue reports or pull requests to improve portability are gratefully accepted.

## Usage

The man page contains full usage information, but briefly:

`khefin enumerate` will give you a list of connected authenticator devices, with a leading `!` for any device that is not supported.

`khefin enrol -d /dev/hidraw0 -f /path/to/encrypted/keyfile` will create (or overwrite!) `/path/to/encrypted/keyfile` with an encrypted keyfile, the output of which depends on the authenticator at `/dev/hidraw0`.

`khefin generate -f /path/to/encrypted/keyfile` will read that encrypted keyfile and output a secret based on it; but this will fail if the originally-used authenticator device is not connected (and the button pressed, if required). This will produce a 128 character ASCII (hex digits) string on STDOUT, followed by a single newline.

`khefin-add-luks-key /path/to/encrypted/keyfile /dev/disk` will add the result of your encrypted keyfile to a keyslot in the LUKS-encrypted `/dev/disk`. See the manual for this tool for more information. **[Backup your LUKS header](https://gitlab.com/cryptsetup/cryptsetup/wikis/FrequentlyAskedQuestions#6-backup-and-data-recovery) and data before using this.**

`khefin-ssh-askpass` is a drop-in replacement for the `ssh-askpass` binary. See the manual for this tool for more information.

## Authenticator support

This application relies on an extension to the FIDO2 standard, which not all FIDO2 authenticators support. `khefin enumerate` will show a leading `!` for any connected authenticator that is not supported.

For a list of authenticators known to work or not work with this software, see [the GitHub wiki page](https://github.com/mjec/khefin/wiki/Supported-authenticators).

## Risks

The number one risk is that by playing around with encryption like this you will lose your data. Keep good, offline backups of your data. Test your backups regularly, to ensure files can be recovered without access to any of your usual hardware or software.

Each keyfile is associated with _only one_ authenticator, and _only one_ passphrase. To be secure, you are going to need at least two authenticators, which means two keyfiles. Make sure that whatever system you're using has support for that.

[Backup your LUKS header](https://gitlab.com/cryptsetup/cryptsetup/wikis/FrequentlyAskedQuestions#6-backup-and-data-recovery) and data before using this for disk encryption keys. Seriously.

Keep a backup of the keyfile created by this application as well. If you lose that file, it is impossible to recover the secret.

The security of this system depends on the security of your authenticator device, libsodium, libfido2, and the quality of your passphrase. It's also possible -- and indeed more likely than any of the former issues -- that there's a bug in the code for this application which compromises its security somehow. Pull requests and issues are very welcome.

## Warrant canary (but not a warranty)

As at 17 January 2021, I (@mjec) have not received or complied with any government or non-government requests for information or services relating to this software, nor am I aware of any such requests.
