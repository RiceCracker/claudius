# OBSOLETE — superseded by ADR-007 (2026-04-28)

The transparent proxy sidecar described by EPIC-02 and its stories (STORY-03 TCP proxy, STORY-04 SNI anti-spoof, STORY-05 UDP/ICMP NFQUEUE) was removed. claudius no longer performs in-process network filtering. See `quality/adr/ADR-007.md` for the rationale.

These files are kept here for historical context only. Do not implement against them.
