import 'package:card_loading/card_loading.dart';
import 'package:flutter/material.dart';
import 'package:moollama/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moollama/settings_page.dart';
import 'package:cactus/cactus.dart';
import 'package:moollama/utils.dart';
import 'package:siri_wave/siri_wave.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:talker_flutter/talker_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:moollama/agent_helper.dart';

import 'package:multi_select_flutter/multi_select_flutter.dart';
import 'package:shake/shake.dart';
import 'package:feedback/feedback.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:moollama/models.dart';
import 'package:moollama/widgets/bottom_bar_button.dart';
import 'package:moollama/widgets/agent_item.dart';
import 'package:moollama/widgets/agent_settings_drawer_content.dart';
import 'package:blur/blur.dart';
import 'package:flutter_tts/flutter_tts.dart';

final talker = TalkerFlutter.init();

class SecretAgentHome extends StatefulWidget {
  final ValueNotifier<ThemeMode> themeNotifier;
  final Talker talker;

  const SecretAgentHome({super.key, required this.themeNotifier, required this.talker});

  @override
  State<SecretAgentHome> createState() => _SecretAgentHomeState();
}

class _SecretAgentHomeState extends State<SecretAgentHome> {
  final TextEditingController _textController = TextEditingController();
  final List<Message> _messages = [];
  final DatabaseHelper _dbHelper = DatabaseHelper();
  late Future<List<Message>> _messagesFuture;
  List<Agent> _agents = [];
  Agent? _selectedAgent;
  String _selectedModelName = 'Qwen3 0.6B'; // New field for selected model name
  double _creativity = 70.0;
  int _contextWindowSize = 8192;
  bool _isLoading = true;
  CactusAgent? _agent;
  double? _downloadProgress;
  double? _initializationProgress;
  String _downloadStatus = 'Initializing...';
  final ScrollController _scrollController = ScrollController();
  bool _isListening = false;
  OverlayEntry? _listeningPopupEntry;
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  String _lastWords = '';
  String _systemPrompt = ''; // New field for system prompt
  late ShakeDetector _shakeDetector;
  late FlutterTts _flutterTts;
  bool _isTtsEnabled = false;

