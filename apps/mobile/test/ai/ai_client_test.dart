import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';

import '../fakes.dart';

void main() {
  group('ProtocolRoutingAiClient', () {
    test('protocol: null dispatches to the anthropic client only', () async {
      final anthropic = FakeAiClient(response: 'from anthropic');
      final openAi = FakeAiClient(response: 'from openai');
      final router =
          ProtocolRoutingAiClient(anthropicClient: anthropic, openAiClient: openAi);

      const request = AiRequest(system: 's', userContent: 'u');
      final result = await router.sendMessage(request).toList();

      expect(result, ['from anthropic']);
      expect(anthropic.requests, [request]);
      expect(openAi.requests, isEmpty);
    });

    test('protocol: AiProtocol.anthropic dispatches to the anthropic client',
        () async {
      final anthropic = FakeAiClient(response: 'from anthropic');
      final openAi = FakeAiClient(response: 'from openai');
      final router =
          ProtocolRoutingAiClient(anthropicClient: anthropic, openAiClient: openAi);

      const request =
          AiRequest(system: 's', userContent: 'u', protocol: AiProtocol.anthropic);
      await router.sendMessage(request).toList();

      expect(anthropic.requests, [request]);
      expect(openAi.requests, isEmpty);
    });

    test('protocol: AiProtocol.openai dispatches to the openai client only',
        () async {
      final anthropic = FakeAiClient(response: 'from anthropic');
      final openAi = FakeAiClient(response: 'from openai');
      final router =
          ProtocolRoutingAiClient(anthropicClient: anthropic, openAiClient: openAi);

      const request =
          AiRequest(system: 's', userContent: 'u', protocol: AiProtocol.openai);
      final result = await router.sendMessage(request).toList();

      expect(result, ['from openai']);
      expect(openAi.requests, [request]);
      expect(anthropic.requests, isEmpty);
    });

    test('an error from the dispatched-to client streams through unchanged',
        () async {
      final anthropic = FakeAiClient();
      final openAi = FakeAiClient(error: const AiAuthException('bad key'));
      final router =
          ProtocolRoutingAiClient(anthropicClient: anthropic, openAiClient: openAi);

      const request =
          AiRequest(system: 's', userContent: 'u', protocol: AiProtocol.openai);

      await expectLater(
        router.sendMessage(request).toList(),
        throwsA(isA<AiAuthException>()),
      );
    });
  });
}
