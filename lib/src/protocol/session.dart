import 'dart:async';

import '../message/abort.dart';
import '../message/abstract_message.dart';
import '../message/abstract_message_with_payload.dart';
import '../message/authenticate.dart';
import '../message/cancel.dart';
import '../message/challenge.dart';
import '../message/goodbye.dart';
import '../message/message_types.dart';
import '../message/unsubscribed.dart';
import '../message/welcome.dart';
import '../message/uri_pattern.dart';
import '../message/details.dart' as detailsPackage;
import '../message/call.dart';
import '../message/event.dart';
import '../message/hello.dart';
import '../message/invocation.dart';
import '../message/publish.dart';
import '../message/published.dart';
import '../message/register.dart';
import '../message/registered.dart';
import '../message/result.dart';
import '../message/subscribe.dart';
import '../message/subscribed.dart';
import '../message/unregister.dart';
import '../message/unregistered.dart';
import '../message/unsubscribe.dart';
import '../message/error.dart';
import '../transport/abstract_transport.dart';
import '../authentication/abstract_authentication.dart';

class Session {

  int id;
  String realm;
  String authId;
  String authRole;
  String authMethod;
  String authProvider;

  AbstractTransport _transport;

  int nextCallId = 1;
  int nextPublishId = 1;
  int nextSubscribeId = 1;
  int nextUnsubscribeId = 1;
  int nextRegisterId = 1;
  int nextUnregisterId = 1;

  final Map<int, Registered> registrations = {};
  final Map<int, Subscribed> subscriptions = {};

  StreamSubscription<AbstractMessage> _transportStreamSubscription;
  StreamController _openSessionStreamController = new StreamController.broadcast();

  static Future<Session> start(
      String realm,
      AbstractTransport transport,
      {
        String authId: null,
        List<AbstractAuthentication> authMethods: null,
        Duration reconnect: null
      }
  ) async
  {
    /**
     * The realm object is mandatory and must mach the uri pattern
     */
    assert(realm != null && UriPattern.match(realm));
    /**
     * The connection should have been established before initializing the
     * session.
     */
    assert(transport != null && transport.isOpen);

    /**
     * Initialize the session object with the realm it belongs to
     */
    final session = new Session();
    session.realm = realm;
    session._transport = transport;

    /**
     * Initialize the sub protocol with a hello message
     */
    final hello = new Hello(realm, detailsPackage.Details.forHello());
    if (authId != null) {
      hello.details.authid = authId;
    }
    if (authMethods != null && authMethods.length > 0) {
      hello.details.authmethods = authMethods.map<String>((authMethod) => authMethod.getName()).toList();
    }
    transport.send(hello);

    /**
     * Either return the welcome or execute a challenge before and eventually return the welcome after this
     */
    Completer<Session> welcomeCompleter = new Completer<Session>();
    session._transportStreamSubscription = transport.receive().listen(
      (message) {
        if (message is Challenge) {
          final AbstractAuthentication foundAuthMethod = authMethods.where((authenticationMethod) => authenticationMethod.getName() == message.authMethod).first;
          if (foundAuthMethod != null) {
            foundAuthMethod.challenge(message.extra).then((authenticate) => session.authenticate(authenticate));
          } else {
            final goodbye = new Goodbye(new GoodbyeMessage("Authmethod ${foundAuthMethod} not supported"), Goodbye.REASON_GOODBYE_AND_OUT);
            session._transport.send(goodbye);
            throw goodbye;
          }
        } else if (message is Welcome) {
          session.id = message.sessionId;
          session.authId = message.details.authid;
          session.authMethod = message.details.authmethod;
          session.authProvider = message.details.authprovider;
          session.authRole = message.details.authrole;
          session._transportStreamSubscription.onData((message) {
            session._openSessionStreamController.add(message);
          });
          session._transportStreamSubscription.onDone(() {
            session._openSessionStreamController.close();
          });
          welcomeCompleter.complete(session);
        } else if (message is Abort) {
          try {
            transport.close();
          } catch (ignore) {/* my be already closed */}
          welcomeCompleter.completeError(message);
        } else if (message is Goodbye) {
          try {
            transport.close();
          } catch (ignore) {/* my be already closed */}
        }
      },
      cancelOnError: true,
      onError: (error) => transport.onDisconnect?.complete(error),
      onDone: () => transport.onDisconnect?.complete()
    );
    return welcomeCompleter.future;
  }

  bool isConnected() {
    return this._transport != null && this._transport.isOpen && this._openSessionStreamController != null && !this._openSessionStreamController.isClosed;
  }

  authenticate(Authenticate authenticate) {
    this._transport.send(authenticate);
  }

