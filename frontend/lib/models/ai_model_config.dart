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
  final bool isFree;
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
    this.isFree = true,
    this.badge = 'Free',
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
      isFree: true,
      badge: 'Local LiteRT',
      downloadUrl: 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
      filename: 'gemma-4-E4B-it.litertlm',
    ),
  ];

  static const List<AIModelConfig> defaultFreeOpenRouterModels = [
    AIModelConfig(
      id: 'openrouter-gemini-2-flash-free',
      openRouterModelId: 'google/gemini-2.0-flash-exp:free',
      name: 'Gemini 2.0 Flash (Free)',
      description: 'High speed multimodal reasoning tier on OpenRouter',
      provider: ModelProvider.openRouter,
      isFree: true,
      badge: 'Free Tier',
    ),
    AIModelConfig(
      id: 'openrouter-llama-3.3-70b-free',
      openRouterModelId: 'meta-llama/llama-3.3-70b-instruct:free',
      name: 'Llama 3.3 70B (Free)',
      description: 'Meta\'s state-of-the-art open flagship model',
      provider: ModelProvider.openRouter,
      isFree: true,
      badge: 'Free Tier',
    ),
    AIModelConfig(
      id: 'openrouter-deepseek-r1-free',
      openRouterModelId: 'deepseek/deepseek-r1:free',
      name: 'DeepSeek R1 (Free)',
      description: 'Advanced reasoning and mathematical logic model',
      provider: ModelProvider.openRouter,
      isFree: true,
      badge: 'Free Tier',
    ),
    AIModelConfig(
      id: 'openrouter-deepseek-chat-free',
      openRouterModelId: 'deepseek/deepseek-chat:free',
      name: 'DeepSeek V3 (Free)',
      description: 'High efficiency open-weights conversational intelligence',
      provider: ModelProvider.openRouter,
      isFree: true,
      badge: 'Free Tier',
    ),
    AIModelConfig(
      id: 'openrouter-mistral-7b-free',
      openRouterModelId: 'mistralai/mistral-7b-instruct:free',
      name: 'Mistral 7B Instruct (Free)',
      description: 'Fast, concise open weights model by Mistral AI',
      provider: ModelProvider.openRouter,
      isFree: true,
      badge: 'Free Tier',
    ),
    AIModelConfig(
      id: 'openrouter-qwen-72b-free',
      openRouterModelId: 'qwen/qwen-2.5-72b-instruct:free',
      name: 'Qwen 2.5 72B (Free)',
      description: 'State-of-the-art multilingual open-weights model',
      provider: ModelProvider.openRouter,
      isFree: true,
      badge: 'Free Tier',
    ),
    AIModelConfig(
      id: 'openrouter-llama-3.1-8b-free',
      openRouterModelId: 'meta-llama/llama-3.1-8b-instruct:free',
      name: 'Llama 3.1 8B (Free)',
      description: 'Lightweight high-speed general intelligence',
      provider: ModelProvider.openRouter,
      isFree: true,
      badge: 'Free Tier',
    ),
    AIModelConfig(
      id: 'openrouter-gemma-2-9b-free',
      openRouterModelId: 'google/gemma-2-9b-it:free',
      name: 'Gemma 2 9B IT (Free)',
      description: 'Google open weights lightweight instruction model',
      provider: ModelProvider.openRouter,
      isFree: true,
      badge: 'Free Tier',
    ),
  ];

  static List<AIModelConfig> availableModels = [
    ...localModels,
    ...defaultFreeOpenRouterModels,
  ];
}
