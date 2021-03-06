# connectanum-dart

This is a WAMP client implementation for the [dart language](https://dart.dev/) and [flutter](https://flutter.dev/) projects. 
The projects aims to provide a simple and extensible structure that is easy to use.
With this project I want return something to the great WAMP-Protocol community.

WAMP is trademark of [Crossbar.io Technologies GmbH](https://crossbario.com/).

## TODOs

- add code coverage report
- add github runners to test code with multiple dart versions
- Multithreading for callee invocations
    - callee interrupt thread on incoming cancellations
- better docs
- msgpack serializer
- get the auth id that called a method
- handle ping pong times
- auto reconnect handling, but keep abstract socket interface
    - difference between intentionally and unintentionally disconnect
    - websocket has error and regular close event. 
      use them if possible or use close with internal state from this package?

## Supported WAMP features

### Authentication

- ☑ [WAMP-CRA](https://wamp-proto.org/_static/gen/wamp_latest.html#wampcra)
- ☑ [TICKET](https://wamp-proto.org/_static/gen/wamp_latest.html#ticketauth)
- ☑ [WAMP-SCRAM](https://wamp-proto.org/_static/gen/wamp_latest.html#wamp-scram)
    - ⬜ Argon2
    - ☑ PBKDF2

### Advanced RPC features

- ☑ Progressive Call Results
- ☑ Progressive Calls
- ⬜ Call Timeouts
- ☑ Call Canceling
- ☑ Caller Identification
- ⬜ Call Trust Levels
- ☑ Shared Registration
- ⬜ Sharded Registration

### Advanced PUB/SUB features

- ☑ Subscriber Black- and Whitelisting
- ☑ Publisher Exclusion
- ☑ Publisher Identification
- ⬜ Publication Trust Levels
- ☑ Pattern-based Subscriptions
- ⬜ Sharded Subscriptions
- ⬜ Subscription Revocation

## Stream model

The transport contains an incoming stream that is usually a single subscribe stream. A session will internally
open a new broadcast stream as soon as the authentication process is successful. The transport stream subscription
passes all incoming messages to the broad cast stream. If the transport stream is done, the broadcast stream will close
as well. The broad cast stream is used to handle all session methods. The user will never touch the transport stream
directly.

## Start the client

To start a client you need to choose a transport module and connect it to the desired endpoint.
When the connection has been established you can start to negotiate a client session by calling
the `client.connect()` method from the client instance. On success the client will return a
session object.

If your transport disconnects the session will invalidate. If a reconnect is configured, the session
will try to authenticate an revalidate the session again. All subscriptions and registrations will
be recovered if possible.

```dart
import 'package:connectanum/connectanum.dart';
import 'package:connectanum/json.dart';

final client = Client(
  realm: "my.realm",
  transport: WebSocketTransport(
    "ws://localhost:8080/wamp",
    new Serializer(),
    WebSocketSerialization.SERIALIZATION_JSON
  )
);
final session = await client.connect();
```

## RPC

to work with RPCs you need to have an established session. 

```dart
import 'package:connectanum/connectanum.dart';
import 'package:connectanum/json.dart';

final client = Client(
  realm: "my.realm",
  transport: WebSocketTransport(
    "ws://localhost:8080/wamp",
    new Serializer(),
    WebSocketSerialization.SERIALIZATION_JSON
  )
);
final session = await client.connect();

// Register a procedure
final registered = await session.register("my.procedure");
registered.onInvoke((invocation) {
  // to something with the invocation
})

// Call a procedure
await for (final result in session.call("my.procedure")) {
  // do something with the result
}
```
