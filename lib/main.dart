import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const PlantDiagnosisApp());
}

class PlantDiagnosisApp extends StatelessWidget {
  const PlantDiagnosisApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plant Disease Diagnosis',
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
  State<HomePage> createState() => HomePageState();  // Changed from _HomePageState
}

// Changed from _HomePageState to HomePageState (removed the underscore)
class HomePageState extends State<HomePage> {
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _diagnosisResult;
  String? _errorMessage;

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

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _getImage(ImageSource source) async {
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

  Future<void> _analyzePlantDisease() async {
    if (_imageFile == null) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      // Replace with your actual plant disease recognition API
      // This is a placeholder for demonstration purposes
      final Uri apiUrl = Uri.parse('https://api.plantdisease.example.com/diagnose');
      
      // Create a multipart request
      var request = http.MultipartRequest('POST', apiUrl);
      
      // Add the image file
      request.files.add(await http.MultipartFile.fromPath(
        'image',
        _imageFile!.path,
      ));

      // Send the request
      var response = await request.send();
      
      // Process the response
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var decodedData = json.decode(responseData);
        
        setState(() {
          _diagnosisResult = decodedData;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plant Disease Diagnosis'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
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
    // This is a mock display - you'll need to adapt this to your API's response structure
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
              'Confidence: ${(diagnosis['confidence'] * 100).toStringAsFixed(1)}%',
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
                  // Navigate to a detail page or show a dialog with more information
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