# Network addressing: one address or two?

## The Wi-Fi chip runs its own network stack

The BL616 module keeps its own TCP/IP stack: it obtains an address over DHCP and
keeps the vendor cloud session, even while the Linux side has no address at all
(ICMP replies with TTL 255 and outbound vendor connections continue to exist in
that state).

The Linux interface (`bleth0`) is the same physical Wi-Fi interface, so it has
the **same MAC address** as the module. In the stock firmware `sta.sh` assigns
the Linux interface the **same address** that the chip obtained over DHCP. One
address is therefore shared by two independent network stacks.

## Why the stock firmware gets away with it

- All vendor traffic is **outbound** (P2P and cloud connections). The device does
  not run any LAN server that somebody connects to, so the two stacks rarely
  compete for an incoming connection.
- Duplicate ICMP replies (TTL 255 from the chip and TTL 64 from Linux) are a
  cosmetic artefact of `ping`, not a functional problem.
- Address changes happen on the chip side (DHCP renew), and the vendor
  application tolerates the resulting races well enough.

## Why a control channel prefers two addresses

A control channel is a **bidirectional TCP connection with one fixed peer** (the
hub), and both directions must be reliable: the device fetches a command and
uploads the output. With one shared address:

- the hub's ARP entry maps the address to the module MAC, and an incoming packet
  is visible to both stacks — which one answers (SYN-ACK or RST) is a race;
- ICMP answers are duplicated (TTL 255 and TTL 64);
- a DHCP renew on the chip side can move the address while the Linux static
  address stays behind;
- a health check that probes the hub produces false "unreachable" results and
  can trigger an unnecessary fallback to the other slot.

So the recommended split is:

| Owner | Address | How |
|---|---|---|
| Wi-Fi module (chip stack) | `192.0.2.10` in the examples (stock DHCP) | chip's own DHCP client |
| Linux (`bleth0`) | `192.0.2.20` in the examples | static, re-applied by the poller |

With the split, ICMP on the chip address is answered only by the chip and ICMP
on the Linux address only by Linux, and the control channel stays stable.

## Can both addresses come from DHCP?

**Not with this hardware, because of the MAC.** The DHCP server keys a lease by
MAC (that is how MikroTik and most consumer routers work), so two stacks behind
one MAC receive the same address — the original conflict comes back.

Options for the future:

1. **DHCP reservation plus a static second address** (the scheme above): the
   router reserves the chip address for the MAC, Linux keeps a static address.
   Deterministic and independent of the chip's renew cycle.
2. **Different DHCP client identifiers**: some DHCP servers (e.g. ISC DHCP) can
   keep separate leases for different client identifiers on the same MAC, but
   consumer routers usually cannot. Even then both stacks see every frame and
   discard packets addressed to the other stack's IP.
3. **NetHub mode**: the module exposes the Wi-Fi interface to the host and does
   not keep an IP stack of its own, so Linux owns the only address and DHCP
   works cleanly. This needs different module firmware/configuration.

**Recommendation:** keep the second address static (plus a DHCP reservation for
the first one). DHCP for the Linux side makes sense together with a move to
NetHub mode, not before it.
