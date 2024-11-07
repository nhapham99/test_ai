import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:opencv_dart/opencv.dart' as cv;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class Rect {
  int x;
  int y;
  int width;
  int height;

  Rect(this.x, this.y, this.width, this.height);
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  File? _image;
  List<Rect> _contours = [];
  Uint8List? _stitchedImage;
  int imageHeight = 0;
  int imageWidth = 0;

  Future<void> _pickImage() async {
    setState(() {
      _contours.clear();
    });

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
      _processImage(_image!);
    }
  }

  Future<void> _processImage(File imageFile) async {
    // Load image, grayscale, and apply Otsu's threshold
    final image = cv.imread(imageFile.path);
    final gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
    final blur = cv.medianBlur(gray, 5);
    final thresh =
        cv.threshold(blur, 0, 255, cv.THRESH_BINARY_INV + cv.THRESH_OTSU).$2;
    // Remove horizontal lines using morphological opening
    final lineKernel = cv.getStructuringElement(cv.MORPH_RECT, (20, 1));
    final linesRemoved =
        cv.morphologyEx(thresh, cv.MORPH_OPEN, lineKernel, iterations: 1);
    // Subtract horizontal line from image
    final textOnly = cv.subtract(thresh, linesRemoved);
    // Apply morphological opening to clean noise
    final openingKernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    final opening =
        cv.morphologyEx(textOnly, cv.MORPH_OPEN, openingKernel, iterations: 1);
    // Dilate to connect text elements
    final smallKernel = cv.getStructuringElement(cv.MORPH_RECT, (10, 30));
    final smallDilate = cv.dilate(opening, smallKernel, iterations: 1);

    final mediumKernel = cv.getStructuringElement(cv.MORPH_RECT, (30, 50));
    final mediumDilate = cv.dilate(smallDilate, mediumKernel, iterations: 1);

    final largeKernel = cv.getStructuringElement(cv.MORPH_RECT, (50, 70));
    final dilate = cv.dilate(mediumDilate, largeKernel, iterations: 1);
    // Remove remaining unwanted contours (e.g., specific shapes or areas)
    var cnts =
        cv.findContours(dilate, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE).$1;
    for (final c in cnts) {
      final area = cv.contourArea(c);
      final rect = cv.boundingRect(c);
      final ar = rect.width / rect.height;
      if (area > 10000 && area < 12500 && ar < 0.5) {
        cv.drawContours(
            dilate, cv.VecVecPoint.fromVecPoint(c), -1, cv.Scalar(0, 0, 0),
            thickness: -1);
      }
    }
    var finalKernelRect = (6, 6);
    var finalInterations = 5;

    if (cnts.length < 10) {
      finalKernelRect = (100, 100);
      finalInterations = 2;
    }

    // Additional dilation to enhance detected regions
    final finalKernel =
        cv.getStructuringElement(cv.MORPH_RECT, finalKernelRect);
    final finalDilate = cv.dilate(
      dilate,
      finalKernel,
      iterations: finalInterations,
    );

    // Draw bounding boxes around large contours
    final finalContours = cv
        .findContours(finalDilate, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE)
        .$1;
    // Calculate the center of the image
    final imageCenter = cv.Point(image.cols ~/ 2, image.rows ~/ 2);

    cv.Rect? biggestNearestRect;
    double maxArea = 0;
    double minDistance = double.infinity;

    for (final c in finalContours) {
      final area = cv.contourArea(c);
      if (area > 100000) {
        final rect = cv.boundingRect(c);
        final rectCenter =
            cv.Point(rect.x + rect.width ~/ 2, rect.y + rect.height ~/ 2);

        // Calculate Euclidean distance manually
        final dx = imageCenter.x - rectCenter.x;
        final dy = imageCenter.y - rectCenter.y;
        final distance = sqrt(dx * dx + dy * dy);

        // Check if this rectangle is bigger and closer than previously found
        if (area > maxArea && distance < minDistance) {
          maxArea = area;
          minDistance = distance;
          biggestNearestRect = rect;
        }
      }
    }

    // Draw the biggest and nearest center rectangle if found
    if (biggestNearestRect != null) {
      cv.rectangle(image, biggestNearestRect, cv.Scalar(36, 255, 12),
          thickness: 10);
    }

    final (success, byte) = cv.imencode(".png", image);

    setState(() {
      _stitchedImage = byte;
      imageHeight = image.rows;
      imageWidth = image.cols;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _stitchedImage == null
                ? Placeholder()
                : Image.memory(_stitchedImage!),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickImage,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
