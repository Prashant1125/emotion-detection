import 'package:camera/camera.dart';
import 'package:emotion_detection/features/controllers/home_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    var mq = MediaQuery.sizeOf(context);
    final controller = Get.put(HomeController());
    return Scaffold(
      body: Obx(() {
        if (!controller.isCameraInitialized.value) {
          return Center(child: CircularProgressIndicator());
        }

        return Stack(
          children: [
            SizedBox(
              height: double.infinity,
              width: double.infinity,
              child: Obx(() {
                bool hasFace =
                    controller.currentEmotion.value != "No face" &&
                    controller.currentEmotion.value != "Detecting..." &&
                    !controller.currentEmotion.value.startsWith("Err") &&
                    !controller.currentEmotion.value.startsWith("Fmt");

                return Padding(
                  padding: EdgeInsets.all(mq.width * .05),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: hasFace ? Colors.green : Colors.red,
                        width: mq.width * .01,
                      ),
                    ),
                    child: CameraPreview(
                      controller.cameraController,
                      child: Container(
                        alignment: Alignment.bottomCenter,
                        padding: EdgeInsets.only(bottom: 30),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            controller.currentEmotion.value,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      }),
    );
  }
}
