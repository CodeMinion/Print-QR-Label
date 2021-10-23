import 'dart:typed_data';

import 'package:another_brother/printer_info.dart';
import 'package:another_brother/type_b_commands.dart';
import 'package:another_brother/type_b_printer.dart';
import 'package:flutter/material.dart';
import 'package:flutterqrprintsample/models/printer_setings_model.dart';
import 'package:flutterqrprintsample/pages/printing/printer_settings_card.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import 'package:permission_handler/permission_handler.dart';

import 'package:qr_flutter/qr_flutter.dart';


void main() {
  PrinterSettingsModel printerSettings = PrinterSettingsModel();
  runApp(MultiProvider(
      providers: [ChangeNotifierProvider.value(value: printerSettings)],
      child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Another_Brother: Print QR'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

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
  int _counter = 0;


  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
              onPressed: () {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (BuildContext context) {
                  return PrinterConfigurationPage();
                }));
              },
              icon: Icon(Icons.settings))
        ],
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: FutureBuilder(
          future: _getWidgetImage(),
          builder: (BuildContext context, AsyncSnapshot<ByteData> snapshot) {

            if(snapshot.hasData) {
              return Image.memory(Uint8List.view(snapshot.data!.buffer));
            }

            return CircularProgressIndicator();
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {_print(context);},
        tooltip: 'Print',
        child: const Icon(Icons.print),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  Future<void> _print(BuildContext context) async {

    // Request Permissions if they have not been granted.
    // Note: If storage permission is not granted printing will fail
    // with ERROR_WRONG_LABEL
    if (!await Permission.storage.request().isGranted) {
      _showSnack(context,
          "Access to storage is needed in order print.",
          duration: Duration(seconds: 2));
      return;
    }

    // TODO Replace this by the image generation method.
    ui.Image imageToPrint = await _generateImage();

    PrinterSettingsModel printerSettingsModel = context.read();

    // If printing to a TypeB pinter
    if (printerSettingsModel.configuredPrinterModel is TbModel) {
      ATbLabelName configuredPaper = printerSettingsModel.tbPrinterInfo.labelName;
      TbPrinter printer = TbPrinter();
      await printer.setPrinterInfo(printerSettingsModel.tbPrinterInfo);
      bool success = false;
      success = await printer.startCommunication();
      success = success && await printer.setup(
          width: configuredPaper.getWidth(),
          height: configuredPaper.getHeight());
      success = success && await printer.clearBuffer();
      success =
          success && await printer.downloadImage(imageToPrint);
      success = success && await printer.printLabel();
      TbPrinterStatus printerStatus = await printer.printerStatus();
      // Delete all files downloaded to the printer memory
      success = success && await printer.sendTbCommand(TbCommandDeleteFile());
      success = success && await printer.endCommunication(timeoutMillis: 5000);
      // TODO On Error show toast.
      if (!success) {
        _showSnack(context,
            "Print failed with error code: ${printerStatus.getStatusValue()}",
            duration: Duration(seconds: 2));
      }


    }

    // Otherwise we are printing to a standard printer.
    else {
      Printer printer = new Printer();
      printer.setPrinterInfo(printerSettingsModel.printerInfo);
      print("Printer - ${printerSettingsModel.printerInfo.customPaper}");
      PrinterStatus status = await printer.printImage(imageToPrint);

      if (status.errorCode != ErrorCode.ERROR_NONE) {
        // Show toast with error.
        _showSnack(context,
            "Print failed with error code: ${status.errorCode.getName()}",
            duration: Duration(seconds: 2));
      }
    }
  }

  void _showSnack(BuildContext context, String content, {Duration duration = const Duration(seconds: 1)}) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: duration,
          content: Container(
            padding: EdgeInsets.all(8.0),
            child: Text(content),
          ),
        ));
  }

  Future<ui.Image> _generateImage() async {
    ui.PictureRecorder recorder = ui.PictureRecorder();
    Canvas canvas = Canvas(recorder);

    double baseSize = 200;
    double labelWidthPx = 9 * baseSize;
    double labelHeightPx = 3 * baseSize;
    double qrSizePx = labelHeightPx / 2;
    // Start Padding of the QR Code
    double qrPaddingStart = 30;
    // Start Padding of the Paragraph in relation to the QR Code
    double paraPaddingStart = 30;
    // Font Size for largest text
    double primaryFontSize = 100;

    Paint paint = new Paint();
    paint.color = Color.fromRGBO(255, 255, 255, 1);
    Rect bounds = new Rect.fromLTWH(0, 0, labelWidthPx, labelHeightPx);
    canvas.save();
    canvas.drawRect(bounds, paint);

    //
    // TODO Create QR Code
    final qrImage = await QrPainter(
      dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
      eyeStyle: QrEyeStyle( eyeShape: QrEyeShape.square, color: Colors.black),
      data: "another_brother",
      version: QrVersions.auto,
      gapless: true,
    ).toImage(qrSizePx);

    // Draw QR Code
    // Center the QR vertically with a 20 px pading on start
    Offset qrOffset = Offset(qrPaddingStart, (labelHeightPx -qrSizePx) / 2);
    canvas.drawImage(qrImage, qrOffset, paint);

    // Create Paragraph
    ui.ParagraphBuilder paraBuilder = ui.ParagraphBuilder(new ui.ParagraphStyle(textAlign: TextAlign.start));
    // Add heading to paragraph
    paraBuilder.pushStyle(ui.TextStyle(fontSize: primaryFontSize, color: Colors.black, fontWeight: FontWeight.bold));
    paraBuilder.addText("Another_Brother\n");
    paraBuilder.pop();
    // Add seconds line
    paraBuilder.pushStyle(ui.TextStyle(fontSize: primaryFontSize * 0.8, color: Colors.black));
    paraBuilder.addText("Flutter Plugin by\n");
    // Add third line
    paraBuilder.pushStyle(ui.TextStyle(fontSize: primaryFontSize * 0.6, color: Colors.black));
    paraBuilder.addText("CodeMinion");
    Offset paraOffset = qrOffset + Offset(paraPaddingStart + qrSizePx, 0);
    ui.Paragraph infoPara = paraBuilder.build();
    // Layout the pargraph in the remaining space.
    infoPara.layout(ui.ParagraphConstraints(width: labelWidthPx - qrSizePx - qrPaddingStart - paraPaddingStart));
    // Draw paragrpah on canvas.
    canvas.drawParagraph(infoPara, paraOffset);

    var picture = await recorder.endRecording().toImage(9 * 200, 3 * 200);

    return picture;
  }

  Future<ByteData> _getWidgetImage() async {
    ui.Image generatedImage = await _generateImage();
    ByteData? bytes = await generatedImage.toByteData(format: ui.ImageByteFormat.png);
    return bytes!;
  }
}

class PrinterConfigurationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Settings Sample"),
      ),
      body: PrinterSettingsCard(),
    );
  }
}
