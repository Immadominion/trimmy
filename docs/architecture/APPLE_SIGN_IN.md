# Apple sign-in

The production account screen offers Apple on iOS and routes it through the
existing account controller and Privy session verification. Android does not
show this option: the installed Privy Flutter SDK 0.10.2 explicitly rejects Apple
login on Android. Email, Google and X remain available there.

The iOS Runner declares the Sign in with Apple capability and entitlement. A
native rebuild with a matching provisioning profile is required to install the
entitlement; hot reload cannot add it.

## Provider setup still required

The read-only Privy app settings check on 2026-09-24 returned
`apple_oauth: false`. No provider settings were changed and no Apple account was
used to sign in. Before enabling production Apple login:

- Configure Apple under Privy's authentication methods. For native iOS, use
  Trimmy's bundle ID (`com.trimmy.trimmy`) as the Apple client ID, as specified by
  Privy's native Apple setup guide.
- Enable Sign in with Apple for that identifier in the Apple Developer account
  and rebuild with a provisioning profile that includes the entitlement.
- Verify successful sign-in, cancellation and return to the current flow on an
  iPhone. The controller and native provider mapping are covered by local tests;
  those tests do not establish that the external provider is configured.

References: [Privy Flutter](https://pub.dev/documentation/privy_flutter/latest/)
and [native Apple setup](https://docs.privy.io/recipes/swift/apple).