  void _handleAgentLongPress(Agent agent) async {
    if (_agents.length == 1) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Cannot Delete Last Agent'),
            content: const Text('You cannot delete the last remaining agent.'),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    } else {
      _deleteAgent(agent); // Call the existing delete logic
    }
  }

  void _showListeningPopup(BuildContext context) async {
    _listeningPopupEntry = OverlayEntry(
      builder: (context) => Center(
        child: Card(
          color: Theme.of(context).dialogBackgroundColor, // Use dialog background color
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SiriWaveform.ios9(),
                const SizedBox(height: 10),
                Text(
                  _lastWords.isEmpty ? 'Listening...' : _lastWords,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_listeningPopupEntry!);
    setState(() {
      _isListening = true;
      _lastWords = '';
    });

    if (_speechToText.isAvailable) {
      await _speechToText.listen(
        onResult: (result) {
          setState(() {
            _lastWords = result.recognizedWords;
          });
          _listeningPopupEntry?.markNeedsBuild();
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        listenOptions: stt.SpeechListenOptions(partialResults: true),
      );
    } else {
      widget.talker.info('Speech recognition not available');
    }
  }

  void _hideListeningPopup() {
    _speechToText.stop();
    _listeningPopupEntry?.remove();
    _listeningPopupEntry = null;
    setState(() {
      _isListening = false;
      _lastWords = '';
    });
  }

  Future<void> _loadTtsSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isTtsEnabled = prefs.getBool('isTtsEnabled') ?? false;
    });
  }

  Future<void> _setTtsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isTtsEnabled', enabled);
    setState(() {
      _isTtsEnabled = enabled;
    });
  }

  @override
  void initState() {
    super.initState();
    _messagesFuture = Future.value([]); // Initialize with an empty future
    _loadAgents(); // Load agents, which will then load messages
    _speechToText.initialize(
      onStatus: (status) => widget.talker.info('Speech recognition status: $status'),
      onError: (errorNotification) =>
          widget.talker.info('Speech recognition error: $errorNotification'),
    );

    _flutterTts = FlutterTts();
    _loadTtsSetting(); // Load TTS setting from SharedPreferences

    _shakeDetector = ShakeDetector.autoStart(
      onPhoneShake: () async {
        // Show feedback UI
        BetterFeedback.of(context).show(
          (feedback) async {
            // Save the screenshot to a temporary file
            final directory = await getTemporaryDirectory();
            final file = File('${directory.path}/feedback_screenshot.png');
            await file.writeAsBytes(feedback.screenshot);

            widget.talker.info('Feedback saved to: ${file.path}');
            widget.talker.info('Feedback text: ${feedback.text}');
            // In a real app, you would send this feedback to a backend service.
            try {
              final result = await Share.shareXFiles([XFile(file.path)], text: feedback.text);
              if (result.status == ShareResultStatus.unavailable) {
                widget.talker.warning('Sharing is unavailable on this device.');
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sharing is not available on this device.'),
                  ),
                );
              }
            } catch (e, s) {
              widget.talker.error('Error sharing feedback', e, s);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Could not share feedback.'),
                ),
              );
            }
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _shakeDetector.stopListening(); // Changed from stop() to stopListening()
    super.dispose();
  }

  // Removed duplicate and unreferenced _initializeCactusModel method

  Future<void> _initializeCactusModel(String modelName, {String? systemPrompt}) async {
    if (modelName.isEmpty) {
      widget.talker.warning('Attempted to initialize Cactus model with empty modelName.');
      setState(() {
        _isLoading = false;
        _downloadStatus = 'No model selected or available.';
      });
      return;
    }
    try {
      setState(() {
        _isLoading = true;
        _downloadProgress = null;
        _initializationProgress = null; // Reset initialization progress
        _downloadStatus = 'Downloading model...';
      });
      _agent = CactusAgent();
      final models = await _dbHelper.getModels();
      final model = models.firstWhere(
        (m) => m['name'] == modelName,
        orElse: () => <String, dynamic>{},
      );
      final modelUrl = model['url'];
      if (modelUrl == null || modelUrl.isEmpty) { // Added check for empty modelUrl
        widget.talker.error('Model URL not found or empty for $modelName');
        throw Exception('Model URL not found or empty for $modelName');
      }
      await _agent!.download(
        modelUrl: modelUrl,
        onProgress: (progress, statusMessage, isError) {
          setState(() {
            _downloadProgress = progress;
            _downloadStatus = statusMessage;
            if (isError) {
              _downloadStatus = 'Error: $statusMessage';
            }
          });
        },
      );
      // After download, start initialization
      setState(() {
        _downloadProgress = null; // Clear download progress
        _initializationProgress = 0.0; // Start initialization progress
        _downloadStatus = 'Initializing model...';
      });
      await _agent!.init(
        contextSize: _contextWindowSize,
        gpuLayers: 99, // Offload all possible layers to GPU
        onProgress: (progress, statusMessage, isError) {
          setState(() {
            _initializationProgress =
                progress; // Update initialization progress
            _downloadStatus = statusMessage;
            if (isError) {
              _downloadStatus = 'Error: $statusMessage';
            }
          });
        },
      );
      // This part is fine, as _agent is checked for null before addAgentTools
      if (_agent != null) {
        final prefs = await SharedPreferences.getInstance();
        final selectedTools = prefs.getStringList('selectedTools') ?? [];
        addAgentTools(_agent!, selectedTools);
      }
      setState(() {
        _isLoading = false;
        _downloadProgress = null; // Ensure download progress is null
        _initializationProgress = 1.0; // Set to 1.0 after successful init
        _downloadStatus = 'Model initialized';
      });
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Error'),
            content: Text('Error initializing Cactus model: $e'),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      setState(() {
        _isLoading = false;
        _downloadProgress = null;
        _initializationProgress =
            null; // Reset initialization progress on error
        _downloadStatus = 'Initialization failed';
      });
    }
  }

  Future<void> _loadAgents() async {
    final prefs = await SharedPreferences.getInstance();
    final hasLaunchedBefore = prefs.getBool('has_launched_before') ?? false;

    if (!hasLaunchedBefore) {
      // First time launch
      await prefs.setBool('has_launched_before', true);
      final bool? downloadConfirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Download Model'),
            content: const Text(
                'This is the first time you are opening the app. Do you want to download the AI model now? This may take some time and data.'),
            actions: <Widget>[
              TextButton(
                child: const Text('No'),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
              TextButton(
                child: const Text('Yes'),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      );

      if (downloadConfirmed == true) {
        await _performAgentLoadingAndInitialization();
      } else {
        setState(() {
          _isLoading = false;
          _downloadStatus = 'Model not downloaded.';
        });
      }
    } else {
      // Not first time launch, proceed as usual
      await _performAgentLoadingAndInitialization();
    }
  }

  Future<void> _performAgentLoadingAndInitialization() async {
    final modelsInDb = await _dbHelper.getModels();
    if (modelsInDb.isEmpty) {
      // Insert default models if none exist
      await _dbHelper.insertModel({
        'name': 'Qwen3 0.6B',
        'url': 'https://huggingface.co/Cactus-Compute/Qwen3-600m-Instruct-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf'
      });
      await _dbHelper.insertModel({
        'name': 'Qwen3 1.7B',
        'url': 'https://huggingface.co/Cactus-Compute/Qwen3-1.7B-Instruct-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf'
      });
      await _dbHelper.insertModel({
        'name': 'Qwen3 4B',
        'url': 'https://huggingface.co/Cactus-Compute/Qwen3-4B-Instruct-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf'
      });
    }

    final agentsFromDb = await _dbHelper.getAgents();
    if (agentsFromDb.isEmpty) {
      // Ensure at least one agent exists
      final defaultAgent = Agent(
        name: 'Default',
        modelName: _selectedModelName,
      );
      final id = await _dbHelper.insertAgent(defaultAgent.toMap());
      if (id != 0) { // Check if insertion was successful
        setState(() {
          _agents.add(
            Agent(id: id, name: 'Default', modelName: _selectedModelName),
          );
          _selectedAgent = _agents.first;
        });
      } else {
        widget.talker.error('Failed to insert default agent.');
        setState(() {
          _isLoading = false;
          _downloadStatus = 'Failed to load agents.';
          _selectedAgent = null; // Explicitly set to null if agent creation fails
        });
        return; // Exit if no agent can be created
      }
    } else {
      setState(() {
        _agents = agentsFromDb.map((map) => Agent.fromMap(map)).toList();
        _selectedAgent = _agents.first;
      });
    }
    // After agents are loaded and a default/selected agent is set, load messages
    _messagesFuture = _loadMessages();
    if (_selectedAgent != null) {
      final prefs = await SharedPreferences.getInstance();
      _systemPrompt = prefs.getString('systemPrompt_${_selectedAgent!.id}') ?? '';
      _initializeCactusModel(_selectedAgent!.modelName, systemPrompt: _systemPrompt);
    } else {
      // If _selectedAgent is still null here (e.g., if user skipped download and no agents existed)
      setState(() {
        _isLoading = false;
        _downloadStatus = 'No agent available. Please add one.';
      });
    }
  }

  Future<List<Message>> _loadMessages() async {
    if (_selectedAgent == null || _selectedAgent!.id == null) {
      return [];
    }
    final List<Map<String, dynamic>> maps = await _dbHelper.getMessages(
      _selectedAgent!.id!,
    );
    setState(() {
      _messages.clear();
      _messages.addAll(
        maps.map((map) {
          final bool isUser = map['is_user'] == 1;
          if (isUser) {
            return Message(finalText: map['text'], isUser: true);
          } else {
            final ThinkingModelResponse parsedResponse =
                splitContentByThinkTags(map['text']);
            final String? thinkingText =
                parsedResponse.thinkingSessions.isNotEmpty
                    ? parsedResponse.thinkingSessions.join('\n')
                    : null;
            final List<String> toolCalls = [];
            final String finalText = extractResponseFromJson(
              parsedResponse.finalOutput,
            );
            return Message(
              rawText: map['text'],
              thinkingText: thinkingText,
              toolCalls: toolCalls,
              finalText: finalText,
              isUser: false,
            );
          }
        }),
      );
    });
    return _messages; // Return List<Message>
  }

  void _sendMessage() async {
    if (_textController.text.isNotEmpty &&
        _selectedAgent != null &&
        _selectedAgent!.id != null) {
      final userMessageText = _textController.text;
      _dbHelper.insertMessage(
        _selectedAgent!.id!,
        userMessageText,
        true, // isUser: true
      ); 
      setState(() {
        _messages.add(Message(finalText: userMessageText, isUser: true));
        _messages.add(Message(finalText: '', isUser: false, isLoading: true));
        _textController.clear();
      });
      _scrollToBottom();

      // Generate response using CactusLM
      if (_agent != null) {
        final List<ChatMessage> messages = [];
        if (_systemPrompt.isNotEmpty) {
          messages.add(ChatMessage(role: 'system', content: _systemPrompt));
        }
        messages.addAll(_messages.where((msg) => !msg.isLoading).map((msg) {
          return ChatMessage(
            role: msg.isUser ? 'user' : 'assistant',
            content: msg.finalText,
          );
        }).toList());
        final response = await _agent!.completionWithTools(
          messages,
          maxTokens: 2048,
          temperature: _creativity / 100.0,
        );
        widget.talker.info(
          'Response result: ${response.result}, tool calls: ${response.toolCalls}',
        );
        final ThinkingModelResponse parsedResponse = splitContentByThinkTags(
          response.result ?? '',
        );

        final String? thinkingText = parsedResponse.thinkingSessions.isNotEmpty
            ? parsedResponse.thinkingSessions.join('\n')
            : null;

        final List<String> toolCalls = response.toolCalls ?? [];

        final String finalText = extractResponseFromJson(
          parsedResponse.finalOutput,
        );

        // Store the combined message in the database
        _dbHelper.insertMessage(
          _selectedAgent!.id!,
          response.result ?? '',
          false, // isUser: false
        );

        setState(() {
          _messages.removeLast();
          _messages.add(
            Message(
              rawText: response.result ?? '',
              thinkingText: thinkingText,
              toolCalls: toolCalls,
              finalText: finalText,
              isUser: false,
            ),
          );
        });
        _scrollToBottom();

        if (_isTtsEnabled && finalText.isNotEmpty) {
          _flutterTts.speak(finalText);
        }
      }
    }
  }

  void _resetChat() async {
    if (_selectedAgent != null && _selectedAgent!.id != null) {
      await _dbHelper.clearMessages(_selectedAgent!.id!);
      setState(() {
        _messages.clear();
      });
      // Dispose and re-initialize the agent
      _agent?.unload();
      _initializeCactusModel(_selectedAgent!.modelName, systemPrompt: _systemPrompt); // Removed redundant check
    }
  }

  void _renameAgent(int index, String newName) async {
    final agentToRename = _agents[index];
    agentToRename.name = newName;
    await _dbHelper.updateAgent(agentToRename.toMap());
    setState(() {
      _agents[index] = agentToRename;
    });
  }

  void _deleteAgent(Agent agentToDelete) async {
    if (agentToDelete.id == null) return;

    if (_agents.length == 1) {
      // If it's the last agent, show a message and disable deletion
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Cannot Delete Last Agent'),
            content: const Text('You cannot delete the last remaining agent.'),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
      return; // Exit the function
    }

    // Show confirmation dialog
    final bool confirmDelete =
        await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Delete Agent'),
              content: Text(
                'Are you sure you want to delete agent "${agentToDelete.name}"?',
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop(false); // User cancelled
                  },
                ),
                TextButton(
                  child: const Text('Delete'),
                  onPressed: () {
                    Navigator.of(context).pop(true); // User confirmed
                  },
                ),
              ],
            );
          },
        ) ??
        false; // Default to false if dialog is dismissed

    if (confirmDelete) {
      await _dbHelper.deleteAgent(agentToDelete.id!);
      setState(() {
        _agents.removeWhere((agent) => agent.id == agentToDelete.id);
        // If the deleted agent was the selected one, select the first available agent
        if (_selectedAgent?.id == agentToDelete.id) {
          _selectedAgent = _agents.isNotEmpty ? _agents.first : null;
          _messages.clear(); // Clear messages for the deleted agent
          if (_selectedAgent != null) {
            _messagesFuture =
                _loadMessages(); // Load messages for the new selected agent
            _initializeCactusModel(
              _selectedAgent!.modelName,
            ); // Initialize model for new selected agent
          }
        }
      });
    }
  }

  Future<void> _showRenameDialog(BuildContext context, Agent agent) async {
    final TextEditingController renameController = TextEditingController(
      text: agent.name,
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Rename Agent'),
          content: TextField(
            controller: renameController,
            decoration: const InputDecoration(hintText: "Enter new agent name"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Rename'),
              onPressed: () {
                Navigator.of(context).pop(renameController.text);
              },
            ),
          ],
        );
      },
    );

    if (newName != null && newName.isNotEmpty) {
      // Find the index of the agent in the _agents list
      final index = _agents.indexOf(agent);
      if (index != -1) {
        _renameAgent(index, newName);
      }
    }
  }

  void _debugAction() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TalkerScreen(
          talker: widget.talker,
          theme: TalkerScreenTheme(
            cardColor: Theme.of(context).cardColor,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            textColor:
                Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
          ),
        ),
      ),
    );
  }

  void _showAddAgentDialog(BuildContext context) async {
    final TextEditingController addAgentController = TextEditingController();
    final newAgentName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add New Agent'),
          content: TextField(
            controller: addAgentController,
            decoration: const InputDecoration(hintText: "Enter new agent name"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Add'),
              onPressed: () {
                Navigator.of(context).pop(addAgentController.text);
              },
            ),
          ],
        );
      },
    );

    if (newAgentName != null && newAgentName.isNotEmpty) {
      _addAgent(newAgentName, _selectedModelName);
    }
  }

  void _addAgent(String name, String modelName) async {
    final newAgent = Agent(name: name, modelName: modelName);
    final id = await _dbHelper.insertAgent(newAgent.toMap());
    setState(() {
      _agents.add(Agent(id: id, name: name, modelName: modelName));
    });
  }

  void _selectAgent(Agent agent) {
    setState(() {
      _selectedAgent = agent;
      _messagesFuture = _loadMessages(); // Reload messages for the new agent
    });
    _initializeCactusModel(
      _selectedAgent!.modelName, systemPrompt: _systemPrompt,
    ); // Initialize model for the new agent
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _showCactusModelInfo(BuildContext context) {
    Scaffold.of(context).openEndDrawer();
  }

  void _showRawResponseDialog(String? rawText) {
    if (rawText == null) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Raw Response'),
          content: SingleChildScrollView(child: Text(rawText)),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showAttachmentOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  // Implement take photo functionality
                  widget.talker.info('Take Photo selected');
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  // Implement choose from gallery functionality
                  widget.talker.info('Choose from Gallery selected');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  const DrawerHeader(
                    child: Text('Agents', style: TextStyle(fontSize: 24)),
                  ),
                  ..._agents.asMap().entries.map((entry) {
                    Agent agent = entry.value;
                    return AgentItem(
                      agent: agent,
                      onRename: () => _showRenameDialog(context, agent),
                      onTap: () => _selectAgent(agent),
                      onLongPress: () => _handleAgentLongPress(
                        agent,
                      ), // Always call the handler
                    );
                  }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      _showAddAgentDialog(context);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              SettingsPage(agentId: _selectedAgent?.id, talker: widget.talker), // Pass talker
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      endDrawer: AgentSettingsDrawerContent(
        initialModelName: _selectedModelName,
        initialCreativity: _creativity,
        initialContextWindowSize: _contextWindowSize,
        initialSystemPrompt: _systemPrompt, // Pass system prompt
        initialIsTtsEnabled: _isTtsEnabled, // Pass TTS setting
        onApply: (modelName, creativity, contextWindowSize, selectedTools, systemPrompt, isTtsEnabled) async {
          bool needsReinitialization =
              _selectedModelName != modelName ||
              _contextWindowSize != contextWindowSize;

          setState(() {
            _selectedModelName = modelName;
            _creativity = creativity;
            _contextWindowSize = contextWindowSize;
            _systemPrompt = systemPrompt; // Update _systemPrompt
            _isTtsEnabled = isTtsEnabled; // Update _isTtsEnabled
            if (_selectedAgent != null) {
              _selectedAgent!.modelName = modelName;
              _dbHelper.updateAgent(_selectedAgent!.toMap());
            }
          });

          // Save system prompt to SharedPreferences
          if (_selectedAgent != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('systemPrompt_${_selectedAgent!.id}', systemPrompt);
          }
          // Save TTS setting to SharedPreferences
          await _setTtsEnabled(isTtsEnabled);

          if (needsReinitialization) {
            _initializeCactusModel(modelName, systemPrompt: systemPrompt);
          }
          // Re-initialize agent with new settings
          if (_agent != null) {
            _agent!.unload(); // Unload current agent
            _initializeCactusModel(modelName, systemPrompt: systemPrompt); // Re-initialize with new settings
          }
        },
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                    children: [
                      // Hamburger menu
                      Builder(
                        builder: (context) {
                          return IconButton(
                            icon: const Icon(Icons.menu),
                            onPressed: () {
                              Scaffold.of(context).openDrawer();
                            },
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      // App name
                      Text(
                        _selectedAgent?.name ?? 'Secret Agent',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      Builder(
                        builder: (BuildContext innerContext) {
                          return IconButton(
                            icon: const Icon(Icons.smart_toy_outlined),
                            onPressed: () {
                              _showCactusModelInfo(innerContext);
                            },
                          );
                        },
                      ),
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: widget.themeNotifier,
                        builder: (context, currentMode, child) {
                          return DropdownButton<ThemeMode>(
                            underline: const SizedBox(),
                            icon: const SizedBox.shrink(),
                            value: currentMode,
                            onChanged: (ThemeMode? newValue) {
                              if (newValue != null) {
                                widget.themeNotifier.value = newValue;
                              }
                            },
                            items: const [
                              DropdownMenuItem(
                                value: ThemeMode.light,
                                child: Icon(Icons.light_mode),
                              ),
                              DropdownMenuItem(
                                value: ThemeMode.dark,
                                child: Icon(Icons.dark_mode),
                              ),
                              DropdownMenuItem(
                                value: ThemeMode.system,
                                child: Icon(Icons.brightness_auto),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onLongPressStart: (_) => _showListeningPopup(context),
                    onLongPressEnd: (_) {
                      final transcript = _lastWords;
                      _hideListeningPopup();
                      if (transcript.isNotEmpty) {
                        _textController.text = transcript;
                        _sendMessage();
                      }
                    },
                    child: Container( // Wrap with Container to fill available space
                      color: Colors.transparent, // Make it transparent so content below is visible
                      child: _isLoading
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 16),
                                  if (_initializationProgress != null)
                                    Column(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 32.0,
                                          ),
                                          child: LinearProgressIndicator(
                                            value: _initializationProgress,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${(_initializationProgress! * 100).toInt()}% Initializing...',
                                          style: Theme.of(context).textTheme.bodyMedium,
                                        ),
                                      ],
                                    )
                                  else if (_downloadProgress != null)
                                    Column(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 32.0,
                                          ),
                                          child: LinearProgressIndicator(
                                            value: _downloadProgress,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${(_downloadProgress! * 100).toInt()}% Downloading...',
                                          style: Theme.of(context).textTheme.bodyMedium,
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 8),
                                  Text(_downloadStatus),
                                ],
                              ),
                            )
                          : _selectedAgent == null
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'No agent selected.',
                                        style: Theme.of(context).textTheme.headlineSmall,
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton(
                                        onPressed: () {
                                          Scaffold.of(context).openDrawer(); // Open drawer to add agent
                                        },
                                        child: const Text('Add Agent'),
                                      ),
                                    ],
                                  ),
                                )
                              : FutureBuilder<List<Message>>(
                              future: _messagesFuture,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                } else if (snapshot.hasError) {
                                  return Center(
                                    child: Text('Error: ${snapshot.error}'),
                                  );
                                } else if (_messages.isEmpty) {
                                  return Center(
                                    child: Text(
                                      'Hello!',
                                      style: TextStyle(
                                        color: Colors.blue[400],
                                        fontSize: 32,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                } else {
                                  return ListView.builder(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.all(8.0),
                                    itemCount: _messages.length,
                                    itemBuilder: (context, index) {
                                      return _buildMessageBubble(_messages[index]);
                                    },
                                  );
                                }
                              },
                            ),
                    ),
                  ),
                ),
                // Bottom bar
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: 16.0,
                    left: 12.0,
                    right: 12.0,
                    top: 8.0,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[800]!
                            : Colors.grey[300]!,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                minLines: 1,
                                maxLines: 6, // Allow up to 6 lines before scrolling
                                textInputAction: TextInputAction.send,
                                keyboardType: TextInputType.multiline, // Enable multiline keyboard
                                decoration: InputDecoration(
                                  hintText: 'Ask Secret Agent',
                                  hintStyle: TextStyle(
                                    color: Theme.of(context).hintColor,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 0,
                                  ),
                                ),
                                style: TextStyle(
                                  color: Theme.of(context).textTheme.bodyLarge?.color,
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            
                            BottomBarButton(
                              icon: Icons.attach_file,
                              onPressed: () {
                                _showAttachmentOptions(context);
                              },
                            ),
                            const SizedBox(width: 8),
                            BottomBarButton(
                              icon: Icons.refresh,
                              onPressed: _resetChat,
                            ),
                            const SizedBox(width: 8),
                            BottomBarButton(
                              icon: Icons.rocket_launch,
                              onPressed: _sendMessage,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isListening)
            Positioned.fill(
              child: Blur(
                blur: 10.0,
                blurColor: Theme.of(context).dialogBackgroundColor.withOpacity(0.7),
                child: Container(), // Add an empty Container as a child
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    if (message.isLoading) {
      return Align(
        alignment: Alignment.centerLeft,
        child: const CardLoading(
          height: 50,
          width: 150,
          borderRadius: BorderRadius.all(Radius.circular(20)),
          margin: EdgeInsets.symmetric(vertical: 4.0),
        ),
      );
    }

    final alignment = message.isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final color = message.isUser
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceVariant;
    final textColor = message.isUser
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return GestureDetector(
      onDoubleTap: () {
        if (!message.isUser) {
          _showRawResponseDialog(message.rawText);
        }
      },
      child: Align(
        alignment: alignment,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.thinkingText != null &&
                  message.thinkingText!.isNotEmpty)
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text(
                      '🤔 Thinking...', // Corrected: Removed extra backslash before 🤔
                      style: TextStyle(color: textColor),
                    ),
                    initiallyExpanded: false,
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        message.thinkingText!,
                        style: TextStyle(color: textColor),
                      ),
                    ],
                  ),
                ),
              if (message.toolCalls != null && message.toolCalls!.isNotEmpty)
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text(
                      '🛠️ Tool Calls',
                      style: TextStyle(color: textColor),
                    ),
                    initiallyExpanded: false,
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Align(
                        alignment: Alignment.topLeft,
                        child: Wrap(
                          alignment:
                              WrapAlignment.start,
                          spacing: 8.0,
                          runSpacing: 4.0,
                          children: message.toolCalls!
                              .map(
                                (toolCall) => Chip(
                                  label: Text(toolCall),
                                  backgroundColor: Colors.blueGrey[100],
                                  labelStyle: TextStyle(color: Colors.black),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(message.finalText, style: TextStyle(color: textColor)),
            ],
          ),
        ),
      ),
    );
  }
}
