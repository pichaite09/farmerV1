class PushServiceStatus {
  final bool supported;
  final bool enabled;
  final String? endpoint;

  const PushServiceStatus({
    required this.supported,
    required this.enabled,
    this.endpoint,
  });
}

class PushSubscriptionPayload {
  final String endpoint;
  final String p256dh;
  final String auth;

  const PushSubscriptionPayload({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });

  Map<String, dynamic> toJson() => {
    'endpoint': endpoint,
    'keys': {'p256dh': p256dh, 'auth': auth},
  };
}
