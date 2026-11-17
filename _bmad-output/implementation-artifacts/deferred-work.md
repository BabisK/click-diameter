<!-- BMad's deferred-work queue. Open items only, in the format below; never
     annotate an entry with its outcome. A closed item leaves this file and is
     recorded in the owning spec's Review Triage Log as a `deferred` row, with
     the pull request as evidence. -->

- summary: >-
    DiameterPopStorePushAVP is a fourth push writer that still keeps per-packet
    state in members.
  evidence: |-
    src/diameterpopstorepushavp.cc decodes, mutates and encodes the member
    AvpHeader ah, and keeps the stored value in the member data, inside push().
    Two threads feeding one instance can interleave those writes and corrupt the
    appended header or the store. Finding A-8 and story 1 list only the three
    writers that keep no store, so this element is out of their change set and
    needs its own story: build the header per packet, and decide whether the
    single store is meant to be shared across threads at all. No smp-* config
    includes the element, and tests/tsan-check.sh never runs it.
  location: >-
    src/diameterpopstorepushavp.cc:69
  severity: medium

- summary: >-
    The upstream Click fork still carries conf/test.click and a stale in-tree
    copy of these elements.
  evidence: |-
    The Click fork BabisK/click carries conf/test.click, which does not
    configure, and etc/diameter/, a stale copy of these elements (F-16 of
    spec-diameter-package-hardening). The removal is one commit in that fork, so
    nothing in this package can perform or verify it.
  location: >-
    external: BabisK/click conf/test.click, etc/diameter/
  severity: low
