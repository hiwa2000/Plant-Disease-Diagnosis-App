import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const PlantDiagnosisApp());
}

class PlantDiagnosisApp extends StatelessWidget {
  const PlantDiagnosisApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plant Disease Diagnosis',
      debugShowCheckedModeBanner: false,// This line hides the debug banner

      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _diagnosisResult;
  String? _errorMessage;
  String? _apiKey;
  final TextEditingController _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadApiKey();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKey = prefs.getString('plant_id_api_key');
      if (_apiKey != null) {
        _apiKeyController.text = _apiKey!;
      }
    });
  }

  Future<void> _saveApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plant_id_api_key', apiKey);
    setState(() {
      _apiKey = apiKey;
    });
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.storage,
    ].request();
    
    if (statuses[Permission.camera] != PermissionStatus.granted ||
        statuses[Permission.storage] != PermissionStatus.granted) {
      setState(() {
        _errorMessage = "Permissions are required to use the camera and access photos.";
      });
    }
  }

  Future<void> _getImage(ImageSource source) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      _showApiKeyDialog();
      return;
    }

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _diagnosisResult = null;
          _errorMessage = null;
        });
        
        _analyzePlantDisease();
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Error picking image: $e";
      });
    }
  }

  Future<void> _showApiKeyDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Plant.id API Key Required'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'To use this app, you need a Plant.id API key. You can get one by signing up at plant.id website.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _apiKeyController,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                if (_apiKeyController.text.isNotEmpty) {
                  _saveApiKey(_apiKeyController.text);
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _analyzePlantDisease() async {
    if (_imageFile == null || _apiKey == null || _apiKey!.isEmpty) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      // Convert image to base64
      List<int> imageBytes = await _imageFile!.readAsBytes();
      String base64Image = base64Encode(imageBytes);
      
      // Prepare request to Plant.id API
      final Uri apiUrl = Uri.parse('https://api.plant.id/v2/identify');
      
      // Create request body
      var requestBody = {
        'api_key': _apiKey,
        'images': [base64Image],
        'modifiers': ['crops_fast', 'similar_images', 'diseases'],
        'plant_details': ['common_names', 'url', 'description', 'taxonomy', 'wiki_description'],
        'disease_details': ['description', 'treatment', 'classification'],
      };

      // Send the request
      var response = await http.post(
        apiUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );
      
      // Process the response
      if (response.statusCode == 200) {
        var decodedData = json.decode(response.body);
        
        setState(() {
          _diagnosisResult = _processApiResponse(decodedData);
          _isAnalyzing = false;
        });
      } else {
        setState(() {
          _errorMessage = "Failed to analyze image. Status code: ${response.statusCode}";
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Error analyzing image: $e";
        _isAnalyzing = false;
      });
    }
  }

  // Helper function to process Plant.id API response
  Map<String, dynamic> _processApiResponse(Map<String, dynamic> apiResponse) {
    var result = <String, dynamic>{};
    
    try {
      if (apiResponse['suggestions'] != null && apiResponse['suggestions'].isNotEmpty) {
        var suggestion = apiResponse['suggestions'][0];
        
        // Basic plant info
        result['plantName'] = suggestion['plant_name'] ?? 'Unknown Plant';
        if (suggestion['plant_details'] != null && 
            suggestion['plant_details']['common_names'] != null && 
            suggestion['plant_details']['common_names'].isNotEmpty) {
          result['plantName'] = suggestion['plant_details']['common_names'][0];
        }
        
        result['confidence'] = suggestion['probability'] ?? 0.0;
        
        // Disease info
        if (suggestion['is_plant_disease'] == true && suggestion['disease_details'] != null) {
          result['diseaseName'] = suggestion['disease_details']['name'] ?? 'Unknown Disease';
          result['treatments'] = _extractTreatments(suggestion['disease_details']);
          result['moreInfo'] = suggestion['disease_details']['description'] ?? '';
        } else {
          // Check if there are any diseases listed
          final List diseaseList = apiResponse['health_assessment']?['diseases'] ?? [];
          if (diseaseList.isNotEmpty) {
            final disease = diseaseList[0];
            result['diseaseName'] = disease['name'] ?? 'Unknown Disease';
            result['confidence'] = disease['probability'] ?? 0.0;
            result['treatments'] = ['Keep the plant in a well-ventilated area', 
                                    'Ensure proper watering', 
                                    'Remove affected leaves',
                                    'Consider appropriate fungicides if the condition worsens'];
            result['moreInfo'] = disease['description'] ?? '';
          } else {
            result['diseaseName'] = 'No disease detected';
            result['treatments'] = ['Your plant appears healthy',
                                   'Continue regular care and monitoring'];
            result['moreInfo'] = 'No signs of disease were detected in this plant. Regular care includes proper watering, adequate sunlight, and occasional fertilization.';
          }
        }
      } else {
        result['plantName'] = 'Unknown Plant';
        result['diseaseName'] = 'Could not identify';
        result['confidence'] = 0.0;
        result['treatments'] = ['Try again with a clearer image',
                               'Ensure good lighting',
                               'Focus on affected areas of the plant'];
        result['moreInfo'] = 'The plant could not be identified. Try taking a photo with better lighting and a clearer view of the plant features.';
      }
    } catch (e) {
      print("Error processing API response: $e");
      result['plantName'] = 'Error in processing';
      result['diseaseName'] = 'Processing error';
      result['confidence'] = 0.0;
      result['treatments'] = ['Try again later'];
      result['moreInfo'] = 'There was an error processing the response from the identification service.';
    }
    
    return result;
  }

  List<String> _extractTreatments(Map<String, dynamic> diseaseDetails) {
    List<String> treatments = [];
    
    if (diseaseDetails['treatment'] != null) {
      if (diseaseDetails['treatment']['biological'] != null) {
        treatments.add('Biological: ${diseaseDetails['treatment']['biological']}');
      }
      
      if (diseaseDetails['treatment']['chemical'] != null) {
        treatments.add('Chemical: ${diseaseDetails['treatment']['chemical']}');
      }
      
      if (diseaseDetails['treatment']['prevention'] != null) {
        treatments.add('Prevention: ${diseaseDetails['treatment']['prevention']}');
      }
    }
    
    // Default treatments if none found
    if (treatments.isEmpty) {
      treatments = [
        'Isolate the affected plant',
        'Remove and destroy affected parts',
        'Ensure good air circulation',
        'Avoid overhead watering',
        'Consider appropriate fungicides or insecticides'
      ];
    }
    
    return treatments;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plant Disease Diagnosis'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showApiKeyDialog,
            tooltip: 'Set API Key',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Take or select a photo of your plant to diagnose diseases',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _getImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _getImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_imageFile != null) ...[
              Container(
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    _imageFile!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (_isAnalyzing) ...[
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.green),
                    SizedBox(height: 10),
                    Text('Analyzing plant image...'),
                  ],
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red[800]),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (_diagnosisResult != null) ...[
              DiagnosisResultCard(diagnosis: _diagnosisResult!),
            ],
          ],
        ),
      ),
    );
  }
}

class DiagnosisResultCard extends StatelessWidget {
  final Map<String, dynamic> diagnosis;
  
  const DiagnosisResultCard({Key? key, required this.diagnosis}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              diagnosis['plantName'] ?? 'Unknown Plant',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Disease: ${diagnosis['diseaseName'] ?? 'No disease detected'}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            Text(
              'Confidence: ${((diagnosis['confidence'] ?? 0.0) * 100).toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text(
              'Treatment Recommendations:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: diagnosis['treatments']?.length ?? 0,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(diagnosis['treatments'][index] ?? ''),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (diagnosis['moreInfo'] != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                icon: const Icon(Icons.info_outline),
                label: const Text('Learn More'),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(diagnosis['diseaseName'] ?? 'Disease Information'),
                      content: SingleChildScrollView(
                        child: Text(diagnosis['moreInfo']),
                      ),
                      actions: [
                        TextButton(
                          child: const Text('Close'),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}