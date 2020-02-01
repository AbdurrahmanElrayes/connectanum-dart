# connectanum-dart

This is a wamp client implementation for dart or flutter projects. The projects aims to 
provide a simple an extensible structure and returning something to the great WAMP-Protocol community.

## TODOs

- Multithreading for callee invocations
    - callee interrupt thread on incoming cancellations
- better docs  
- web socket support
- get the auth id that called a method

## Supported WAMP features

### Advanced RPC features

- [x] Progressive Call Results
- [x] Progressive Calls
- [ ] Call Timeouts
- [x] Call Canceling
- [x] Caller Identification
- [ ] Call Trust Levels
- [x] Shared Registration
- [ ] Sharded Registration

### Advanced PUB/SUB features

- [x] Subscriber Black- and Whitelisting
- [x] Publisher Exclusion
- [x] Publisher Identification
- [ ] Publication Trust Levels
- [x] Pattern-based Subscriptions
- [ ] Sharded Subscriptions
- [ ] Subscription Revocation

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
final client = new Client(realm: "my.realm",transport: new WebSocketTransport("wss://localhost:8443"));
final session = await client.connect();
```

## RPC

to work with RPCs you need to have an established session. 

```dart
final client = new Client(realm: "my.realm",new WebSocketTransport("wss://localhost:8443"));
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
