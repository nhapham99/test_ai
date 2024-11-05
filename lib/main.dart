import 'dart:io';
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
    final mat = cv.imread(imageFile.path);

    final ratio = mat.width / MediaQuery.of(context).size.width;
    setState(() {
      imageHeight = (mat.height / ratio).toInt();
      imageWidth = MediaQuery.of(context).size.width.toInt();
    });

    final gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    final blur = cv.medianBlur(gray, 5);
    final thresh = cv.adaptiveThreshold(
        blur, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY_INV, 11, 14);

    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
    final dilate = cv.dilate(thresh, kernel, iterations: 50);
    final (success, bytes) = await cv.imencodeAsync(".png", dilate);

    setState(() {
      _stitchedImage = bytes;
    });
    if (!success) {
      throw Exception("Failed to encode image");
    }
    var cnts =
        cv.findContours(dilate, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    var contours = cnts.$1;

    for (var contour in contours) {
      var rect = cv.boundingRect(contour);
      _contours.add(
        Rect(
          (rect.x / ratio).toInt(),
          (rect.y / ratio).toInt(),
          (rect.width / ratio).toInt(),
          (rect.height / ratio).toInt(),
        ),
      );
    }
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
            SizedBox(
              width: imageWidth.toDouble(),
              height: imageHeight.toDouble(),
              child: Stack(
                children: <Widget>[
                  _image != null
                      ? Positioned.fill(
                          child: Image.file(_image!),
                        )
                      : Text('No image selected'),
                  Positioned.fill(
                    child: Stack(
                      alignment: Alignment.center,
                      children: _contours.map((rect) {
                        return Positioned(
                          left: rect.x.toDouble(),
                          top: rect.y.toDouble(),
                          width: rect.width.toDouble(),
                          height: rect.height.toDouble(),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.red, width: 2.0),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  )
                ],
              ),
            ),
            Card(
              child: _stitchedImage == null
                  ? Placeholder()
                  : Image.memory(_stitchedImage!),
            ),
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
