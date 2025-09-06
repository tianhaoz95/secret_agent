import 'package:flutter/material.dart';
import 'package:moollama/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:restart_app/restart_app.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:file_picker/file_picker.dart';

class SettingsPage extends StatefulWidget {
  final int? agentId;
  final Talker talker;

  const SettingsPage({super.key, this.agentId, required this.talker});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<Map<String, dynamic>> _availableModels = []; // Changed type
  final DatabaseHelper _dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _loadAvailableModels();
  }

  Future<void> _loadAvailableModels() async {
    final models = await _dbHelper.getModels(); // Get all model data
    setState(() {
      _availableModels = models;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.bug_report_outlined),
                label: const Text('View Logs'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => TalkerScreen(
                        talker: widget.talker, // Use widget.talker
                        theme: TalkerScreenTheme(
                          cardColor: Theme.of(context).cardColor,
                          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                          textColor:
                              Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  _confirmAndDeletePreferences(context);
                },
                child: const Text('Delete All Preferences'),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  _confirmAndDeleteData(context);
                },
                child: const Text('Delete All Data'),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Model'),
                onPressed: () {
                  _showAddModelDialog(context);
                },
              ),
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 16),
            const Text('Manage Models', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded( // Use Expanded to allow ListView to take available space
              child: ListView.builder(
                itemCount: _availableModels.length,
                itemBuilder: (context, index) {
                  final model = _availableModels[index];
                  return ListTile(
                    title: Text(model['name']),
                    subtitle: Text(model['url']),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _confirmAndDeleteModel(context, model['id'], model['name']),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmAndDeletePreferences(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text('Are you sure you want to delete all preferences? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                Restart.restartApp();
                if (!context.mounted) return;
                Navigator.of(context).pop(); // Dismiss the dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All preferences deleted.')),
                );
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _confirmAndDeleteData(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text('Are you sure you want to delete all data? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final dbHelper = DatabaseHelper();
                await dbHelper.clearAllData(); // Call clearAllData()
                Restart.restartApp();
                if (!context.mounted) return;
                Navigator.of(context).pop(); // Dismiss the dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All data deleted.')),
                );
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _confirmAndDeleteModel(BuildContext context, int modelId, String modelName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete the model "$modelName"?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await _deleteModel(modelId);
                if (!context.mounted) return;
                Navigator.of(context).pop(); // Dismiss the dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Model "$modelName" deleted.')),
                );
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteModel(int modelId) async {
    await _dbHelper.deleteModel(modelId);
    _loadAvailableModels(); // Refresh the list after deletion
  }

  void _showAddModelDialog(BuildContext context) {
    final TextEditingController nicknameController = TextEditingController();
    final TextEditingController urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add New Model'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nicknameController,
                decoration: const InputDecoration(
                  labelText: 'Model Nickname',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Model URL',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async { // Make onPressed async
                    FilePickerResult? result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['gguf'],
                    );

                    if (result != null && result.files.single.path != null) {
                      urlController.text = result.files.single.path!;
                      // Optionally, set nickname based on file name
                      if (nicknameController.text.isEmpty) {
                        nicknameController.text = result.files.single.name.replaceAll('.gguf', '');
                      }
                    } else {
                      // User canceled the picker
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('File selection cancelled.')),
                      );
                    }
                  },
                  child: const Text('Select from Files'),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async { // Make onPressed async
                final String nickname = nicknameController.text;
                final String url = urlController.text;

                if (nickname.isEmpty || url.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nickname and URL cannot be empty.')),
                  );
                  return;
                }

                await _dbHelper.insertModel({'name': nickname, 'url': url});
                _loadAvailableModels(); // Refresh the list of available models
                if (!context.mounted) return;
                Navigator.of(context).pop(); // Dismiss the dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Model added successfully!')),
                );
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}
