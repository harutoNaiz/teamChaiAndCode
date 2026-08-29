enum ModelProvider {
  openRouter,
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
  final String? downloadUrl;
  final String? filename;

  const AIModelConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.provider,
    this.openRouterModelId = '',
    this.isLocal = false,
    this.badge = 'OpenRouter',
    this.downloadUrl,
    this.filename,
  });

  static const List<AIModelConfig> localModels = [
    AIModelConfig(
      id: 'litert-community/gemma-4-E4B-it-litert-lm',
      name: 'Gemma 4 E4B (LiteRT LM)',
      description: 'On-device open-source model optimized for mobile NPU via LiteRT',
      provider: ModelProvider.localOnDevice,
      isLocal: true,
      badge: 'Local LiteRT',
      downloadUrl: 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
      filename: 'gemma-4-E4B-it.litertlm',
    ),
  ];

  static const List<AIModelConfig> openRouterModels = [
    AIModelConfig(
      id: 'openrouter-deepseek-chat',
      openRouterModelId: 'deepseek/deepseek-chat',
      name: 'DeepSeek V3 (OpenRouter)',
      description: 'High performance open-weights reasoning model',
      provider: ModelProvider.openRouter,
      badge: 'OpenRouter',
    ),
    AIModelConfig(
      id: 'openrouter-llama-3.3-70b',
      openRouterModelId: 'meta-llama/llama-3.3-70b-instruct',
      name: 'Llama 3.3 70B (OpenRouter)',
      description: 'State-of-the-art open-source LLM by Meta',
      provider: ModelProvider.openRouter,
      badge: 'OpenRouter',
    ),
    AIModelConfig(
      id: 'openrouter-gemini-2-flash-free',
      openRouterModelId: 'google/gemini-2.0-flash-exp:free',
      name: 'Gemini 2.0 Flash (Free OpenRouter)',
      description: 'High speed, free multimodal intelligence tier',
      provider: ModelProvider.openRouter,
      badge: 'Free OR',
    ),
    AIModelConfig(
      id: 'openrouter-mistral-7b-free',
      openRouterModelId: 'mistralai/mistral-7b-instruct:free',
      name: 'Mistral 7B Instruct (Free OpenRouter)',
      description: 'Lightweight efficient European open model',
      provider: ModelProvider.openRouter,
      badge: 'Free OR',
    ),
    AIModelConfig(
      id: 'openrouter-qwen-72b',
      openRouterModelId: 'qwen/qwen-2.5-72b-instruct',
      name: 'Qwen 2.5 72B (OpenRouter)',
      description: 'Advanced open-weight multilingual reasoning',
      provider: ModelProvider.openRouter,
      badge: 'OpenRouter',
    ),
    AIModelConfig(
      id: 'openrouter-auto',
      openRouterModelId: 'openrouter/auto',
      name: 'OpenRouter Auto Router',
      description: 'Automatically routes queries to best available open model',
      provider: ModelProvider.openRouter,
      badge: 'OpenRouter',
    ),
  ];

  static List<AIModelConfig> get availableModels => [
        ...localModels,
        ...openRouterModels,
      ];
}
