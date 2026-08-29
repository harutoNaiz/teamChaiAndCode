enum ModelProvider {
  localOnDevice,
  googleGemini,
  openRouter,
}

class AIModelConfig {
  final String id;
  final String name;
  final String description;
  final ModelProvider provider;
  final bool isLocal;
  final String badge;

  const AIModelConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.provider,
    this.isLocal = false,
    this.badge = 'Cloud',
  });

  static const List<AIModelConfig> availableModels = [
    AIModelConfig(
      id: 'local-slm',
      name: 'On-Device iQOO SLM',
      description: 'Zero latency, 100% private on-device neural model',
      provider: ModelProvider.localOnDevice,
      isLocal: true,
      badge: 'Local / NPU',
    ),
    AIModelConfig(
      id: 'gemini-1.5-flash',
      name: 'Gemini 1.5 Flash',
      description: 'Fast, high-intelligence multimodal agent model',
      provider: ModelProvider.googleGemini,
      isLocal: false,
      badge: 'Gemini',
    ),
    AIModelConfig(
      id: 'openrouter-auto',
      name: 'OpenRouter Smart Router',
      description: 'Model-agnostic routing across open weights & APIs',
      provider: ModelProvider.openRouter,
      isLocal: false,
      badge: 'OpenRouter',
    ),
  ];
}
