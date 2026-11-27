# C516 webhook test isolation boundary

The C516 webhook route regressions execute the exported Next.js `POST` handler in a separate Node process. Before importing the route, the harness installs deterministic denial interceptors for:

- global Fetch and the Node `net` / `Socket` connection entry points;
- Node TLS and HTTP/HTTPS request entry points;
- HTTP/2 client connections;
- UDP datagram socket creation;
- Node DNS lookup, reverse-lookup, and resolver APIs, including the promise API;
- the global WebSocket constructor when the runtime provides it.

Every intercepted attempt increments a counter and throws. Tests require the counter to remain zero. The exported-route instrumentation test additionally mocks the Supabase client module and webhook verifier module before importing the route. It counts privileged client constructions, verifier calls, database RPC calls, and outbound-network attempts for each invalid destination; every counter must remain zero and every response must be HTTP 503.

The existing privacy-canary regression remains separate and exercises the real Svix verifier with an invalid signature. It asserts that synthetic recipient addresses and raw payload canaries are absent from captured console output and response bodies.

## Isolation limitations

This is deterministic, process-local API interception, not an OS network namespace, firewall rule, or kernel-enforced egress sandbox. It does not prove that arbitrary native addons, subprocesses, worker processes, undocumented runtime internals, or future third-party transports cannot open sockets through APIs outside the intercepted interfaces. The tested webhook path imports no such transport in its invalid-destination branch, and its privileged Supabase client and verifier are mocked in the dedicated boundary test. CI also runs with no Production credentials and `DELIVERY_ENABLED=false`.

Do not describe this harness as a complete process-wide or OS-level network isolation boundary. If a future route change introduces native networking, subprocesses, workers, or a new transport, extend the interceptors or run the regression inside a kernel-enforced network-disabled environment before accepting the security claim.