  Stream<Result> call(String procedure,
      {List<Object> arguments,
      Map<String, Object> argumentsKeywords,
      CallOptions options,
      Completer<String> cancelCompleter}) async* {
    Call call = new Call(nextCallId++, procedure,
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
        options: options);
    this._transport.send(call);
    if (cancelCompleter != null) {
      cancelCompleter.future.then((cancelMode) {
        CancelOptions options = null;
        if (
          cancelMode != null && (
              CancelOptions.MODE_KILL_NO_WAIT == cancelMode ||
              CancelOptions.MODE_KILL == cancelMode ||
              CancelOptions.MODE_SKIP == cancelMode
          )
        ) {
          options = new CancelOptions();
          options.mode = cancelMode;
        }
        Cancel cancel = new Cancel(call.requestId, options: options);
        this._transport.send(cancel);
      });
    }
    await for(AbstractMessageWithPayload result in this._openSessionStreamController.stream.where(
            (message) => (message is Result && message.callRequestId == call.requestId) ||
            (message is Error && message.requestTypeId == MessageTypes.CODE_CALL && message.requestId == call.requestId)
    )) {
      if (result is Result) {
        yield result;
      } else if (result is Error) {
        throw result;
      }
    }
  }

  /**
   * The events are passed to the {@see Subscribed#events subject}
   */
  Future<Subscribed> subscribe(String topic, {SubscribeOptions options}) async {
    Subscribe subscribe = new Subscribe(nextSubscribeId++, topic, options: options);
    this._transport.send(subscribe);
    AbstractMessage subscribed = await this._openSessionStreamController.stream.where(
      (message) => (message is Subscribed && message.subscribeRequestId == subscribe.requestId) ||
        (message is Error && message.requestTypeId == MessageTypes.CODE_SUBSCRIBE && message.requestId == subscribe.requestId)
    ).first;
    if (subscribed is Subscribed) {
      subscriptions[subscribed.subscriptionId] = subscribed;
      subscribed.eventStream = this._openSessionStreamController.stream.where(
        (message) => message is Event && subscriptions[subscribed.subscriptionId] != null && message.subscriptionId == subscribed.subscriptionId
      ).cast();
      return subscribed;
    } else throw subscribed as Error;
  }

  Future<void> unsubscribe(int subscriptionId) async {
    Unsubscribe unsubscribe = new Unsubscribe(nextUnsubscribeId++, subscriptionId);
    this._transport.send(unsubscribe);
    await this._openSessionStreamController.stream.where(
      (message) {
        if (message is Unsubscribed && message.unsubscribeRequestId == unsubscribe.requestId) {
          return true;
        }
        if (message is Error && message.requestTypeId == MessageTypes.CODE_UNSUBSCRIBE && message.requestId == unsubscribe.requestId) {
          throw message;
        }
        return false;
      }
    ).first;
    subscriptions.remove(subscriptionId);
  }

  Future<Published> publish(String topic,
      {List<Object> arguments,
      Map<String, Object> argumentsKeywords,
      PublishOptions options}) {
    Publish publish = new Publish(nextPublishId++, topic,
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
        options: options);
    this._transport.send(publish);
    return this._openSessionStreamController.stream.where(
      (message) {
        if (message is Published && message.publishRequestId == publish.requestId) {
          return true;
        }
        if (message is Error && message.requestTypeId == MessageTypes.CODE_PUBLISH && message.requestId == publish.requestId) {
          throw message;
        }
        return false;
      }).first;
  }

  Future<Registered> register(String procedure, {RegisterOptions options}) async {
    Register register = new Register(nextRegisterId++, procedure, options: options);
    this._transport.send(register);
    AbstractMessage registered = await this._openSessionStreamController.stream.where(
            (message) => (message is Registered && message.registerRequestId == register.requestId) ||
            (message is Error && message.requestTypeId == MessageTypes.CODE_REGISTER && message.requestId == register.requestId)
    ).first;
    if (registered is Registered) {
      registrations[registered.registrationId] = registered;
      registered.procedure = procedure;
      registered.invocationStream = this._openSessionStreamController.stream.where(
        (message) {
          if (message is Invocation && message.registrationId == registered.registrationId) {
            // Check if there is a registration that has not been unregistered yet
            if (registrations[registered.registrationId] != null) {
              message.onResponse((message) => this._transport.send(message));
              return true;
            } else {
              this._transport.send(new Error(MessageTypes.CODE_INVOCATION, message.requestId, {}, Error.NO_SUCH_REGISTRATION));
              return false;
            }
          }
          return false;
        }
      ).cast();
      return registered;
    } else throw registered as Error;
  }

  Future<void> unregister(int registrationId) async {
    Unregister unregister = new Unregister(nextUnregisterId++, registrationId);
    this._transport.send(unregister);
    await this._openSessionStreamController.stream.where(
        (message) {
          if (message is Unregistered && message.unregisterRequestId == unregister.requestId) {
            return true;
          }
          if (message is Error && message.requestTypeId == MessageTypes.CODE_UNREGISTER && message.requestId == unregister.requestId) {
            throw message;
          }
          return false;
        }
    ).first;
    registrations.remove(registrationId);
  }

  void setInvocationTransportChannel(Invocation message) {
    message.onResponse((AbstractMessageWithPayload invocationResultMessage) {
      _transport.send(invocationResultMessage);
    });
  }
}
