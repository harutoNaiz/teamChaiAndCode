enum ModelProvider {
  openRouter,
  googleGemini,
  localOnDevice,
}

class AIModelConfig {
  final String id;
  final String openRouterModelId;
  final String name;
  final String description;
  final ModelProvider provider;
  final bool isLocal;
  final String badge;

  const AIModelConfig({
    required this.id,
    required this.openRouterModelId,
    required this.name,
    required this.description,
    required this.provider,
    this.isLocal = false,
    this.badge = 'OpenRouter',
  });

  static const List<AIModelConfig> availableModels = [
    AIModelConfig(
      id: 'openrouter-deepseek-chat',
      openRouterModelId: 'openrouter/free',
      name: 'Free OpenRouter Router',
      description: 'Automatically chooses an available free model',
      provider: ModelProvider.openRouter,
      badge: 'OpenRouter',
    ),
    AIModelConfig(
      id: 'openrouter-llama-3.3-70b',
      openRouterModelId: 'meta-llama/llama-3.3-70b-instruct',
      name: 'Llama 3.3 70B (OpenRouter)',
      description: 'State-of-the-art open weight reasoning',
      provider: ModelProvider.openRouter,
      badge: 'OpenRouter',
    ),
    AIModelConfig(
      id: 'openrouter-gemini-flash',
      openRouterModelId: 'google/gemini-2.0-flash-exp:free',
      name: 'Gemini 2.0 Flash (Free OpenRouter)',
      description: 'Ultra fast multimodal agent model',
      provider: ModelProvider.openRouter,
      badge: 'Free OR',
    ),
    AIModelConfig(
      id: 'openrouter-claude-3.5-sonnet',
      openRouterModelId: 'anthropic/claude-3.5-sonnet',
      name: 'Claude 3.5 Sonnet (OpenRouter)',
      description: 'Industry-leading coding and tool-calling agent',
      provider: ModelProvider.openRouter,
      badge: 'OpenRouter',
    ),
    AIModelConfig(
      id: 'local-slm',
      openRouterModelId: '',
      name: 'On-Device iQOO SLM',
      description: 'Zero latency, 100% private on-device neural model',
      provider: ModelProvider.localOnDevice,
      isLocal: true,
      badge: 'Local NPU',
    ),
  ];
}
